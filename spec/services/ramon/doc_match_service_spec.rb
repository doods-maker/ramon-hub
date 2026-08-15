require 'rails_helper'

RSpec.describe Ramon::DocMatchService do
  let(:account) { create(:account) }
  let(:thesis) { create(:thesis, account: account) }
  let!(:rg) { create(:thesis_item, thesis: thesis, section: 'documento', content: 'RG') }
  let(:conversation) { create(:conversation, account: account) }
  let(:lead) { create(:lead, account: account, thesis: thesis, conversation: conversation) }
  let(:message) do
    create(:message, account: account, conversation: conversation, message_type: :incoming).tap do |m|
      m.attachments.create!(account_id: account.id, file_type: :image,
                            file: fixture_file_upload(Rails.root.join('spec/assets/avatar.png'), 'image/png'))
    end
  end

  before { lead }

  it 'grava doc_sugestao quando o LLM aponta um item valido' do
    allow(Ramon::LlmClient).to receive(:complete)
      .and_return(Ramon::LlmClient::Result.new(content: %({"item_id": #{rg.id}}), input_tokens: 1, output_tokens: 1))
    described_class.new(message).perform
    expect(lead.reload.custom_attributes.dig('doc_sugestao', 'item_id')).to eq(rg.id)
    sugestao = lead.custom_attributes['doc_sugestao']
    expect(sugestao['resolvida']).to be(false)
    expect(sugestao['message_id']).to eq(message.id)
  end

  it 'registra evento de automação doc_match na conversa' do
    allow(Ramon::LlmClient).to receive(:complete)
      .and_return(Ramon::LlmClient::Result.new(content: %({"item_id": #{rg.id}}), input_tokens: 1, output_tokens: 1))
    expect { described_class.new(message).perform }
      .to have_enqueued_job(Conversations::ActivityMessageJob).with(
        message.conversation,
        hash_including(
          message_type: :activity,
          content_attributes: hash_including(
            'ramon_event' => 'doc_match',
            'item_id' => rg.id
          )
        )
      )
  end

  it 'grava doc_sugestao quando o LLM devolve item_id como string' do
    allow(Ramon::LlmClient).to receive(:complete)
      .and_return(Ramon::LlmClient::Result.new(content: %({"item_id": "#{rg.id}"}), input_tokens: 1, output_tokens: 1))
    described_class.new(message).perform
    expect(lead.reload.custom_attributes.dig('doc_sugestao', 'item_id')).to eq(rg.id)
  end

  it 'nao grava com item fora do checklist' do
    allow(Ramon::LlmClient).to receive(:complete)
      .and_return(Ramon::LlmClient::Result.new(content: '{"item_id": 999999}', input_tokens: 1, output_tokens: 1))
    described_class.new(message).perform
    expect(lead.reload.custom_attributes['doc_sugestao']).to be_nil
  end

  it 'nao chama o LLM quando o lead nao tem checklist pendente' do
    rg.destroy!
    expect(Ramon::LlmClient).not_to receive(:complete)
    described_class.new(message).perform
  end

  it 'nao chama o LLM quando a mensagem nao tem anexo de imagem/arquivo' do
    plain = create(:message, account: account, conversation: conversation, message_type: :incoming, content: 'oi')
    expect(Ramon::LlmClient).not_to receive(:complete)
    described_class.new(plain).perform
  end

  context 'when the item is already marked as received' do
    it 'does not ask the LLM' do
      lead.update!(custom_attributes: { 'doc_status' => { rg.id.to_s => 'recebido' } })
      expect(Ramon::LlmClient).not_to receive(:complete)
      described_class.new(message).perform
    end
  end
end
