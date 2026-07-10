require 'rails_helper'

RSpec.describe 'Lead Dossiê API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:lead) { create(:lead, account: account) }

  describe 'GET /api/v1/accounts/:account_id/leads/:id/dossie' do
    it 'retorna o dossiê agregado do lead' do
      get "/api/v1/accounts/#{account.id}/leads/#{lead.id}/dossie",
          headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body.keys).to include('pessoa', 'origem', 'triagem', 'tese', 'timeline', 'pendencias')
      expect(body['pessoa']['lead_id']).to eq(lead.id)
      expect(body['pessoa']['stage_name']).to eq(lead.lead_stage.name)
    end

    it 'retorna 401 sem autenticação' do
      get "/api/v1/accounts/#{account.id}/leads/#{lead.id}/dossie", as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it 'retorna 404 para lead de outra conta' do
      stranger = create(:lead)
      get "/api/v1/accounts/#{account.id}/leads/#{stranger.id}/dossie",
          headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end
end
