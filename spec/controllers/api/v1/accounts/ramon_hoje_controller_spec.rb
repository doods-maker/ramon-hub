require 'rails_helper'

RSpec.describe 'Ramon Hoje API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:url) { "/api/v1/accounts/#{account.id}/ramon_hoje" }

  it 'exige login' do
    get url
    expect(response).to have_http_status(:unauthorized)
  end

  it 'agente sem time recebe papel equipe e nunca o bloco do gestor' do
    get url, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    body = response.parsed_body
    expect(body['papel']).to eq('equipe')
    expect(body).not_to have_key('precisa')
  end

  it 'admin recebe papel gestor e a data de hoje em São Paulo' do
    travel_to Time.utc(2026, 10, 4, 1, 0, 0) do # 22h de 03/10 em SP
      get url, headers: admin.create_new_auth_token, as: :json
    end
    expect(response.parsed_body).to include('papel' => 'gestor', 'data' => '2026-10-03')
  end
end
