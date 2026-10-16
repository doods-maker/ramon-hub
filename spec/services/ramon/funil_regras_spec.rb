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

    it 'lead velho em memória não passa por cima de um Perdido gravado por outro processo' do
      ligar('zapsign_negociacao')
      velho = Lead.find(lead.id)
      lead.update!(lead_stage: account.lead_stages.find_by(is_lost: true))

      described_class.contrato_criado(velho)

      expect(lead.reload.lead_stage).to be_is_lost
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

    it 'saindo de Perdido, o desfazer guarda a etapa e o motivo da perda' do
      ligar('zapsign_ganho')
      perdido = account.lead_stages.find_by(is_lost: true)
      lead.update!(lead_stage: perdido, lost_reason: 'Honorário')

      described_class.contrato_assinado(lead)

      expect(FunilAcao.last.desfazer).to eq('etapa_id' => perdido.id, 'lost_reason' => 'Honorário')
    end

    it 'saindo de etapa aberta, o desfazer só leva a etapa' do
      ligar('zapsign_ganho')
      anterior = lead.lead_stage_id

      described_class.contrato_assinado(lead)

      expect(FunilAcao.last.desfazer).to eq('etapa_id' => anterior)
    end

    it 'lead velho em memória não regrava o won_at de um Ganho já gravado' do
      ligar('zapsign_ganho')
      velho = Lead.find(lead.id)
      travel_to(2.days.ago) { lead.update!(lead_stage: account.lead_stages.find_by(is_won: true)) }
      won_at = lead.reload.won_at

      described_class.contrato_assinado(velho)

      expect(lead.reload.won_at).to eq(won_at)
      expect(FunilAcao.count).to eq(0)
    end

    it 'falha vira log + ChatwootExceptionTracker, sem estourar para quem chamou' do
      ligar('zapsign_ganho')
      allow(Ramon::FunilAutomatico).to receive(:executar).and_raise(StandardError, 'boom')
      allow(ChatwootExceptionTracker).to receive(:new).and_call_original
      allow(Rails.logger).to receive(:error)

      expect(described_class.contrato_assinado(lead)).to be_nil

      expect(ChatwootExceptionTracker).to have_received(:new).with(an_instance_of(StandardError), account: account)
      expect(Rails.logger).to have_received(:error).with("FunilRegras falhou no lead #{lead.id}: StandardError")
    end

    it 'com a peça off não muda nada' do
      described_class.contrato_assinado(lead)

      expect(lead.reload.won_at).to be_nil
    end
  end
end
