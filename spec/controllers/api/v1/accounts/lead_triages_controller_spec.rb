require 'rails_helper'

RSpec.describe 'Lead Triages API', type: :request do
  let(:account) { create(:account) }
  let(:agent_user) { create(:user, account: account, role: :agent) }
  let(:lead) { create(:lead, account: account) }

  describe 'POST /api/v1/accounts/:account_id/leads/:lead_id/triages' do
    it 'cria a triagem pending com o agente default e enfileira o job' do
      expect do
        post "/api/v1/accounts/#{account.id}/leads/#{lead.id}/triages",
             headers: agent_user.create_new_auth_token, as: :json
      end.to have_enqueued_job(Leads::TriageJob)
      expect(response).to have_http_status(:success)
      triage = lead.lead_triages.order(:id).last
      expect(triage.status).to eq('pending')
      expect(triage.triage_agent).to eq(account.triage_agents.active.first)
    end

    it 'aceita triage_agent_id explícito' do
      other = account.triage_agents.create!(name: 'Outro', system_prompt: 'p')
      post "/api/v1/accounts/#{account.id}/leads/#{lead.id}/triages",
           params: { triage_agent_id: other.id }, headers: agent_user.create_new_auth_token, as: :json
      expect(lead.lead_triages.order(:id).last.triage_agent).to eq(other)
    end

    it 'retorna 404 sem nenhum agente ativo' do
      account.triage_agents.update_all(active: false) # rubocop:disable Rails/SkipsModelValidations
      post "/api/v1/accounts/#{account.id}/leads/#{lead.id}/triages",
           headers: agent_user.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it 'expira triagens órfãs (pending/running paradas há +10min) e ignora as recentes' do
      agent = account.triage_agents.first
      stale = lead.lead_triages.create!(account: account, triage_agent: agent, status: 'running')
      stale.update_column(:updated_at, 20.minutes.ago) # rubocop:disable Rails/SkipsModelValidations
      fresh = lead.lead_triages.create!(account: account, triage_agent: agent, status: 'running')

      post "/api/v1/accounts/#{account.id}/leads/#{lead.id}/triages",
           headers: agent_user.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(stale.reload.status).to eq('error')
      expect(stale.error_message).to eq('Triagem expirada (worker interrompido)')
      expect(fresh.reload.status).to eq('running')
    end
  end

  describe 'GET .../triages' do
    it 'lista as triagens do lead, mais recente primeiro' do
      agent = account.triage_agents.first
      old = lead.lead_triages.create!(account: account, triage_agent: agent)
      newer = lead.lead_triages.create!(account: account, triage_agent: agent, status: 'done', viability: 'alta')
      get "/api/v1/accounts/#{account.id}/leads/#{lead.id}/triages",
          headers: agent_user.create_new_auth_token, as: :json
      body = response.parsed_body
      expect(body.pluck('id')).to eq([newer.id, old.id])
      expect(body.first['viability']).to eq('alta')
    end
  end

  it 'nega acesso sem login' do
    get "/api/v1/accounts/#{account.id}/leads/#{lead.id}/triages", as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  describe 'POST .../triages/:id/kit' do
    it 'enfileira o KitJob, marca running e devolve a triagem' do
      agent = account.triage_agents.first
      triage = lead.lead_triages.create!(account: account, triage_agent: agent, status: 'done', result: 'ok')

      expect do
        post "/api/v1/accounts/#{account.id}/leads/#{lead.id}/triages/#{triage.id}/kit",
             headers: agent_user.create_new_auth_token, as: :json
      end.to have_enqueued_job(Leads::KitJob).with(triage.id)
      expect(response).to have_http_status(:success)
      expect(triage.reload.kit_status).to eq('running')
      expect(response.parsed_body['kit_status']).to eq('running')
    end

    it 'recusa quando a triagem não está done' do
      agent = account.triage_agents.first
      pending_triage = lead.lead_triages.create!(account: account, triage_agent: agent, status: 'running')
      post "/api/v1/accounts/#{account.id}/leads/#{lead.id}/triages/#{pending_triage.id}/kit",
           headers: agent_user.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
