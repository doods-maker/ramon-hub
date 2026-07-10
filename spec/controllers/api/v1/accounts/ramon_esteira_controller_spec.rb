require 'rails_helper'

RSpec.describe 'Ramon Esteira API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:url) { "/api/v1/accounts/#{account.id}/ramon_esteira" }
  let(:active_stage) { account.lead_stages.find_by(is_won: false, is_lost: false) }

  describe 'GET /ramon_esteira' do
    it 'returns the queue with items and the board' do
      lead = create(:lead, account: account, lead_stage: active_stage, value: 2000)
      create(:lead_task, account: account, lead: lead, title: 'Ligar', due_at: 2.days.ago)
      get url, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      item = response.parsed_body['items'].first
      expect(item['lead_id']).to eq(lead.id)
      expect(item['reasons'].first['key']).to eq('TASK_OVERDUE')
      expect(response.parsed_body['board']).to include('total' => 1, 'value_sum' => 2000.0, 'done_today' => 0)
    end

    it 'denies a user without access to the account' do
      stranger = create(:user)
      get url, headers: stranger.create_new_auth_token, as: :json
      expect(response).not_to have_http_status(:success)
    end
  end

  describe 'POST /ramon_esteira/done' do
    it 'records an esteira_done activity for the lead' do
      lead = create(:lead, account: account, lead_stage: active_stage)
      post "#{url}/done", params: { lead_id: lead.id },
                          headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      activity = lead.lead_activities.where(kind: 'esteira_done').first
      expect(activity).to be_present
      expect(activity.user_id).to eq(agent.id)
    end

    it 'rejects a lead from another account' do
      other_lead = create(:lead)
      post "#{url}/done", params: { lead_id: other_lead.id },
                          headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST /ramon_esteira/snooze' do
    it 'pushes an existing task to tomorrow' do
      lead = create(:lead, account: account, lead_stage: active_stage)
      task = create(:lead_task, account: account, lead: lead, due_at: 3.days.ago)
      post "#{url}/snooze", params: { lead_id: lead.id, task_id: task.id },
                            headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(task.reload.due_at).to be > Time.current
      expect(task.due_at).to be < 2.days.from_now
    end

    it 'creates a follow-up task for tomorrow when the item has no task' do
      lead = create(:lead, account: account, lead_stage: active_stage)
      post "#{url}/snooze", params: { lead_id: lead.id },
                            headers: agent.create_new_auth_token, as: :json
      task = lead.lead_tasks.open_tasks.first
      expect(task.kind).to eq('follow_up')
      expect(task.due_at).to be > Time.current
    end
  end
end
