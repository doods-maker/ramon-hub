require 'rails_helper'

describe Ramon::CoachObjecaoService do
  let(:account) { create(:account) }
  let(:thesis) { create(:thesis, account: account) }
  let!(:objecao_item) do
    create(:thesis_item, thesis: thesis, section: 'objecao',
                         title: 'Advogado é caro', content: 'A análise é gratuita e o honorário é no êxito.')
  end
  let(:conversation) { create(:conversation, account: account) }
  let(:lead) { create(:lead, account: account, conversation: conversation, thesis: thesis) }
  let(:message) do
    create(:message, account: account, conversation: conversation, message_type: :incoming,
                     content: 'minha vizinha pagou caro e o INSS negou, vou pensar mais um pouco')
  end

  def llm(content)
    Ramon::LlmClient::Result.new(content: content, input_tokens: 1, output_tokens: 1)
  end

  it 'objeção detectada → registra evento coach com 2 opções e grava ultima_em' do
    allow(Ramon::LlmClient).to receive(:complete).and_return(
      llm('{"objecao": "custo", "opcoes": [{"titulo": "Segurança primeiro", "texto": "..."}, {"titulo": "Prova concreta", "texto": "..."}]}')
    )
    expect { described_class.new(message, lead).perform }
      .to have_enqueued_job(Conversations::ActivityMessageJob).with(
        conversation,
        hash_including(content_attributes: hash_including('ramon_event' => 'coach', 'objecao' => 'custo'))
      )
    expect(lead.reload.custom_attributes.dig('coach', 'ultima_em')).to be_present
  end

  it 'sem objeção ({"objecao": "nenhuma"}) → não registra evento, mas grava ultima_em (gap por chamada de LLM)' do
    allow(Ramon::LlmClient).to receive(:complete).and_return(llm('{"objecao": "nenhuma"}'))
    expect { described_class.new(message, lead).perform }
      .not_to have_enqueued_job(Conversations::ActivityMessageJob)
    expect(lead.reload.custom_attributes.dig('coach', 'ultima_em')).to be_present
  end

  it 'fail-safe: JSON inválido/exceção → silêncio e não grava ultima_em' do
    allow(Ramon::LlmClient).to receive(:complete).and_raise(Ramon::LlmClient::TransientError)
    expect { described_class.new(message, lead).perform }.not_to raise_error
    expect(lead.reload.custom_attributes.dig('coach', 'ultima_em')).to be_blank
  end

  it 'gap mínimo: coach há menos de 10 min → não roda o LLM' do
    lead.update!(custom_attributes: lead.custom_attributes.merge('coach' => { 'ultima_em' => 2.minutes.ago.iso8601 }))
    expect(Ramon::LlmClient).not_to receive(:complete)
    described_class.new(message, lead).perform
  end

  it 'playbook vazio (tese sem itens de objeção) → não chama o LLM' do
    thesis.thesis_items.where(section: 'objecao').delete_all
    expect(Ramon::LlmClient).not_to receive(:complete)
    described_class.new(message, lead).perform
  end
end
