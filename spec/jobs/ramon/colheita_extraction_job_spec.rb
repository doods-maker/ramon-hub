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

  it 'roda a extração pelo message_id (caminho da transcrição do Whisper)' do
    described_class.perform_now(message.id)
    expect(Ramon::ColheitaExtractionService).to have_received(:new).with(lead)
  end

  it 'roda a extração pelo lead_id (caminho sob demanda do botão)' do
    described_class.perform_now(lead_id: lead.id)
    expect(Ramon::ColheitaExtractionService).to have_received(:new).with(lead)
  end

  it 'sai em silêncio quando a conversa da mensagem não tem lead' do
    orphan = create(:conversation, account: account)
    msg = create(:message, account: account, conversation: orphan, message_type: :incoming, content: 'oi')
    described_class.perform_now(msg.id)
    expect(Ramon::ColheitaExtractionService).not_to have_received(:new)
  end

  it 'sai em silêncio quando o lead_id não existe' do
    described_class.perform_now(lead_id: 0)
    expect(Ramon::ColheitaExtractionService).not_to have_received(:new)
  end
end
