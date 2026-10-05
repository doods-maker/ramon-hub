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

  it 'traz o SDR e o Closer do lead em cada tarefa (filtro Minhas | Time)', :aggregate_failures do
    closer = create(:user, account: account, role: :agent, name: 'Clara Closer')
    lead.update!(sdr: agent, closer: closer)
    create(:lead_task, account: account, lead: lead, title: 'reunião', kind: 'meeting', due_at: 1.day.from_now)
    get "/api/v1/accounts/#{account.id}/lead_tasks", headers: agent.create_new_auth_token, as: :json
    row = response.parsed_body['payload'].first
    expect(row['sdr_id']).to eq(agent.id)
    expect(row['sdr_name']).to eq(agent.name)
    expect(row['closer_id']).to eq(closer.id)
    expect(row['closer_name']).to eq('Clara Closer')
  end

  it 'scope=agenda devolve o período (abertas + feitas hoje) e as vencidas abertas', :aggregate_failures do
    create(:lead_task, account: account, lead: lead, title: 'aberta', due_at: 2.days.from_now)
    create(:lead_task, account: account, lead: lead, title: 'feita hoje', due_at: 2.days.from_now, completed_at: Time.current)
    create(:lead_task, account: account, lead: lead, title: 'feita antes', due_at: 2.days.from_now, completed_at: 3.days.ago)
    create(:lead_task, account: account, lead: lead, title: 'vencida', due_at: 20.days.ago)
    create(:lead_task, account: account, lead: lead, title: 'fora', due_at: 30.days.from_now)
    get "/api/v1/accounts/#{account.id}/lead_tasks",
        params: { scope: 'agenda', from: 1.day.from_now.iso8601, to: 7.days.from_now.iso8601 },
        headers: agent.create_new_auth_token
    titles = response.parsed_body['payload'].map { |t| t['title'] }
    expect(titles).to contain_exactly('aberta', 'feita hoje', 'vencida')
  end
end
