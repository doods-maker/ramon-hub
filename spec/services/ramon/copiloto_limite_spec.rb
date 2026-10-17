require 'rails_helper'

RSpec.describe Ramon::CopilotoLimite do
  let(:account) { create(:account) }
  let(:thesis) { create(:thesis, account: account) }
  let(:conversation) { create(:conversation, account: account, status: :pending) }
  let(:lead) { create(:lead, account: account, thesis: thesis, lead_stage: etapa('Reunião agendada'), conversation: conversation) }
  let!(:admin) { create(:user, account: account, role: :administrator) }

  def etapa(nome) = account.lead_stages.find_by!(name: nome)
  def perfil!(cfg) = account.update!(settings: { 'ia_atendimento' => { 'padrao' => cfg } })
  def avisos = Notification.where(user: admin, primary_actor: lead, notification_type: 'ramon_fluxo_aviso')
  def carimbo = conversation.reload.custom_attributes['copiloto_limite']

  before { perfil!('base' => 'equilibrada') } # Marcador = Reunião agendada

  describe '.verificar' do
    # Captain (assistente da caixa) é enterprise: aqui a caixa "tem IA" pelo stub.
    before { allow(Ramon::PerfilIa).to receive(:com_ia?).and_return(true) }

    it 'cruzar o Marcador carimba, avisa uma vez e não mexe na conversa' do
      lead.update!(lead_stage: etapa('Reunião realizada'))

      expect(carimbo).to include('limite' => 'marcador', 'marcador' => 'fase-reuniao-agendada', 'etapa' => 'fase-reuniao-realizada')
      expect(conversation.custom_attributes.keys).to contain_exactly('copiloto_limite')
      expect(conversation.status).to eq('pending')
      expect(avisos.count).to eq(1)

      lead.update!(lead_stage: etapa('Negociação'))
      expect(avisos.count).to eq(1)
    end

    it 'mudar o Marcador na conta e cruzar de novo avisa de novo' do
      lead.update!(lead_stage: etapa('Reunião realizada'))
      perfil!('base' => 'equilibrada', 'marcador' => 'fase-qualificacao')
      lead.update!(lead_stage: etapa('Negociação'))

      expect(carimbo).to include('marcador' => 'fase-qualificacao')
      expect(avisos.count).to eq(2)
    end

    it 'antes do Marcador, em Perdido ou na Pausa não avisa' do
      lead.update!(lead_stage: etapa('Qualificação'))
      lead.update!(lead_stage: account.lead_stages.find_by!(is_lost: true))
      expect(carimbo).to be_nil

      conversation.update!(custom_attributes: { 'ia_pausa' => 'pausada' })
      lead.update!(lead_stage: etapa('Negociação'))
      expect(avisos.count).to eq(0)
    end

    it 'Marcador _inicio nunca avisa' do
      perfil!('base' => 'equilibrada', 'marcador' => '_inicio')
      lead.update!(lead_stage: etapa('Reunião realizada'))
      expect(carimbo).to be_nil
      expect(avisos.count).to eq(0)
    end

    it 'caixa sem assistente: cruzar o Marcador não carimba nem avisa' do
      allow(Ramon::PerfilIa).to receive(:com_ia?).with(conversation.inbox).and_return(false)
      lead.update!(lead_stage: etapa('Reunião realizada'))
      expect(carimbo).to be_nil
      expect(avisos.count).to eq(0)
    end

    it 'lead sem conversa não faz nada' do
      sem = create(:lead, account: account, thesis: thesis, lead_stage: etapa('Negociação'))
      expect(described_class.verificar(sem)).to be_nil
    end
  end

  describe '.falhou' do
    it 'carimba o motivo, põe a conversa em rascunho (Pausa) e avisa' do
      described_class.falhou(lead, 'CPF, rua')

      expect(carimbo).to include('limite' => 'contrato_falhou', 'motivo' => 'CPF, rua')
      expect(conversation.custom_attributes).to include('ia_pausa' => 'rascunho')
      expect(avisos.count).to eq(1)
    end

    it 'sem conversa só retorna' do
      sem = create(:lead, account: account, thesis: thesis)
      expect { described_class.falhou(sem, 'x') }.not_to raise_error
    end
  end
end
