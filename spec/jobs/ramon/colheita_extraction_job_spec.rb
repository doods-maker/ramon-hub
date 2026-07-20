require 'rails_helper'

RSpec.describe Ramon::ColheitaExtractionJob do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let!(:lead) { create(:lead, account: account, conversation: conversation) }
  let(:message) do
    create(:message, account: account, conversation: conversation, message_type: :incoming, content: 'oi')
  end
  let(:service) { instance_double(Ramon::ColheitaExtractionService, perform: nil) }

  before { allow(Ramon::ColheitaExtractionService).to receive(:new).and_return(service) }

  it 'roda a extração quando a mensagem ainda é a última da rajada' do
    described_class.perform_now(message.id, debounce: true)
    expect(Ramon::ColheitaExtractionService).to have_received(:new).with(lead)
  end

  it 'pula com debounce quando chegou incoming mais nova (rajada converge no último job)' do
    message
    create(:message, account: account, conversation: conversation, message_type: :incoming, content: 'mais uma')
    described_class.perform_now(message.id, debounce: true)
    expect(Ramon::ColheitaExtractionService).not_to have_received(:new)
  end

  it 'sem debounce roda mesmo com mensagem mais nova (caminho da transcrição)' do
    message
    create(:message, account: account, conversation: conversation, message_type: :incoming, content: 'mais uma')
    described_class.perform_now(message.id)
    expect(Ramon::ColheitaExtractionService).to have_received(:new).with(lead)
  end

  it 'sai em silêncio quando a conversa não tem lead' do
    orphan = create(:conversation, account: account)
    msg = create(:message, account: account, conversation: orphan, message_type: :incoming, content: 'oi')
    described_class.perform_now(msg.id)
    expect(Ramon::ColheitaExtractionService).not_to have_received(:new)
  end
end
