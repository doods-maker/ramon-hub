require 'rails_helper'

# O ponto único que escolhe o assistente da conversa (etapa do lead → caixa). O CI roda sem enterprise/ (run_foss_spec
# apaga a pasta): lá só vale "sem Captain, nil"; o resto roda onde o Captain existe.
RSpec.describe Captain::AssistenteDaConversa do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversa) { create(:conversation, account: account, inbox: inbox) }
  let(:documentos) { Ramon::EtapasPosVenda.criar!(account).first }

  it 'caixa sem IA: nil, mesmo com o lead numa etapa' do
    create(:lead, account: account, conversation: conversa, lead_stage: documentos)

    expect(described_class.para(conversa)).to be_nil
  end

  context 'with o Captain', if: ChatwootApp.enterprise? do
    let(:da_caixa) { create(:captain_assistant, account: account) }
    let(:da_etapa) { create(:captain_assistant, account: account) }

    before { create(:captain_inbox, captain_assistant: da_caixa, inbox: inbox) }

    it 'sem lead: o da caixa' do
      expect(described_class.para(conversa)).to eq(da_caixa)
    end

    it 'lead em etapa sem assistente: o da caixa' do
      create(:lead, account: account, conversation: conversa, lead_stage: documentos)

      expect(described_class.para(conversa)).to eq(da_caixa)
    end

    it 'lead em etapa com assistente, com a chave ligada: o da etapa' do
      documentos.update!(captain_assistant: da_etapa)
      create(:lead, account: account, conversation: conversa, lead_stage: documentos)

      with_modified_env(RAMON_ETAPA_DOCUMENTOS: 'on') { expect(described_class.para(conversa)).to eq(da_etapa) }
    end

    it 'chave desligada: o da caixa, mesmo com a etapa tendo assistente' do
      documentos.update!(captain_assistant: da_etapa)
      create(:lead, account: account, conversation: conversa, lead_stage: documentos)

      expect(described_class.para(conversa)).to eq(da_caixa)
    end

    it 'caixa sem IA continua nil, mesmo com a etapa tendo assistente' do
      CaptainInbox.where(inbox: inbox).destroy_all
      documentos.update!(captain_assistant: da_etapa)
      create(:lead, account: account, conversation: conversa, lead_stage: documentos)

      with_modified_env(RAMON_ETAPA_DOCUMENTOS: 'on') { expect(described_class.para(conversa.reload)).to be_nil }
    end
  end
end
