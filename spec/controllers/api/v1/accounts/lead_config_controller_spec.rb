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
end
