require 'rails_helper'

RSpec.describe 'Ramon Dashboard API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:url) { "/api/v1/accounts/#{account.id}/ramon_dashboard" }
  let(:active_stage) { account.lead_stages.find_by(is_won: false, is_lost: false) }

  it 'lists overdue tasks under today with lead name' do
    lead = create(:lead, account: account, lead_stage: active_stage)
    create(:lead_task, account: account, lead: lead, title: 'Atrasada', due_at: 2.days.ago)
    get url, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    block = response.parsed_body['today']['tasks_overdue']
    expect(block['count']).to eq(1)
    expect(block['items'].first['title']).to eq('Atrasada')
    expect(block['items'].first['lead_name']).to eq(lead.name)
  end

  it 'lists stalled active leads with days_in_stage' do
    lead = create(:lead, account: account, lead_stage: account.lead_stages.find_by(name: 'Novo'))
    lead.update_column(:stage_entered_at, 10.days.ago) # rubocop:disable Rails/SkipsModelValidations
    get url, headers: agent.create_new_auth_token, as: :json
    block = response.parsed_body['today']['stalled']
    expect(block['count']).to eq(1)
    expect(block['items'].first['id']).to eq(lead.id)
    expect(block['items'].first['days_in_stage']).to be >= 9
  end

  it 'counts weekly wins and sums funnel value' do
    won_stage = account.lead_stages.find_by(is_won: true)
    create(:lead, account: account, lead_stage: won_stage, value: 1500)
    get url, headers: agent.create_new_auth_token, as: :json
    expect(response.parsed_body['week']['won']).to eq(1)
    row = response.parsed_body['funnel'].find { |r| r['stage_id'] == won_stage.id }
    expect(row['count']).to eq(1)
    expect(row['total_value']).to eq(1500.0)
    expect(row['total_value']).to be_a(Float)
    empty_row = response.parsed_body['funnel'].find { |r| r['stage_id'] == active_stage.id }
    expect(empty_row['total_value']).to eq(0.0)
    expect(empty_row['weighted_value']).to be_a(Float)
  end

  it 'lists fresh landing-page leads without follow-up' do
    create(:lead, account: account, lead_stage: active_stage, source: 'lp-auxilio-acidente')
    get url, headers: agent.create_new_auth_token, as: :json
    block = response.parsed_body['today']['new_from_lp']
    expect(block['count']).to eq(1)
    expect(block['items'].first['source']).to eq('lp-auxilio-acidente')
  end

  it 'denies a user without access to the account' do
    stranger = create(:user)
    get url, headers: stranger.create_new_auth_token, as: :json
    expect(response).not_to have_http_status(:success)
    expect(response).to have_http_status(:unauthorized).or have_http_status(:not_found)
  end
end
