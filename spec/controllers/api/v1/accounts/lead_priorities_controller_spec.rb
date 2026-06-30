require 'rails_helper'

RSpec.describe 'Lead Priorities API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }

  it 'cria com peso e posição no fim' do
    account.lead_priorities.create!(name: 'Alta', weight: 3, position: 0)
    post "/api/v1/accounts/#{account.id}/lead_priorities",
         params: { name: 'Urgente', weight: 5 }, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:success)
    expect(response.parsed_body['weight']).to eq(5)
    expect(response.parsed_body['position']).to eq(1)
  end

  it 'atualiza o peso' do
    p = account.lead_priorities.create!(name: 'Média', weight: 2, position: 0)
    patch "/api/v1/accounts/#{account.id}/lead_priorities/#{p.id}",
          params: { weight: 4 }, headers: admin.create_new_auth_token
    expect(p.reload.weight).to eq(4)
  end
end
