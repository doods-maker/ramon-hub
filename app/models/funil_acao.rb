# Ação automática do funil (ver Ramon::FunilAutomatico). Ensaio = só registrada, nunca aplicada.
class FunilAcao < ApplicationRecord
  self.table_name = 'ramon_funil_acoes'

  belongs_to :account
  belongs_to :lead
  belongs_to :desfeita_por, class_name: 'User', optional: true

  scope :reais, -> { where(ensaio: false) }
  scope :vivas, -> { reais.where(desfeita_em: nil) }

  # Texto curto do chip do card ("IA: …"): a ação do histórico, sem o prefixo técnico.
  def texto = [acao.to_s.tr('_', ' '), alvo].compact_blank.join(' → ')

  # Última ação viva do lead nas últimas 24h, para o chip do card (nil = sem chip).
  def self.chip(lead) = chips([lead.id])[lead.id]

  # Em lote (índice do Kanban): UMA query para todos os leads → { lead_id => { id:, texto: } }.
  def self.chips(lead_ids)
    ultimas = vivas.where(lead_id: lead_ids, created_at: 24.hours.ago..).order(:id).index_by(&:lead_id)
    ultimas.transform_values { |a| { id: a.id, texto: a.texto } }
  end

  # Reverte o que a ação fez (payload `desfazer`). false = já desfeita. Tudo ou nada, sob lock do lead.
  def desfazer!(user)
    lead.with_lock do
      reload
      next false if desfeita_em || movida_depois?

      restaurar_etapa
      restaurar_modo
      desfazer_tarefa(user)
      update!(desfeita_em: Time.current, desfeita_por: user)
      true
    end
  end

  # Um humano mexeu na etapa depois da IA: desfazer sobrescreveria a decisão dele (só vale p/ ações que mudam etapa).
  def movida_depois?
    produzida = etapa_produzida
    desfazer['etapa_id'].present? && produzida.present? && lead.lead_stage_id != produzida.id
  end

  private

  def etapa_produzida
    case acao
    when 'mover_etapa', 'marcar_ganho' then account.lead_stages.find_by(name: alvo)
    when 'perdido' then account.lead_stages.find_by(is_lost: true)
    end
  end

  def restaurar_etapa
    return if desfazer['etapa_id'].blank?

    # lost_reason só existe no payload quando a etapa de volta é Perdido; senão o lead zera o motivo
    lead.update!(lead_stage_id: desfazer['etapa_id'], lost_reason: desfazer['lost_reason'])
  end

  def restaurar_modo
    return if desfazer['modo'].blank? || lead.conversation.nil?

    Ramon::CopilotoModo.trocar(lead.conversation, desfazer['modo'])
    Ramon::Roteiro::Efeitos.tirar_etiqueta(lead.conversation)
  end

  def desfazer_tarefa(user)
    task = lead.lead_tasks.find_by(id: desfazer['task_id'])
    return if task.nil?

    task.kind == 'meeting' ? Ramon::ReuniaoAgendamento.cancelar(task: task, user: user) : task.destroy!
  end
end
