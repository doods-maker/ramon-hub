require 'rails_helper'

RSpec.describe 'Lead Tasks API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:lead) { create(:lead, account: account) }

  it 'lists a lead tasks ordered by due date' do
    lead.lead_tasks.create!(account: account, title: 'depois', kind: 'follow_up', due_at: 3.days.from_now)
    lead.lead_tasks.create!(account: account, title: 'antes', kind: 'meeting', due_at: 1.day.from_now)
    get "/api/v1/accounts/#{account.id}/leads/#{lead.id}/tasks",
        headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    expect(response.parsed_body['payload'].map { |t| t['title'] }).to eq(%w[antes depois])
  end

  it 'creates a task authored by the current user' do
    expect do
      post "/api/v1/accounts/#{account.id}/leads/#{lead.id}/tasks",
           params: { title: 'Ligar', kind: 'follow_up', due_at: 1.day.from_now },
           headers: agent.create_new_auth_token, as: :json
    end.to change(lead.lead_tasks, :count).by(1)
    expect(response).to have_http_status(:success)
    expect(response.parsed_body['title']).to eq('Ligar')
    expect(response.parsed_body['user_id']).to eq(agent.id)
    expect(response.parsed_body['lead_name']).to eq(lead.name)
  end

  it 'updates a task' do
    task = create(:lead_task, account: account, lead: lead, title: 'antigo')
    patch "/api/v1/accounts/#{account.id}/leads/#{lead.id}/tasks/#{task.id}",
          params: { title: 'novo' }, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    expect(task.reload.title).to eq('novo')
  end

  it 'completes a task and stamps completed_at' do
    task = create(:lead_task, account: account, lead: lead)
    post "/api/v1/accounts/#{account.id}/leads/#{lead.id}/tasks/#{task.id}/complete",
         headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    expect(task.reload.completed_at).to be_present
    expect(response.parsed_body['completed_at']).to be_present
  end

  it 'destroys a task' do
    task = create(:lead_task, account: account, lead: lead)
    expect do
      delete "/api/v1/accounts/#{account.id}/leads/#{lead.id}/tasks/#{task.id}",
             headers: agent.create_new_auth_token, as: :json
    end.to change(lead.lead_tasks, :count).by(-1)
    expect(response).to have_http_status(:success)
  end

  it 'denies a user without access to the account' do
    stranger = create(:user)
    get "/api/v1/accounts/#{account.id}/leads/#{lead.id}/tasks",
        headers: stranger.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it 'filters the account collection by scope=overdue' do
    create(:lead_task, account: account, lead: lead, title: 'atrasada', due_at: 2.days.ago)
    create(:lead_task, account: account, lead: lead, title: 'futura', due_at: 2.days.from_now)
    get "/api/v1/accounts/#{account.id}/lead_tasks",
        params: { scope: 'overdue' }, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    titles = response.parsed_body['payload'].map { |t| t['title'] }
    expect(titles).to eq(['atrasada'])
    expect(response.parsed_body['payload'].first['lead_name']).to eq(lead.name)
  end
end
