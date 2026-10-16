require 'rails_helper'

RSpec.describe 'Ramon Google Agenda API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:base) { "/api/v1/accounts/#{account.id}/ramon_google_agenda" }

  it 'exige autenticacao' do
    get base, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it 'status: conectada false sem conta' do
    get base, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('conectada' => false, 'email' => nil, 'status' => nil)
  end

  it 'status: mostra conta desconectada' do
    GoogleAgendaConta.create!(user: agent, account: account, email: 'a@b.com', status: 'desconectada')
    get base, headers: agent.create_new_auth_token, as: :json
    expect(response.parsed_body).to include('conectada' => false, 'email' => 'a@b.com', 'status' => 'desconectada')
  end

  it 'autorizacao: agente comum recebe a url com o escopo de agenda e state valido' do
    with_modified_env('FRONTEND_URL' => 'https://hub.test', 'GOOGLE_OAUTH_CLIENT_ID' => 'cid') do
      post "#{base}/autorizacao", headers: agent.create_new_auth_token, as: :json
    end
    expect(response).to have_http_status(:ok)
    url = response.parsed_body['url']
    expect(url).to start_with('https://accounts.google.com/o/oauth2/auth')
    query = Rack::Utils.parse_query(URI(url).query)
    expect(query['scope']).to include('https://www.googleapis.com/auth/calendar.events')
    expect(query).to include('access_type' => 'offline', 'prompt' => 'consent',
                             'redirect_uri' => 'https://hub.test/ramon/google_agenda/callback')
    sgid, _sep, account_id = query['state'].rpartition(':')
    expect(account_id).to eq(account.id.to_s)
    expect(GlobalID::Locator.locate_signed(sgid, for: 'ramon_google_agenda')).to eq(agent)
  end

  it 'destroy: apaga a conta e tenta revogar no Google' do
    GoogleAgendaConta.create!(user: agent, account: account, refresh_token: 'rt', access_token: 'at')
    revogacao = stub_request(:post, 'https://oauth2.googleapis.com/revoke').to_return(status: 200)
    delete base, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:no_content)
    expect(GoogleAgendaConta.find_by(user_id: agent.id)).to be_nil
    expect(revogacao).to have_been_requested
  end

  it 'destroy: apaga mesmo se a revogacao falhar' do
    GoogleAgendaConta.create!(user: agent, account: account, refresh_token: 'rt')
    stub_request(:post, 'https://oauth2.googleapis.com/revoke').to_timeout
    delete base, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:no_content)
    expect(GoogleAgendaConta.find_by(user_id: agent.id)).to be_nil
  end
end
