require 'rails_helper'

RSpec.describe Captain::Llm::ContactNotesService do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:mock_chat) { instance_double(RubyLLM::Chat) }
  let(:resposta) { instance_double(RubyLLM::Message, content: { memoria: ['Interesse: BPC', 'CID F32'] }.to_json) }

  before do
    create(:installation_config, name: 'CAPTAIN_OPEN_AI_API_KEY', value: 'test-key')
    allow(RubyLLM).to receive(:chat).and_return(mock_chat)
    allow(mock_chat).to receive_messages(with_temperature: mock_chat, with_params: mock_chat, with_instructions: mock_chat,
                                         ask: resposta)
  end

  it 'grava a memoria no lead da conversa, sem o item de saude' do
    lead = create(:lead, account: account, conversation: conversation)

    described_class.new(assistant, conversation).generate_and_update_notes

    expect(lead.lead_notes.last.body).to eq("MEMÓRIA DA IA (conversa ##{conversation.display_id}):\n- Interesse: BPC")
  end

  it 'sem lead nao chama a IA' do
    described_class.new(assistant, conversation).generate_and_update_notes

    expect(mock_chat).not_to have_received(:ask)
  end

  it 'com o gasto do dia no teto nao chama a IA' do
    create(:lead, account: account, conversation: conversation)
    allow(Ramon::IaGastoAlerta).to receive(:passou_do_teto?).and_return(true)

    described_class.new(assistant, conversation).generate_and_update_notes

    expect(mock_chat).not_to have_received(:ask)
  end
end
