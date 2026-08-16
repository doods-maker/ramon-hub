require 'rails_helper'

describe Ramon::PilotoLogisticaService do
  def result_with(content)
    Ramon::LlmClient::Result.new(content: content, input_tokens: 1, output_tokens: 1)
  end

  it 'true quando o LLM responde logistica true' do
    allow(Ramon::LlmClient).to receive(:complete).and_return(result_with('{"logistica": true}'))
    expect(described_class.logistica?('Bom dia! Consegue me mandar o PPP até amanhã?')).to be(true)
  end

  it 'false quando o LLM responde false' do
    allow(Ramon::LlmClient).to receive(:complete).and_return(result_with('{"logistica": false}'))
    expect(described_class.logistica?('Seu benefício deve sair em 30 dias')).to be(false)
  end

  it 'fail-safe: JSON inválido vira false' do
    allow(Ramon::LlmClient).to receive(:complete).and_return(result_with('acho que sim'))
    expect(described_class.logistica?('qualquer')).to be(false)
  end

  it 'fail-safe: exceção do LLM vira false' do
    allow(Ramon::LlmClient).to receive(:complete).and_raise(Ramon::LlmClient::TransientError)
    expect(described_class.logistica?('qualquer')).to be(false)
  end
end
