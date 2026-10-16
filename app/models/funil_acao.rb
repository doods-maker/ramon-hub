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

  # Reverte o que a ação fez (payload `desfazer`). false = já desfeita. O banco volta tudo ou nada sob o lock do lead;
  # cancelar a reunião (sino, Disparo, push) só depois do commit — um aviso não sai de um desfazer que deu rollback.
  def desfazer!(user)
    reuniao = nil
    feito = lead.with_lock do
      reload
      next false if desfeita_em || movida_depois?

      restaurar_etapa
      restaurar_modo
      reuniao = desfazer_tarefa
      update!(desfeita_em: Time.current, desfeita_por: user)
      true
    end
    Ramon::ReuniaoAgendamento.cancelar(task: reuniao, user: user) if feito && reuniao
    feito
  end

  # Um humano mexeu na etapa depois da IA: desfazer sobrescreveria a decisão dele (só vale p/ ações que mudam etapa).
  # etapa_produzida_id vem no payload; ações antigas, sem ele, caem na busca pelo nome/tipo.
  def movida_depois?
    produzida_id = desfazer['etapa_produzida_id'] || etapa_produzida&.id
    desfazer['etapa_id'].present? && produzida_id.present? && lead.lead_stage_id != produzida_id
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
    desfazer_limite
  end

  # O avanço pode ter encerrado um modo "sozinha até…" (Lead → CopilotoLimite.verificar). Carimbo desta ação (não
  # anterior a ela) e o lead, de volta, sem alcançar o limite: devolve o modo (o desfazer confere carimbo e rascunho).
  def desfazer_limite
    conversa = lead.conversation
    carimbo = conversa&.custom_attributes&.[]('copiloto_limite')
    return unless carimbo.is_a?(Hash) && Ramon::CopilotoLimite::NIVEIS.include?(carimbo['limite'])
    return if Time.zone.parse(carimbo['em'].to_s).to_i < created_at.to_i || Ramon::CopilotoLimite.atingido?(carimbo['limite'], lead)

    Ramon::CopilotoLimite.desfazer(conversa, carimbo['limite'])
  end

  # O inverso do calar (que guardou o modo de antes em CopilotoModo::MODO_ANTES). Sem o guardado (já restaurado por
  # outro caminho, ou ação antiga), vale o 'modo' gravado na ação.
  def restaurar_modo
    conversa = lead.conversation
    return if desfazer['modo'].blank? || conversa.nil?

    Ramon::CopilotoModo.restaurar(conversa) ||
      conversa.update!(custom_attributes: (conversa.custom_attributes || {}).merge('copiloto_modo' => desfazer['modo']))
    Ramon::Roteiro::Efeitos.tirar_etiqueta(conversa)
  end

  # Follow-up some aqui (dentro do lock); a reunião volta para ser cancelada depois do commit.
  def desfazer_tarefa
    task = lead.lead_tasks.find_by(id: desfazer['task_id'])
    return if task.nil?
    return task if task.kind == 'meeting'

    task.destroy!
    nil
  end
end
