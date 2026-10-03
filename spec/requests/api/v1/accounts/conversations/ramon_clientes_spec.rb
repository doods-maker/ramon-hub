require 'rails_helper'

RSpec.describe 'Ramon Cliente da Conversa API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:conversation) { create(:conversation, account: account) }
  let(:url) { "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/ramon_cliente" }

  it 'sem login → 401' do
    get url, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it 'agente sem acesso à caixa → 401 (Pundit, igual aos irmãos)' do
    get url, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it 'contato sem cadastro no painel do cliente → cliente: false' do
    create(:inbox_member, user: agent, inbox: conversation.inbox)
    get url, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    expect(response.parsed_body).to eq('cliente' => false)
  end
end
