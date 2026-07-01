require 'rails_helper'

RSpec.describe 'Lead Notes API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:lead) { create(:lead, account: account) }

  it 'lists notes chronologically' do
    lead.lead_notes.create!(account: account, body: 'primeira', created_at: 2.days.ago)
    lead.lead_notes.create!(account: account, body: 'segunda', user: admin, created_at: 1.hour.ago)
    get "/api/v1/accounts/#{account.id}/leads/#{lead.id}/notes",
        headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    payload = response.parsed_body['payload']
    expect(payload.map { |n| n['body'] }).to eq(%w[primeira segunda])
    expect(payload.last['author_name']).to eq(admin.name)
  end

  it 'creates a note authored by the current user' do
    expect do
      post "/api/v1/accounts/#{account.id}/leads/#{lead.id}/notes",
           params: { body: 'nova nota' }, headers: admin.create_new_auth_token, as: :json
    end.to change(lead.lead_notes, :count).by(1)
    expect(response).to have_http_status(:success)
    expect(response.parsed_body['author_name']).to eq(admin.name)
  end
end
