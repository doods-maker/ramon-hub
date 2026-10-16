require 'rails_helper'

RSpec.describe Ramon::FunilRegras do
  let(:account) { create(:account) }
  let(:lead) { create(:lead, account: account, lead_stage: account.lead_stages.find_by(label: 'fase-reuniao-realizada')) }

  def ligar(peca, modo = 'on') = Ramon::FunilAutomatico.mudar!(account, peca, modo)

  describe '.contrato_criado' do
    it 'com a peça on leva de Reunião realizada a Negociação e registra' do
      ligar('zapsign_negociacao')

      described_class.contrato_criado(lead)

      expect(lead.reload.lead_stage.label).to eq('fase-negociacao')
      expect(FunilAcao.last).to have_attributes(acao: 'mover_etapa', alvo: 'Negociação', peca: 'zapsign_negociacao')
    end

    it 'não volta etapa: lead em Última chance fica onde está' do
      ligar('zapsign_negociacao')
      ultima = account.lead_stages.find_by(label: 'fase-ultima-chance')
      lead.update!(lead_stage: ultima)

      described_class.contrato_criado(lead)

      expect(lead.reload.lead_stage).to eq(ultima)
      expect(FunilAcao.count).to eq(0)
    end

    it 'com a peça off não muda nada' do
      described_class.contrato_criado(lead)

      expect(lead.reload.lead_stage.label).to eq('fase-reuniao-realizada')
      expect(FunilAcao.count).to eq(0)
    end
  end

  describe '.contrato_assinado' do
    it 'com a peça on marca ganho e mantém o valor estimado' do
      ligar('zapsign_ganho')
      valor_antes = lead.value

      described_class.contrato_assinado(lead)

      lead.reload
      expect(lead.lead_stage).to be_is_won
      expect(lead.won_at).to be_present
      expect(lead.value).to eq(valor_antes)
    end

    it 'lead em Perdido vira Ganho' do
      ligar('zapsign_ganho')
      lead.update!(lead_stage: account.lead_stages.find_by(is_lost: true))

      described_class.contrato_assinado(lead)

      expect(lead.reload.lead_stage).to be_is_won
    end

    it 'com a peça off não muda nada' do
      described_class.contrato_assinado(lead)

      expect(lead.reload.won_at).to be_nil
    end
  end
end
