require 'rails_helper'

RSpec.describe 'Calculos API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:lead) { create(:lead, account: account) }
  let(:cnis) do
    {
      'entrada' => { 'segurado' => { 'nascimento' => '1980-05-10', 'sexo' => 'F' }, 'competencias' => [] },
      'vinculos' => [{ 'seq' => 1, 'tipo' => 'EMPREGO' }],
      'filename' => 'cnis.pdf',
      'segurado_nome' => 'MARIA DAS DORES',
      'segurado_cpf' => '52998224725'
    }
  end

  def cria_calculo(nome: 'MARIA DAS DORES', tipo: 'painel', snapshot_cnis: nil)
    Calculo.create!(account: account, lead: lead, user: agent, tipo: tipo, segurado_nome: nome,
                    segurado_cpf: '52998224725', der: '2026-03-10',
                    snapshot: { 'params' => { 'der' => '2026-03-10' }, 'cnis' => snapshot_cnis })
  end

  describe 'GET /calculos' do
    let(:url) { "/api/v1/accounts/#{account.id}/calculos" }

    it 'exige login' do
      get url
      expect(response).to have_http_status(:unauthorized)
    end

    it 'lista com cliente, tipo e data/hora, do mais novo pro mais velho' do
      antigo = cria_calculo(tipo: 'honorario')
      antigo.update!(created_at: 2.days.ago)
      novo = cria_calculo(tipo: 'painel')

      get url, headers: agent.create_new_auth_token, as: :json
      payload = response.parsed_body['payload']
      expect(payload.map { |c| c['id'] }).to eq([novo.id, antigo.id])
      expect(payload.first).to include('segurado_nome' => 'MARIA DAS DORES', 'tipo' => 'painel',
                                       'der' => '2026-03-10', 'user_name' => agent.name)
      expect(payload.first['created_at']).to be_present
    end

    it 'filtra por nome do cliente e por CPF digitado com pontuação' do
      maria = cria_calculo
      cria_calculo(nome: 'JOÃO PEDRO')

      get url, params: { q: 'maria' }, headers: agent.create_new_auth_token, as: :json
      expect(response.parsed_body['payload'].map { |c| c['id'] }).to eq([maria.id])

      get url, params: { q: '529.982.247-25' }, headers: agent.create_new_auth_token, as: :json
      expect(response.parsed_body['payload'].length).to eq(2)
    end
  end

  describe 'POST /calculos/:id/reabrir' do
    it 'devolve o CNIS ao caso e responde com os parâmetros do cálculo' do
      calculo = cria_calculo(snapshot_cnis: cnis)
      lead.update!(cnis: nil)

      post "/api/v1/accounts/#{account.id}/calculos/#{calculo.id}/reabrir",
           headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      corpo = response.parsed_body
      expect(corpo['lead_id']).to eq(lead.id)
      expect(corpo['tipo']).to eq('painel')
      expect(corpo.dig('params', 'der')).to eq('2026-03-10')
      expect(corpo.dig('cnis', 'filename')).to eq('cnis.pdf')
      # é o servidor que lê lead.cnis na hora de recalcular
      expect(lead.reload.cnis['filename']).to eq('cnis.pdf')
    end
  end

  describe 'DELETE /calculos/:id' do
    it 'apaga o registro' do
      calculo = cria_calculo
      delete "/api/v1/accounts/#{account.id}/calculos/#{calculo.id}",
             headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:no_content)
      expect(Calculo.exists?(calculo.id)).to be(false)
    end
  end

  describe 'POST /calculos/:id/reabrir — destino seguro' do
    let(:outro) { create(:user, account: account, role: :agent) }
    let(:rascunho_do_outro) { Lead.rascunho_de!(account, outro) }

    def reabrir(calculo, params = {})
      post "/api/v1/accounts/#{account.id}/calculos/#{calculo.id}/reabrir",
           params: params, headers: agent.create_new_auth_token, as: :json
    end

    it 'cálculo rápido de outra pessoa volta no MEU rascunho e não mexe no dela' do
      rascunho_do_outro.update!(cnis: { 'filename' => 'atual-do-outro.pdf' })
      calculo = Calculo.create!(account: account, lead: rascunho_do_outro, user: outro, tipo: 'painel',
                                snapshot: { 'params' => { 'der' => '2026-03-10' }, 'cnis' => cnis })

      reabrir(calculo)

      meu = Lead.rascunho_de!(account, agent)
      expect(response.parsed_body['lead_id']).to eq(meu.id)
      expect(meu.reload.cnis['filename']).to eq('cnis.pdf')
      expect(rascunho_do_outro.reload.cnis['filename']).to eq('atual-do-outro.pdf')
    end

    it 'de lead real com destino=rascunho copia pro meu rascunho (com a tese) e deixa o lead intacto' do
      tese = create(:thesis, account: account)
      lead.update!(cnis: { 'filename' => 'cnis-atual.pdf' }, thesis: tese)
      calculo = cria_calculo(snapshot_cnis: cnis)

      reabrir(calculo, destino: 'rascunho')

      meu = Lead.rascunho_de!(account, agent)
      expect(response.parsed_body).to include('lead_id' => meu.id, 'thesis_id' => tese.id)
      expect(meu.reload.cnis['filename']).to eq('cnis.pdf')
      expect(lead.reload.cnis['filename']).to eq('cnis-atual.pdf')
    end
  end

  describe 'POST /calculos/:id/vincular' do
    let(:cliente) { create(:lead, account: account, contact: create(:contact, account: account, name: 'João Carlos Pereira')) }

    def vincular(calculo, params = {})
      post "/api/v1/accounts/#{account.id}/calculos/#{calculo.id}/vincular",
           params: { lead_id: cliente.id }.merge(params), headers: agent.create_new_auth_token, as: :json
    end

    it 'leva o CNIS do cálculo rápido pro cliente e o cálculo passa a ser dele' do
      calculo = Calculo.create!(account: account, lead: Lead.rascunho_de!(account, agent), user: agent,
                                tipo: 'painel', snapshot: { 'params' => { 'der' => '2026-03-10' }, 'cnis' => cnis })

      vincular(calculo)

      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to include('lead_id' => cliente.id, 'tipo' => 'painel')
      expect(cliente.reload.cnis['filename']).to eq('cnis.pdf')
      expect(calculo.reload.lead_id).to eq(cliente.id)
      expect(calculo.segurado_nome).to eq('João Carlos Pereira')
    end

    it 'não sobrescreve outro CNIS do cliente sem substituir=true' do
      cliente.update!(cnis: { 'filename' => 'cnis-do-cliente.pdf' })
      calculo = cria_calculo(snapshot_cnis: cnis)

      vincular(calculo)
      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body['error']).to eq('LEAD_TEM_CNIS')
      expect(cliente.reload.cnis['filename']).to eq('cnis-do-cliente.pdf')

      vincular(calculo, substituir: true)
      expect(response).to have_http_status(:success)
      expect(cliente.reload.cnis['filename']).to eq('cnis.pdf')
    end
  end

  describe 'gravação automática' do
    it 'painel calculado vira registro com CNIS e nome do segurado' do
      lead.update!(cnis: cnis)
      stub_request(:post, 'http://motor:8000/painel')
        .to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                   body: { resumo: {}, cartoes: [], avisos: [] }.to_json)

      expect do
        with_modified_env MOTOR_CALCULOS_URL: 'http://motor:8000' do
          post "/api/v1/accounts/#{account.id}/leads/#{lead.id}/painel",
               params: { der: '2026-03-10', nascimento: '1980-05-10', sexo: 'F' },
               headers: agent.create_new_auth_token, as: :json
        end
      end.to change(Calculo, :count).by(1)

      calculo = Calculo.last
      expect(calculo.tipo).to eq('painel')
      expect(calculo.der.to_s).to eq('2026-03-10')
      expect(calculo.segurado_nome).to eq('MARIA DAS DORES')
      expect(calculo.cnis_snapshot['filename']).to eq('cnis.pdf')
    end

    it 'nome digitado na tela vence o do CNIS no registro' do
      lead.update!(cnis: cnis)
      stub_request(:post, 'http://motor:8000/painel')
        .to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                   body: { resumo: {}, cartoes: [], avisos: [] }.to_json)

      with_modified_env MOTOR_CALCULOS_URL: 'http://motor:8000' do
        post "/api/v1/accounts/#{account.id}/leads/#{lead.id}/painel",
             params: { der: '2026-03-10', nascimento: '1980-05-10', sexo: 'F', segurado_nome: 'Dona Zilda' },
             headers: agent.create_new_auth_token, as: :json
      end

      expect(Calculo.last.segurado_nome).to eq('Dona Zilda')
    end
  end
end
