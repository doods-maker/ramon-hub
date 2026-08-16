require 'rails_helper'

# FORK-PONTO (ramon): busca textual da FAQ (Ramon::FaqBusca). Depende do codigo
# enterprise (o CI FOSS remove a pasta), por isso o guard.
RSpec.describe 'Captain::AssistantResponse busca textual', type: :model, if: ChatwootApp.enterprise? do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }

  around { |example| with_modified_env(RAMON_FAQ_BUSCA: 'texto') { example.run } }

  before do
    faq('Posso continuar trabalhando recebendo auxílio-acidente?', 'Sim, o auxílio-acidente é compatível com o trabalho.')
    faq('Quanto custa?', 'Você só paga se receber.')
    faq('Quais documentos preciso?', 'RG, CPF e carta do INSS.')
  end

  def faq(question, answer)
    create(:captain_assistant_response, assistant: assistant, account: account, question: question, answer: answer)
  end

  it 'acha a FAQ certa pela pergunta em portugues' do
    resultado = assistant.responses.approved.search('posso continuar trabalhando').to_a
    expect(resultado.map(&:question)).to eq(['Posso continuar trabalhando recebendo auxílio-acidente?'])
  end

  it 'cai no OR das palavras quando a busca inteira nao casa' do
    resultado = assistant.responses.approved.search('trabalhando documentos').to_a
    expect(resultado.map(&:question)).to contain_exactly('Posso continuar trabalhando recebendo auxílio-acidente?',
                                                         'Quais documentos preciso?')
  end

  it 'volta vazio sem match' do
    expect(assistant.responses.approved.search('foguete lunar').to_a).to be_empty
  end

  it 'nao enfileira embedding em modo texto' do
    expect { faq('Nova?', 'Sim.') }.not_to have_enqueued_job(Captain::Llm::UpdateEmbeddingJob)
  end
end
