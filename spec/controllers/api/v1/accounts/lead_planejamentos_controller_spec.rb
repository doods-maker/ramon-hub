require 'rails_helper'

RSpec.describe 'Lead Planejamentos API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:lead) { create(:lead, account: account) }
  let(:motor_url) { 'http://motor:8000' }
  let(:cnis_entrada) do
    {
      'segurado' => { 'nascimento' => '1975-01-20', 'sexo' => 'F' },
      'competencias' => [{ 'ano' => 2023, 'mes' => 5, 'salario' => '2500.00' }],
      'vinculos' => [{ 'inicio' => '2005-01-01', 'fim' => '2020-12-31', 'tipo' => 'EMPREGO', 'indicadores' => [] }]
    }
  end
  let(:motor_body) { { data_calculo: '2026-07-24', cenarios: [], decisoes_pendentes: [], avisos: [] }.to_json }

  def planejar(params = {}, headers = admin.create_new_auth_token, caminho = 'planejamento')
    post "/api/v1/accounts/#{account.id}/leads/#{lead.id}/#{caminho}",
         params: params, headers: headers, as: :json
  end

  it 'returns unauthorized without auth' do
    planejar({}, {})
    expect(response).to have_http_status(:unauthorized)
  end

  it 'returns unauthorized for an agent of another account' do
    other_account = create(:account)
    other_admin = create(:user, account: other_account, role: :administrator)
    planejar({}, other_admin.create_new_auth_token)
    expect(response).to have_http_status(:unauthorized)
  end

  it 'returns service unavailable sem MOTOR_CALCULOS_URL' do
    planejar
    expect(response).to have_http_status(:service_unavailable)
  end

  context 'when the motor responds' do
    before do
      stub_request(:post, "#{motor_url}/planejamento")
        .to_return(status: 200, body: motor_body, headers: { 'Content-Type' => 'application/json' })
      lead.update!(cnis: { 'entrada' => cnis_entrada })
    end

    it 'proxies o payload com segurado/competencias/vinculos do CNIS + cenarios/data_calculo/horizonte_anos' do
      with_modified_env MOTOR_CALCULOS_URL: motor_url do
        planejar(data_calculo: '2026-08-01', horizonte_anos: 10,
                 cenarios: [{ nome: 'A', salario: '3000.00', aliquota: '20' }])
      end
      expect(response).to have_http_status(:success)
      matcher = have_requested(:post, "#{motor_url}/planejamento").with do |req|
        body = JSON.parse(req.body)
        body['segurado'] == cnis_entrada['segurado'] &&
          body['competencias'] == cnis_entrada['competencias'] &&
          body['vinculos'] == cnis_entrada['vinculos'] &&
          body['data_calculo'] == '2026-08-01' &&
          body['horizonte_anos'] == 10 &&
          body['cenarios'] == [{ 'nome' => 'A', 'salario' => '3000.00', 'aliquota' => '20' }]
      end
      expect(WebMock).to matcher
    end

    it 'nao envia campos opcionais ausentes' do
      with_modified_env MOTOR_CALCULOS_URL: motor_url do
        planejar
      end
      matcher = have_requested(:post, "#{motor_url}/planejamento").with do |req|
        body = JSON.parse(req.body)
        !body.key?('data_calculo') && !body.key?('cenarios') && !body.key?('horizonte_anos')
      end
      expect(WebMock).to matcher
    end

    it 'falls back to the contact nascimento/sexo when there is no CNIS' do
      lead.update!(cnis: nil, contact: create(:contact, account: account, data_nascimento: '1980-05-10', sexo: 'M'))
      with_modified_env MOTOR_CALCULOS_URL: motor_url do
        planejar
      end
      expect(response).to have_http_status(:success)
      matcher = have_requested(:post, "#{motor_url}/planejamento").with do |req|
        JSON.parse(req.body)['segurado'] == { 'nascimento' => '1980-05-10', 'sexo' => 'M' }
      end
      expect(WebMock).to matcher
    end
  end

  it 'repassa o detail 422 do motor' do
    stub_request(:post, "#{motor_url}/planejamento")
      .to_return(status: 422, body: { detail: 'cenarios excede o maximo de 10' }.to_json,
                 headers: { 'Content-Type' => 'application/json' })
    with_modified_env MOTOR_CALCULOS_URL: motor_url do
      planejar
    end
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to include('cenarios excede o maximo de 10')
  end

  describe 'POST /planejamento/pdf' do
    before { lead.update!(cnis: { 'entrada' => cnis_entrada }) }

    it 'devolve o PDF do motor como attachment com segurado_nome default do contato' do
      contact = create(:contact, account: account, name: 'Fulano de Tal')
      lead.update!(contact: contact)
      stub_request(:post, "#{motor_url}/planejamento/pdf")
        .to_return(status: 200, body: '%PDF-1.7 fake', headers: { 'Content-Type' => 'application/pdf' })
      with_modified_env MOTOR_CALCULOS_URL: motor_url do
        planejar({}, admin.create_new_auth_token, 'planejamento/pdf')
      end
      expect(response).to have_http_status(:success)
      expect(response.headers['Content-Type']).to include('application/pdf')
      expect(response.body).to start_with('%PDF')
      matcher = have_requested(:post, "#{motor_url}/planejamento/pdf").with do |req|
        JSON.parse(req.body)['segurado_nome'] == 'Fulano de Tal'
      end
      expect(WebMock).to matcher
    end

    it 'usa segurado_nome explicito quando enviado' do
      stub_request(:post, "#{motor_url}/planejamento/pdf")
        .to_return(status: 200, body: '%PDF-1.7 fake', headers: { 'Content-Type' => 'application/pdf' })
      with_modified_env MOTOR_CALCULOS_URL: motor_url do
        planejar({ segurado_nome: 'Ciclana' }, admin.create_new_auth_token, 'planejamento/pdf')
      end
      matcher = have_requested(:post, "#{motor_url}/planejamento/pdf").with do |req|
        JSON.parse(req.body)['segurado_nome'] == 'Ciclana'
      end
      expect(WebMock).to matcher
    end

    it 'returns service unavailable sem MOTOR_CALCULOS_URL' do
      planejar({}, admin.create_new_auth_token, 'planejamento/pdf')
      expect(response).to have_http_status(:service_unavailable)
    end
  end
end
