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

  it 'trava antes do LLM: valor, percentual, garantia, prazo ou texto longo nunca são logística' do
    allow(Ramon::LlmClient).to receive(:complete).and_return(result_with('{"logistica": true}'))
    ['Seus atrasados ficam em R$ 12.000', 'O honorário é 30% dos atrasados', 'Garantimos o benefício',
     'O prazo de análise é de 45 dias', "Consegue mandar o PPP? #{'a' * 400}"].each do |texto|
      expect(described_class.logistica?(texto)).to be(false)
    end
    expect(Ramon::LlmClient).not_to have_received(:complete)
    expect(described_class.logistica?('Pode me mandar o print do Meu INSS com o extrato?')).to be(true)
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
