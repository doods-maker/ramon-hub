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
      expect(body.keys).to include('pessoa', 'origem', 'triagem', 'tese', 'timeline', 'pendencias', 'passagem', 'passagem_texto')
      expect(body['passagem_texto']).to start_with("DOSSIÊ DE PASSAGEM — #{lead.name}")
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

  describe 'POST /api/v1/accounts/:account_id/leads/:id/dossie_entregue' do
    let(:ganho) { create(:lead, account: account, lead_stage: account.lead_stages.find_by(is_won: true)) }
    let(:url) { "/api/v1/accounts/#{account.id}/leads/#{ganho.id}/dossie_entregue" }

    it 'marca uma vez só e devolve o dossiê com a entrega', :aggregate_failures do
      2.times { post url, headers: agent.create_new_auth_token, as: :json }

      expect(response).to have_http_status(:success)
      expect(ganho.lead_activities.where(kind: 'dossie_entregue').pluck(:user_id)).to eq([agent.id])
      expect(response.parsed_body.dig('passagem', 'entrega', 'entregue_em')).to be_present
      expect(response.parsed_body.dig('passagem', 'entrega', 'por')).to eq(agent.name)
    end
  end
end
