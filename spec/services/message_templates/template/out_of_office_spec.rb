require 'rails_helper'

describe MessageTemplates::Template::OutOfOffice do
  context 'when this hook is called' do
    let(:conversation) { create(:conversation) }

    it 'creates the out of office messages' do
      described_class.new(conversation: conversation).perform
      expect(conversation.messages.template.count).to eq(1)
      expect(conversation.messages.template.first.content).to eq(conversation.inbox.out_of_office_message)
    end

    it 'creates the out of office messages with template variable' do
      conversation.inbox.update!(out_of_office_message: 'Hey, {{contact.name}} we are unavailable at the moment.')
      described_class.new(conversation: conversation).perform
      expect(conversation.messages.count).to eq(1)
      expect(conversation.messages.last.content).to eq("Hey, #{conversation.contact.name} we are unavailable at the moment.")
    end

    it 'creates the out of office messages with more than one variable strings' do
      conversation.inbox.update!(out_of_office_message:
        'Hey, {{contact.name}} we are unavailable at the moment. - from {{account.name}}')
      described_class.new(conversation: conversation).perform
      expect(conversation.messages.count).to eq(1)
      expect(conversation.messages.last.content).to eq(
        "Hey, #{conversation.contact.name} we are unavailable at the moment. - from #{conversation.account.name}"
      )
    end
  end

  # ramon (teste ponta a ponta de 07/11): o aviso genérico da caixa ("adiante seu CNIS...") destoa para quem está juntando os
  # documentos com o assistente da etapa Documentos.
  context 'when the lead is in the Documentos stage' do
    let(:conversation) { create(:conversation) }
    let(:documentos) { Ramon::EtapasPosVenda.criar!(conversation.account).first }

    before { create(:lead, account: conversation.account, conversation: conversation, lead_stage: documentos, won_at: 1.day.ago) }

    it 'does not send the out of office message with the switch on' do
      with_modified_env(RAMON_ETAPA_DOCUMENTOS: 'on') do
        described_class.new(conversation: conversation).perform
        described_class.perform_if_applicable(conversation)
      end

      expect(conversation.messages.template).to be_empty
    end

    it 'sends it as before with the switch off' do
      described_class.new(conversation: conversation).perform

      expect(conversation.messages.template.count).to eq(1)
    end
  end
end
