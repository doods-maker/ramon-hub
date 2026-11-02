require 'rails_helper'

RSpec.describe CopilotMessage, type: :model do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:copilot_thread) { create(:captain_copilot_thread, account: account, user: user, assistant: assistant) }

  describe 'validations' do
    it { is_expected.to validate_presence_of(:message_type) }
    it { is_expected.to validate_presence_of(:message) }
  end

  # ramon: conversa da Equipe nunca vai para a IA (ADR 0011)
  describe '#enqueue_response_job' do
    let(:message) { create(:captain_copilot_message, copilot_thread: copilot_thread, account: account) }

    it 'não leva a conversa da Equipe para a IA' do
      Ramon::Equipe.sincronizar(account, criar: true)
      geral = Ramon::Equipe.caixa(account).contact_inboxes.find_by!(source_id: 'equipe-geral').conversations.first

      expect { message.enqueue_response_job(geral.display_id, user.id) }
        .to have_enqueued_job(Captain::Copilot::ResponseJob).with(hash_including(conversation_id: nil))
    end

    it 'segue levando a conversa de caixa comum' do
      comum = create(:conversation, account: account)

      expect { message.enqueue_response_job(comum.display_id, user.id) }
        .to have_enqueued_job(Captain::Copilot::ResponseJob).with(hash_including(conversation_id: comum.display_id))
    end
  end

  describe 'callbacks' do
    let(:account) { create(:account) }
    let(:user) { create(:user, account: account) }
    let(:assistant) { create(:captain_assistant, account: account) }
    let(:copilot_thread) { create(:captain_copilot_thread, account: account, user: user, assistant: assistant) }

    describe '#ensure_account' do
      it 'sets the account from the copilot thread before validation' do
        message = build(:captain_copilot_message, copilot_thread: copilot_thread, account: nil)
        message.valid?
        expect(message.account).to eq(copilot_thread.account)
      end
    end

    describe '#broadcast_message' do
      it 'dispatches COPILOT_MESSAGE_CREATED event after create' do
        message = build(:captain_copilot_message, copilot_thread: copilot_thread)

        expect(Rails.configuration.dispatcher).to receive(:dispatch)
          .with('copilot.message.created', anything, copilot_message: message)

        message.save!
      end
    end
  end

  describe '#push_event_data' do
    let(:account) { create(:account) }
    let(:user) { create(:user, account: account) }
    let(:assistant) { create(:captain_assistant, account: account) }
    let(:copilot_thread) { create(:captain_copilot_thread, account: account, user: user, assistant: assistant) }
    let(:message_content) { { 'content' => 'Test message' } }
    let(:copilot_message) do
      create(:captain_copilot_message,
             copilot_thread: copilot_thread,
             message_type: 'user',
             message: message_content)
    end

    it 'returns the correct event data' do
      event_data = copilot_message.push_event_data

      expect(event_data[:id]).to eq(copilot_message.id)
      expect(event_data[:message]).to eq(message_content)
      expect(event_data[:message_type]).to eq('user')
      expect(event_data[:created_at]).to eq(copilot_message.created_at.to_i)
      expect(event_data[:copilot_thread]).to eq(copilot_thread.push_event_data)
    end
  end
end
