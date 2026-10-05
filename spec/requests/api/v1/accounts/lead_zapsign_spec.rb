require 'rails_helper'

RSpec.describe 'Lead ZapSign API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:lead) { create(:lead, account: account) }

  describe 'GET /api/v1/accounts/:account_id/leads/zapsign_templates' do
    it 'lista os modelos da conta ZapSign' do
      modelos = [{ 'token' => 't1', 'name' => 'Aux. Acidente' }, { 'token' => 't2', 'name' => 'Aposentadoria' }]
      allow(Ramon::ZapsignClient).to receive(:templates).and_return(modelos)

      get "/api/v1/accounts/#{account.id}/leads/zapsign_templates",
          headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to eq(modelos)
    end

    it 'devolve 503 quando o ZapSign está indisponível' do
      allow(Ramon::ZapsignClient).to receive(:templates).and_raise(Ramon::ZapsignClient::UnavailableError, 'sem token')

      get "/api/v1/accounts/#{account.id}/leads/zapsign_templates",
          headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:service_unavailable)
      expect(response.parsed_body['error']).to eq('sem token')
    end

    it 'retorna 401 sem autenticação' do
      get "/api/v1/accounts/#{account.id}/leads/zapsign_templates", as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'POST /api/v1/accounts/:account_id/leads/:lead_id/zapsign' do
    it 'repassa o template_id escolhido pro serviço' do
      allow(Ramon::ZapsignContractService).to receive(:new)
        .with(lead, template_id: 'abc')
        .and_return(instance_double(Ramon::ZapsignContractService, perform: {}))

      post "/api/v1/accounts/#{account.id}/leads/#{lead.id}/zapsign",
           params: { template_id: 'abc' }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(Ramon::ZapsignContractService).to have_received(:new).with(lead, template_id: 'abc')
    end
  end

  describe 'prévia e dados do contrato' do
    let(:contact) { create(:contact, account: account, name: 'Maria', email: 'maria@example.com') }
    let(:lead) { create(:lead, account: account, contact: contact) }
    let(:base) { "/api/v1/accounts/#{account.id}/leads/#{lead.id}/zapsign" }

    it 'GET preview devolve o que sairia em branco sem chamar o ZapSign' do
      get "#{base}/preview", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['faltando']).to include('{{CPF}}', '{{rua}}', '{{número}}')
      expect(response.parsed_body['dados']['email']).to eq('maria@example.com')
    end

    it 'PUT dados grava endereço/estado civil/profissão/e-mail no contato e devolve a prévia nova' do
      endereco = { cep: '88701000', rua: 'Rua A', numero: '10', complemento: '', bairro: 'Centro', cidade: 'Tubarão', uf: 'SC' }
      put "#{base}/dados", params: { endereco: endereco, estado_civil: 'casada', profissao: 'costureira', email: 'nova@example.com' },
                           headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      contact.reload
      expect(contact.custom_attributes['endereco']).to include('cep' => '88701000', 'numero' => '10', 'cidade' => 'Tubarão')
      expect(contact.custom_attributes).to include('estado_civil' => 'casada', 'profissao' => 'costureira')
      expect(contact.email).to eq('nova@example.com')
      expect(response.parsed_body['faltando']).not_to include('{{rua}}', '{{número}}', '{{bairro}}', '{{estado civil}}')
    end

    it 'PUT dados com e-mail inválido devolve 422' do
      put "#{base}/dados", params: { email: 'xx' }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'GET /api/v1/accounts/:account_id/leads/zapsign_cep' do
    def buscar(cep)
      get "/api/v1/accounts/#{account.id}/leads/zapsign_cep", params: { cep: cep }, headers: admin.create_new_auth_token
    end

    it 'preenche rua/bairro/cidade/UF pelo ViaCEP' do
      stub_request(:get, 'https://viacep.com.br/ws/88701000/json/')
        .to_return(status: 200, body: { logradouro: 'Rua Lauro Müller', bairro: 'Centro', localidade: 'Tubarão', uf: 'SC' }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      buscar('88701-000')

      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to include('rua' => 'Rua Lauro Müller', 'bairro' => 'Centro', 'cidade' => 'Tubarão', 'uf' => 'SC')
    end

    it 'CEP inexistente ou mal formado devolve 404' do
      stub_request(:get, 'https://viacep.com.br/ws/99999999/json/')
        .to_return(status: 200, body: { erro: 'true' }.to_json, headers: { 'Content-Type' => 'application/json' })
      buscar('99999999')
      expect(response).to have_http_status(:not_found)
      buscar('123')
      expect(response).to have_http_status(:not_found)
    end

    it 'ViaCEP fora do ar devolve 503' do
      stub_request(:get, 'https://viacep.com.br/ws/88701000/json/').to_timeout
      buscar('88701000')
      expect(response).to have_http_status(:service_unavailable)
    end
  end
end
