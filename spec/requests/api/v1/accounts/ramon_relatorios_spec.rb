require 'rails_helper'

RSpec.describe 'Ramon Relatorios API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:url) { "/api/v1/accounts/#{account.id}/ramon_relatorios" }
  let(:envs) do
    { 'RAMON_METABASE_SITE_URL' => 'https://bi.test', 'RAMON_METABASE_SECRET_KEY' => 'a' * 64,
      'RAMON_METABASE_DASHBOARD_ID' => '7' }
  end

  it 'exige autenticacao' do
    get url, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it 'barra agente (admin-only)' do
    get url, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it 'devolve configured false sem envs' do
    with_modified_env('RAMON_METABASE_SITE_URL' => nil) do
      get url, headers: admin.create_new_auth_token, as: :json
    end
    expect(response).to have_http_status(:success)
    expect(response.parsed_body['configured']).to be(false)
  end

  it 'devolve a url do embed com JWT valido' do
    with_modified_env(envs) do
      get url, headers: admin.create_new_auth_token, as: :json
    end
    body = response.parsed_body
    expect(body['configured']).to be(true)
    token = body['url'][%r{embed/dashboard/([^#]+)}, 1]
    payload, = JWT.decode(token, 'a' * 64, true, algorithm: 'HS256')
    expect(payload['resource']).to eq('dashboard' => 7)
    expect(body['url']).to start_with('https://bi.test/embed/dashboard/')
    expect(body['url']).to end_with('#theme=night&bordered=false&titled=false')
  end
end
