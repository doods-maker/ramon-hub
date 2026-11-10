require 'rails_helper'

RSpec.describe 'Lead Planejamentos API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:lead) { create(:lead, account: account) }
  let(:motor_url) { 'http://motor:8000' }
  let(:cnis) do
    {
      'entrada' => {
        'segurado' => { 'nascimento' => '1975-01-20', 'sexo' => 'F' },
        'competencias' => [{ 'ano' => 2023, 'mes' => 5, 'salario' => '2500.00' }],
        'vinculos' => [{ 'inicio' => '2005-01-01', 'fim' => '2020-12-31', 'tipo' => 'EMPREGO', 'indicadores' => [] }]
      },
      'vinculos' => [{ 'empresa' => 'Empresa Ficticia' }]
    }
  end
  let(:motor_body) do
    { dados: { nome: 'Ana' }, memoria_xlsx_b64: 'eA==', forma_sugerida: { forma: 'carne_20' }, avisos: [] }.to_json
  end
  let(:base) { "/api/v1/accounts/#{account.id}/leads/#{lead.id}/planejamento" }

  def planejar(params = {}, headers = admin.create_new_auth_token, caminho = '')
    post "#{base}#{caminho}", params: params, headers: headers, as: :json
  end

  it 'returns unauthorized without auth' do
    planejar({}, {})
    expect(response).to have_http_status(:unauthorized)
  end

  it 'returns unauthorized for an agent of another account' do
    other_admin = create(:user, account: create(:account), role: :administrator)
    planejar({}, other_admin.create_new_auth_token)
    expect(response).to have_http_status(:unauthorized)
  end

  describe 'POST /planejamento (calcular)' do
    before { lead.update!(cnis: cnis) }

    def stub_motor
      stub_request(:post, "#{motor_url}/planejamento/previdenciario")
        .to_return(status: 200, body: motor_body, headers: { 'Content-Type' => 'application/json' })
    end

    it 'repassa o corpo do payload e tira a memória da resposta' do
      stub_motor
      with_modified_env MOTOR_CALCULOS_URL: motor_url do
        planejar(perfil: { forma: 'carne_20' })
      end
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.keys).to match_array(%w[dados forma_sugerida avisos])
      matcher = have_requested(:post, "#{motor_url}/planejamento/previdenciario").with do |req|
        body = JSON.parse(req.body)
        body['perfil']['forma'] == 'carne_20' && body['vinculos_detalhe'] == cnis['vinculos']
      end
      expect(WebMock).to matcher
    end

    it 'sem CNIS devolve 422 pedindo o CNIS' do
      lead.update!(cnis: nil)
      planejar
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('Anexe o CNIS para montar o planejamento.')
    end

    it 'motor desatualizado (404) vira 503 com a mensagem' do
      stub_request(:post, "#{motor_url}/planejamento/previdenciario").to_return(status: 404, body: '{}')
      with_modified_env MOTOR_CALCULOS_URL: motor_url do
        planejar
      end
      expect(response).to have_http_status(:service_unavailable)
      expect(response.parsed_body['error']).to match(/motor de cálculos desatualizado/)
    end

    it 'não grava histórico' do
      stub_motor
      with_modified_env MOTOR_CALCULOS_URL: motor_url do
        expect { planejar(perfil: { forma: 'carne_20' }) }.not_to change(Calculo, :count)
      end
    end
  end

  describe 'POST /planejamento/gerar' do
    let(:dados) do
      { 'nome' => 'Ana', 'cenarios' => [{ 'rmi' => 2234.62, 'sugestao' => true, 'bom' => %w[a b], 'vazio' => [] }],
        'pendencias' => [], 'sugestao' => { 'itens' => ['x'] } }
    end

    before { lead.update!(cnis: cnis) }

    it 'grava o dados editado inteiro no histórico e enfileira o job' do
      expect { planejar({ perfil: { forma: 'pro_labore' }, dados: dados }, admin.create_new_auth_token, '/gerar') }
        .to have_enqueued_job(Ramon::PlanejamentoGerarJob)
      calculo = Calculo.last
      expect(response).to have_http_status(:accepted)
      expect(response.parsed_body).to eq('calculo_id' => calculo.id)
      expect(calculo.snapshot['params']['dados']).to eq(dados)
      expect(calculo.snapshot['params']['perfil']).to eq('forma' => 'pro_labore')
      expect(calculo.snapshot['geracao']).to eq('estado' => 'gerando')
      expect(calculo.snapshot['valor']).to eq(2234.62)
    end

    it 'sem registro do histórico devolve 503' do
      allow(Calculo).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)
      planejar({ perfil: {}, dados: dados }, admin.create_new_auth_token, '/gerar')
      expect(response).to have_http_status(:service_unavailable)
    end
  end

  describe 'GET /planejamento/geracao e /arquivo' do
    let(:calculo) do
      Calculo.create!(account: account, lead: lead, user: admin, tipo: 'planejamento',
                      snapshot: { 'params' => { 'dados' => { 'nome' => 'Ana' } }, 'geracao' => { 'estado' => 'pronto' } })
    end
    let(:outro) do
      Calculo.create!(account: account, lead: create(:lead, account: account), user: admin, tipo: 'planejamento')
    end

    def pegar(caminho, query)
      get "#{base}#{caminho}", params: query, headers: admin.create_new_auth_token, as: :json
    end

    it 'geracao devolve o estado' do
      pegar('/geracao', calculo_id: calculo.id)
      expect(response.parsed_body).to eq('estado' => 'pronto')
    end

    it 'geracao de cálculo de outro lead dá 404' do
      pegar('/geracao', calculo_id: outro.id)
      expect(response).to have_http_status(:not_found)
    end

    it 'arquivo devolve o PDF com o nome do Drive' do
      Redis::Alfred.setex(Ramon::PlanejamentoPrevidenciario.chave(calculo, 'pdf'), Base64.strict_encode64('%PDF-fake'), 1.hour)
      pegar('/arquivo', calculo_id: calculo.id, tipo: 'pdf')
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq('%PDF-fake')
      expect(response.headers['Content-Disposition']).to include('Planejamento previdenci')
      expect(response.headers['Content-Type']).to include('application/pdf')
    end

    it 'arquivo expirado dá 404' do
      pegar('/arquivo', calculo_id: calculo.id, tipo: 'memoria')
      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body['error']).to eq('arquivo expirou — gere de novo')
    end

    it 'arquivo de cálculo de outro lead dá 404' do
      pegar('/arquivo', calculo_id: outro.id, tipo: 'pdf')
      expect(response).to have_http_status(:not_found)
    end
  end
end
