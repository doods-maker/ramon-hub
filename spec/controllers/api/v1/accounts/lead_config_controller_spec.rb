require 'rails_helper'

RSpec.describe 'Lead Config API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }

  it 'retorna stages, benefit_types e priorities da conta' do
    get "/api/v1/accounts/#{account.id}/lead_config",
        headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    body = response.parsed_body
    expect(body['stages'].size).to eq(8)
    expect(body['benefit_types'].size).to eq(7)
    expect(body['priorities'].size).to eq(3)
  end

  it 'expõe a cor de cada etapa' do
    get "/api/v1/accounts/#{account.id}/lead_config",
        headers: admin.create_new_auth_token, as: :json
    novo = response.parsed_body['stages'].find { |s| s['name'] == 'Novo' }
    expect(novo['color']).to eq('#6b7280')
  end

  it 'retorna as origens distintas ordenadas' do
    stage = account.lead_stages.first
    account.leads.create!(name: 'A', lead_stage: stage, source: 'Meta Ads')
    account.leads.create!(name: 'B', lead_stage: stage, source: 'Indicação')
    account.leads.create!(name: 'C', lead_stage: stage, source: 'Meta Ads')
    account.leads.create!(name: 'D', lead_stage: stage, source: nil)
    get "/api/v1/accounts/#{account.id}/lead_config", headers: admin.create_new_auth_token
    expect(response.parsed_body['sources']).to eq(['Indicação', 'Meta Ads'])
  end
end
