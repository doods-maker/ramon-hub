require 'rails_helper'

RSpec.describe 'Painel dos agentes API', type: :request do
  let(:account) { create(:account) }
  let(:url) { "/api/v1/accounts/#{account.id}/ramon_painel_agentes" }

  around do |exemplo|
    with_modified_env(RAMON_PAINEL_AGENTES_EMAILS: 'eduardo@example.com', RAMON_PAINEL_AGENTES_URL: 'https://painel.example.com:8443/') do
      exemplo.run
    end
  end

  it 'entrega o endereço a quem está na lista' do
    eduardo = create(:user, account: account, role: :administrator, email: 'eduardo@example.com')
    get url, headers: eduardo.create_new_auth_token, as: :json
    expect(response.parsed_body['url']).to eq('https://painel.example.com:8443/')
  end

  it 'não entrega a quem está fora, mesmo administrador' do
    ramon = create(:user, account: account, role: :administrator, email: 'ramon@example.com')
    get url, headers: ramon.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    expect(response.parsed_body['url']).to be_nil
  end

  it 'exige login' do
    get url, as: :json
    expect(response).to have_http_status(:unauthorized)
  end
end
