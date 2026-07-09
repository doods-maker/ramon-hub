require 'rails_helper'

RSpec.describe 'Titular Export API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:contact) { create(:contact, :with_email, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  before do
    create(:message, conversation: conversation, account: account, inbox: conversation.inbox,
                     sender: contact, content: 'Mensagem do titular')
  end

  describe 'GET /api/v1/accounts/{account.id}/contacts/:contact_id/titular_export' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/contacts/#{contact.id}/titular_export"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an administrator' do
      it 'returns the full dump with conversations and messages' do
        get "/api/v1/accounts/#{account.id}/contacts/#{contact.id}/titular_export",
            headers: admin.create_new_auth_token

        expect(response).to have_http_status(:success)
        json = response.parsed_body
        expect(json['titular']['id']).to eq(contact.id)
        expect(json['conversas'].first['id']).to eq(conversation.display_id)
        expect(json['conversas'].first['mensagens'].pluck('conteudo')).to include('Mensagem do titular')
      end
    end

    context 'when it is an agent' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/contacts/#{contact.id}/titular_export",
            headers: agent.create_new_auth_token

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
