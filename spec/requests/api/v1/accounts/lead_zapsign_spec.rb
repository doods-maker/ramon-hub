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
end
