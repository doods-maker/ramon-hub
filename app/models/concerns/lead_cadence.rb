# Cadência do lead (SLA de 1ª resposta, próxima tarefa e o pedaço de cadência
# do payload de broadcast) — extraído do Lead pelo limite de tamanho do
# rubocop; mesmo comportamento, mesmos nomes públicos.
module LeadCadence
  extend ActiveSupport::Concern

  # Tarefa aberta com o menor due_at — fonte de next_task_due_at/next_task_title
  # no jbuilder e no broadcast. Mesmo padrão do latest_triage: com lead_tasks
  # pré-carregada (índice do Kanban via includes) resolve em memória, sem query.
  def next_open_task
    if lead_tasks.loaded?
      lead_tasks.select { |t| t.completed_at.nil? }.min_by(&:due_at)
    else
      lead_tasks.open_tasks.order(:due_at).first
    end
  end

  # SLA de 1ª resposta calculado da conversa do lead (mesma regra do
  # FirstResponseSlaJob): nil sem conversa ou com inbox fora do funil de
  # entrada (sem auto_create_lead). Vai no jbuilder (slim e completo) e no
  # broadcast — o card do Kanban desenha o timer a partir daqui.
  def sla_info
    inbox = conversation&.inbox
    return nil unless inbox&.auto_create_lead?

    minutes = inbox.first_response_sla_minutes || ENV.fetch('RAMON_SLA_FIRST_RESPONSE_MINUTES', '15').to_i
    {
      due_at: conversation.created_at + minutes.minutes,
      replied_at: conversation.first_reply_created_at,
      minutes: minutes
    }
  end

  private

  def cadence_event_data
    next_task = next_open_task
    {
      stage_entered_at: stage_entered_at,
      won_at: won_at,
      lost_at: lost_at,
      stalled: stalled?,
      open_tasks_count: lead_tasks.open_tasks.size,
      next_task_due_at: next_task&.due_at,
      next_task_title: next_task&.title,
      dcb_em: dcb_em,
      # BigDecimal não é JSON nativo — Sidekiq strict_args rejeita no broadcast (mesmo motivo de `value` no push_event_data)
      benefit_monthly_value: benefit_monthly_value&.to_f,
      cnis_resumo: cnis_resumo,
      sla: sla_info,
      # jsonb já é JSON nativo; painel aberto recebe colheita/doc_status ao vivo
      custom_attributes: custom_attributes || {}
    }.merge(contact_event_data).merge(follow_up_event_data)
  end

  def contact_event_data
    {
      contact_phone: contact&.phone_number,
      contact_cpf: contact&.cpf,
      # Date segue o precedente de dcb_em no mesmo hash
      contact_data_nascimento: contact&.data_nascimento,
      contact_sexo: contact&.sexo
    }
  end

  # espelho do jbuilder: o badge do card/banner lê os escalares, não o jsonb
  def follow_up_event_data
    {
      follow_up_count: custom_attributes.dig('follow_up', 'tentativas').to_i,
      follow_up_last_at: custom_attributes.dig('follow_up', 'ultima_em')
    }
  end
end
