require 'rails_helper'

RSpec.describe 'Triage Agents API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent_user) { create(:user, account: account, role: :agent) }

  it 'agent lê a lista' do
    get "/api/v1/accounts/#{account.id}/triage_agents",
        headers: agent_user.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    expect(response.parsed_body.pluck('name')).to include('Triagem Previdenciária — Auxílio-Acidente')
  end

  it 'agent NÃO edita (escrita admin-only)' do
    target = account.triage_agents.first
    patch "/api/v1/accounts/#{account.id}/triage_agents/#{target.id}",
          params: { sensitive: true }, headers: agent_user.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it 'admin edita o toggle sensitive e o provider' do
    target = account.triage_agents.first
    patch "/api/v1/accounts/#{account.id}/triage_agents/#{target.id}",
          params: { sensitive: true, provider: 'anthropic', model: 'claude-haiku-4-5-20251001' },
          headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    expect(target.reload.sensitive).to be(true)
    expect(target.provider).to eq('anthropic')
  end

  it 'admin cria e apaga agente' do
    post "/api/v1/accounts/#{account.id}/triage_agents",
         params: { name: 'Trabalhista', system_prompt: 'p', area: 'trabalhista' },
         headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    created = account.triage_agents.find_by(name: 'Trabalhista')
    delete "/api/v1/accounts/#{account.id}/triage_agents/#{created.id}",
           headers: admin.create_new_auth_token, as: :json
    expect(account.triage_agents.exists?(created.id)).to be(false)
  end
end
