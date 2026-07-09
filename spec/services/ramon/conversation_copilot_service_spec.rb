require 'rails_helper'

RSpec.describe Ramon::ConversationCopilotService do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }

  def llm_result(content)
    Ramon::LlmClient::Result.new(content: content, input_tokens: 10, output_tokens: 5)
  end

  describe '#perform' do
    before do
      create(:message, account: account, conversation: conversation,
                       message_type: :incoming, content: 'Sofri um acidente e recebi B91')
      create(:message, account: account, conversation: conversation,
                       message_type: :outgoing, content: 'Pode me contar mais?')
      create(:message, account: account, conversation: conversation,
                       message_type: :incoming, content: 'nota interna', private: true)
    end

    it 'manda a transcrição pública pro LLM (sem mensagens privadas) e devolve o conteúdo' do
      sent = nil
      allow(Ramon::LlmClient).to receive(:complete) do |args|
        sent = args[:user]
        llm_result('resumo pronto')
      end
      expect(described_class.new(conversation, 'summary').perform).to eq('resumo pronto')
      expect(sent).to include('Cliente: Sofri um acidente e recebi B91')
      expect(sent).to include('Atendimento: Pode me contar mais?')
      expect(sent).not_to include('nota interna')
    end

    it 'pseudonimiza nome, CPF e telefone antes de mandar pro LLM (LGPD)' do
      conversation.contact.update!(name: 'Maria das Dores')
      create(:message, account: account, conversation: conversation, message_type: :incoming,
                       content: 'Sou Maria das Dores, CPF 123.456.789-01, fone (48) 99999-8888')
      sent = nil
      allow(Ramon::LlmClient).to receive(:complete) do |args|
        sent = args[:user]
        llm_result('ok')
      end
      described_class.new(conversation, 'summary').perform
      expect(sent).to include('[nome]').and include('[cpf]').and include('[telefone]')
      expect(sent).not_to include('Maria')
      expect(sent).not_to include('123.456.789-01')
    end

    it 'usa o prompt de resumo no modo summary, via deepseek' do
      expect(Ramon::LlmClient).to receive(:complete)
        .with(hash_including(provider: 'deepseek', system: described_class::SUMMARY_SYSTEM_PROMPT))
        .and_return(llm_result('resumo'))
      described_class.new(conversation, 'summary').perform
    end

    it 'usa o prompt de rascunho no modo draft, via deepseek' do
      expect(Ramon::LlmClient).to receive(:complete)
        .with(hash_including(provider: 'deepseek', system: described_class::DRAFT_SYSTEM_PROMPT))
        .and_return(llm_result('rascunho'))
      described_class.new(conversation, 'draft').perform
    end

    it 'restaura [nome] da resposta com o primeiro nome do contato' do
      conversation.contact.update!(name: 'Maria das Dores')
      allow(Ramon::LlmClient).to receive(:complete).and_return(llm_result('Oi [nome], tudo bem?'))
      expect(described_class.new(conversation, 'draft').perform).to eq('Oi Maria, tudo bem?')
    end

    it 'inclui a ficha do lead quando a conversa tem lead' do
      create(:lead, account: account, conversation: conversation)
      sent = nil
      allow(Ramon::LlmClient).to receive(:complete) do |args|
        sent = args[:user]
        llm_result('ok')
      end
      described_class.new(conversation, 'summary').perform
      expect(sent).to include('Lead: [nome]')
      expect(sent).to include('Etapa no funil:')
    end
  end

  it 'levanta EmptyConversationError quando a conversa não tem mensagem de texto' do
    expect do
      described_class.new(conversation, 'summary').perform
    end.to raise_error(described_class::EmptyConversationError)
  end
end
