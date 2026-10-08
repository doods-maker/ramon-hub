require 'rails_helper'

RSpec.describe FluxoExecucao do
  let(:account) { create(:account) }
  let(:conversa) { create(:conversation, account: account) }
  let!(:lead) { create(:lead, account: account, conversation: conversa, contact: conversa.contact) }

  describe '.lead_de' do
    it 'lead, conversa e reunião gravada vinculada acham o lead; alvo de fora do funil nunca adivinha pelo id' do
      expect(described_class.lead_de(lead)).to eq(lead)
      expect(described_class.lead_de(conversa)).to eq(lead)
      expect(described_class.lead_de(create(:reuniao, account: account, lead: lead))).to eq(lead)
      expect(described_class.lead_de(create(:reuniao, account: account))).to be_nil
      # o mesmo id da conversa do lead: o "else" antigo acharia este lead por engano
      expect(described_class.lead_de(Chegada.new(id: conversa.id, account: account))).to be_nil
      expect(described_class.lead_de(Peca.new(id: conversa.id, account: account))).to be_nil
      expect([described_class.lead_de(account), described_class.lead_de(nil)]).to eq([nil, nil]) # B5-conta: o Horário
    end
  end

  it 'a execução de um alvo de fora do funil diz o que ele é, sem lead nem conversa' do
    fluxo = fluxo_publicado(account, grafo_linear({ 'tipo' => 'peca_publicada' }))
    execucao = fluxo.execucoes.create!(account: account, alvo: create(:peca, account: account), ensaio: true)
    expect(execucao.resumo_json).to include(alvo_nome: 'Peça: Auxílio-acidente: quem tem direito', lead_id: nil,
                                            conversation_display_id: nil)
  end
end
