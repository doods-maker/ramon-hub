# spec/services/ramon/portal_docs_service_spec.rb
require 'rails_helper'

RSpec.describe Ramon::PortalDocsService do
  let(:notes) do
    'LEAD (Dudu) - o juízo não aceita ZapSign. Pedir comprovante de residência atual em nome dele; ' \
      'se for da esposa, certidão de casamento.'
  end

  def resposta(content)
    Ramon::LlmClient::Result.new(content: content, input_tokens: 1, output_tokens: 1)
  end

  it 'manda as observações mascaradas ao LLM e devolve só os nomes dos documentos' do
    allow(Ramon::LlmClient).to receive(:complete)
      .with(hash_including(provider: 'deepseek', user: notes))
      .and_return(resposta('{"documentos": ["Comprovante de residência atual em seu nome", ' \
                           '" Certidão de casamento (se o comprovante estiver no nome da esposa) "]}'))
    expect(described_class.itens(notes, nome: 'Felix Ribeiro'))
      .to eq(['Comprovante de residência atual em seu nome', 'Certidão de casamento (se o comprovante estiver no nome da esposa)'])
  end

  it 'aceita cerca de markdown e devolve nil em resposta inválida ou erro' do
    allow(Ramon::LlmClient).to receive(:complete).and_return(resposta("```json
{\"documentos\": [\"RG\"]}
```"))
    expect(described_class.itens(notes)).to eq(['RG'])

    allow(Ramon::LlmClient).to receive(:complete).and_return(resposta('não sei'))
    expect(described_class.itens(notes)).to be_nil

    allow(Ramon::LlmClient).to receive(:complete).and_raise(Ramon::LlmClient::TransientError)
    expect(described_class.itens(notes)).to be_nil
  end

  it 'observação vazia não chama o LLM' do
    allow(Ramon::LlmClient).to receive(:complete)
    expect(described_class.itens('  ')).to eq([])
    expect(Ramon::LlmClient).not_to have_received(:complete)
  end
end
