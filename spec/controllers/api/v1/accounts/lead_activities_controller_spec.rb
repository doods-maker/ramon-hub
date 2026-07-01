require 'rails_helper'

RSpec.describe 'Lead Activities API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:lead) { create(:lead, account: account) }

  it 'lists the activities of a lead in chronological order' do
    lead.lead_activities.create!(account: account, kind: 'created', created_at: 2.days.ago)
    lead.lead_activities.create!(account: account, kind: 'stage_changed',
                                 from_value: 'Novo', to_value: 'Qualificação', user: admin, created_at: 1.hour.ago)

    get "/api/v1/accounts/#{account.id}/leads/#{lead.id}/activities",
        headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    payload = response.parsed_body['payload']
    expect(payload.map { |a| a['kind'] }).to eq(%w[created stage_changed])
    expect(payload.last['author_name']).to eq(admin.name)
    expect(payload.last['to_value']).to eq('Qualificação')
  end
end
