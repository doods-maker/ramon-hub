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

  describe '#texto' do
    it 'usa o rótulo em português; início de reunião em dd/mm HH:MM (São Paulo); id de tarefa não aparece' do
      expect(acao(acao: 'mover_etapa', alvo: 'Qualificação').texto).to eq('moveu para Qualificação')
      expect(acao(acao: 'marcar_reuniao', alvo: '2026-10-20T14:00:00-03:00').texto).to eq('marcou reunião para 20/10 14:00')
      expect(acao(acao: 'promessa', alvo: 'Cobrar: laudo').texto).to eq('criou cobrança (Cobrar: laudo)')
      expect(acao(acao: 'promessa_cumprida', alvo: '42').texto).to eq('concluiu cobrança')
      expect(acao(acao: 'avisar_no_show', alvo: '42').texto).to eq('avisou no-show')
      expect(acao(acao: 'reativar', alvo: '30').texto).to eq('rascunho de retomada')
      expect(acao(acao: 'outra_coisa', alvo: 'x').texto).to eq('outra coisa → x')
    end
  end

  describe '.chips' do
    it 'ação sem desfazer (aviso, cobrança concluída) não substitui o chip da ação desfazível' do
      movida = acao(acao: 'mover_etapa', alvo: 'Qualificação', desfazer: { 'etapa_id' => 1 })
      acao(acao: 'avisar_no_show', alvo: '42')

      expect(described_class.chip(lead)).to eq(id: movida.id, texto: 'moveu para Qualificação')
    end

    it 'só ações sem desfazer: sem chip' do
      acao(acao: 'promessa_cumprida', alvo: '42')

      expect(described_class.chip(lead)).to be_nil
    end
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

    it 'perdido devolve a etapa, tira a etiqueta e restaura a Pausa de antes' do
      conversa = create(:conversation, account: account, custom_attributes: { 'ia_pausa' => 'rascunho' })
      lead.update!(conversation: conversa)
      lead.update!(lead_stage: account.lead_stages.find_by(is_lost: true), lost_reason: 'Honorário')
      Ramon::Roteiro::Efeitos.calar(lead)
      a = acao(desfazer: { 'etapa_id' => qualificacao.id, 'pausa' => 'rascunho' })

      expect(a.desfazer!(user)).to be(true)
      expect(lead.reload.lead_stage).to eq(qualificacao)
      expect(lead.lost_reason).to be_nil
      expect(conversa.reload.label_list).not_to include('desqualificado-ia')
      expect(conversa.custom_attributes).to include('ia_pausa' => 'rascunho')
      expect(conversa.custom_attributes).not_to have_key('ia_pausa_antes_roteiro')
    end

    it 'perdido sem a Pausa guardada vale a gravada na ação; ação antiga (só modo) não mexe na Pausa' do
      conversa = create(:conversation, account: account, custom_attributes: { 'ia_pausa' => 'pausada' })
      lead.update!(conversation: conversa, lead_stage: account.lead_stages.find_by(is_lost: true), lost_reason: 'Honorário')
      antiga = acao(acao: 'perdido', desfazer: { 'etapa_id' => qualificacao.id, 'modo' => 'rascunho' })

      expect(antiga.desfazer!(user)).to be(true)
      expect(conversa.reload.custom_attributes['ia_pausa']).to eq('pausada')

      # reload: o desfazer devolveu a etapa por outra instância do lead; a desta, ainda em Perdido, não gravaria nada
      lead.reload.update!(lead_stage: account.lead_stages.find_by(is_lost: true), lost_reason: 'Honorário')
      expect(acao(acao: 'perdido', desfazer: { 'etapa_id' => qualificacao.id, 'pausa' => nil }).desfazer!(user)).to be(true)
      expect(conversa.reload.custom_attributes).not_to have_key('ia_pausa')
    end

    it 'Ganho que veio de Perdido volta a Perdido com o motivo guardado' do
      perdido = account.lead_stages.find_by(is_lost: true)
      lead.update!(lead_stage: account.lead_stages.find_by(is_won: true))
      a = acao(desfazer: { 'etapa_id' => perdido.id, 'lost_reason' => 'Honorário' })

      expect(a.desfazer!(user)).to be(true)
      expect(lead.reload).to have_attributes(lead_stage: perdido, lost_reason: 'Honorário')
    end

    it 'se um humano moveu o lead depois da IA, recusa e não mexe em nada' do
      lead.update!(lead_stage: account.lead_stages.find_by(label: 'fase-negociacao'))
      a = acao(acao: 'mover_etapa', alvo: qualificacao.name, desfazer: { 'etapa_id' => novo.id })

      expect(a.desfazer!(user)).to be(false)
      expect(lead.reload.lead_stage.label).to eq('fase-negociacao')
      expect(a.reload.desfeita_em).to be_nil
    end

    it 'mover_etapa ainda na etapa produzida desfaz normalmente' do
      lead.update!(lead_stage: qualificacao)
      a = acao(acao: 'mover_etapa', alvo: qualificacao.name, desfazer: { 'etapa_id' => novo.id })

      expect(a.desfazer!(user)).to be(true)
      expect(lead.reload.lead_stage).to eq(novo)
    end

    it 'tarefa de follow-up criada pela ação é apagada' do
      task = create(:lead_task, account: account, lead: lead, kind: 'follow_up')

      expect(acao(desfazer: { 'task_id' => task.id }).desfazer!(user)).to be(true)
      expect(LeadTask.exists?(task.id)).to be(false)
    end

    it 'reunião é cancelada só depois do commit (fora do lock)' do
      task = create(:lead_task, account: account, lead: lead, kind: 'meeting')
      a = acao(desfazer: { 'task_id' => task.id })
      fora = ActiveRecord::Base.connection.open_transactions
      durante = nil
      allow(Ramon::ReuniaoAgendamento).to receive(:cancelar) { durante = ActiveRecord::Base.connection.open_transactions }

      expect(a.desfazer!(user)).to be(true)
      expect(Ramon::ReuniaoAgendamento).to have_received(:cancelar).with(task: task, user: user)
      expect(durante).to eq(fora)
    end

    it 'perdido devolve a Pausa guardada pelo calar (PerfilIa.restaurar_pausa), não a gravada na ação' do
      conversa = create(:conversation, account: account)
      lead.update!(conversation: conversa, lead_stage: qualificacao)
      lead.update!(lead_stage: account.lead_stages.find_by(is_lost: true), lost_reason: 'Honorário')
      Ramon::Roteiro::Efeitos.calar(lead)
      a = acao(acao: 'perdido', desfazer: { 'etapa_id' => qualificacao.id, 'pausa' => 'rascunho' })

      expect(a.desfazer!(user)).to be(true)
      expect(conversa.reload.custom_attributes).not_to have_key('ia_pausa')
      expect(conversa.custom_attributes).not_to have_key(Ramon::PerfilIa::PAUSA_ANTES)
    end

    # O Marcador recalcula a cada turno pela Etapa: desfazer um avanço não tem modo nem carimbo a devolver.
    it 'desfazer um avanço não mexe na conversa' do
      atributos = { 'copiloto_limite' => { 'limite' => 'reuniao', 'em' => 1.day.ago.iso8601 } }
      conversa = create(:conversation, account: account, custom_attributes: atributos)
      lead.update!(conversation: conversa, lead_stage: qualificacao)
      a = acao(acao: 'mover_etapa', alvo: qualificacao.name, desfazer: { 'etapa_id' => novo.id })

      expect(a.desfazer!(user)).to be(true)
      expect(lead.reload.lead_stage).to eq(novo)
      expect(conversa.reload.custom_attributes).to eq(atributos.deep_stringify_keys)
    end

    it 'prefere etapa_produzida_id ao nome do alvo (etapa renomeada depois)' do
      lead.update!(lead_stage: account.lead_stages.find_by(label: 'fase-negociacao'))
      movida = acao(acao: 'mover_etapa', alvo: 'Nome antigo', desfazer: { 'etapa_id' => novo.id, 'etapa_produzida_id' => qualificacao.id })
      expect(movida.desfazer!(user)).to be(false)

      lead.update!(lead_stage: qualificacao)
      expect(movida.desfazer!(user)).to be(true)
      expect(lead.reload.lead_stage).to eq(novo)
    end
  end
end
