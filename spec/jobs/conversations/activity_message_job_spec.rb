require 'rails_helper'

RSpec.describe Conversations::ActivityMessageJob do
  let(:conversation) { create(:conversation) }
  let(:params) { { message_type: :outgoing, account_id: conversation.account_id, inbox_id: conversation.inbox_id, content: 'aviso' } }
  let!(:cliente) { create(:message, conversation: conversation, account: conversation.account, inbox: conversation.inbox) }

  it 'cria a mensagem' do
    expect { described_class.perform_now(conversation, params) }.to change { conversation.messages.count }.by(1)
  end

  describe 'aviso agendado com apos_id (handoff por cota)' do
    it 'não sai se uma pessoa respondeu depois da mensagem do cliente' do
      create(:message, conversation: conversation, account: conversation.account, inbox: conversation.inbox, message_type: :outgoing)
      expect { described_class.perform_now(conversation, params, cliente.id) }.not_to(change { conversation.messages.count })
    end

    it 'sai se depois só veio mensagem sem pessoa (IA/automação)' do
      create(:message, :bot_message, conversation: conversation, account: conversation.account, inbox: conversation.inbox)
      expect { described_class.perform_now(conversation, params, cliente.id) }.to change { conversation.messages.count }.by(1)
    end
  end
end
