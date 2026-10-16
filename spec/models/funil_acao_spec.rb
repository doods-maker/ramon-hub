require 'rails_helper'

RSpec.describe FunilAcao do
  let(:account) { create(:account) }
  let(:lead) { create(:lead, account: account) }

  def acao(attrs = {})
    described_class.create!({ account: account, lead: lead, peca: 'etapa_ia', acao: 'mover', ensaio: false }.merge(attrs))
  end

  it 'reais exclui ensaios; vivas exclui também as desfeitas' do
    viva = acao
    ensaio = acao(ensaio: true)
    desfeita = acao(desfeita_em: Time.current)

    expect(described_class.reais).to contain_exactly(viva, desfeita)
    expect(described_class.vivas).to contain_exactly(viva)
    expect(described_class.vivas).not_to include(ensaio)
  end

  it 'guarda desfazer como jsonb (padrão vazio)' do
    expect(acao.desfazer).to eq({})
    expect(acao(desfazer: { 'etapa' => 'fase-novo' }).reload.desfazer).to eq('etapa' => 'fase-novo')
  end

  describe '#desfazer!' do
    let(:user) { create(:user, account: account) }
    let(:novo) { account.lead_stages.find_by(label: 'fase-novo') }
    let(:qualificacao) { account.lead_stages.find_by(label: 'fase-qualificacao') }

    it 'mover etapa volta à etapa anterior, grava desfeita_em/por; o segundo desfazer devolve false' do
      lead.update!(lead_stage: qualificacao)
      a = acao(desfazer: { 'etapa_id' => novo.id })

      expect(a.desfazer!(user)).to be(true)
      expect(lead.reload.lead_stage).to eq(novo)
      expect(a.reload).to have_attributes(desfeita_por: user)
      expect(a.desfeita_em).to be_present
      expect(a.desfazer!(user)).to be(false)
    end

    it 'perdido devolve a etapa, tira a etiqueta e restaura o modo' do
      conversa = create(:conversation, account: account)
      lead.update!(conversation: conversa)
      Ramon::CopilotoModo.trocar(conversa, 'rascunho')
      lead.update!(lead_stage: account.lead_stages.find_by(is_lost: true), lost_reason: 'Honorário')
      Ramon::Roteiro::Efeitos.calar(lead)
      a = acao(desfazer: { 'etapa_id' => qualificacao.id, 'modo' => 'rascunho' })

      expect(a.desfazer!(user)).to be(true)
      expect(lead.reload.lead_stage).to eq(qualificacao)
      expect(lead.lost_reason).to be_nil
      expect(conversa.reload.label_list).not_to include('desqualificado-ia')
      expect(Ramon::CopilotoModo.of(conversa)).to eq('rascunho')
    end

    it 'Ganho que veio de Perdido volta a Perdido com o motivo guardado' do
      perdido = account.lead_stages.find_by(is_lost: true)
      lead.update!(lead_stage: account.lead_stages.find_by(is_won: true))
      a = acao(desfazer: { 'etapa_id' => perdido.id, 'lost_reason' => 'Honorário' })

      expect(a.desfazer!(user)).to be(true)
      expect(lead.reload).to have_attributes(lead_stage: perdido, lost_reason: 'Honorário')
    end

    it 'tarefa de follow-up criada pela ação é apagada' do
      task = create(:lead_task, account: account, lead: lead, kind: 'follow_up')

      expect(acao(desfazer: { 'task_id' => task.id }).desfazer!(user)).to be(true)
      expect(LeadTask.exists?(task.id)).to be(false)
    end
  end
end
