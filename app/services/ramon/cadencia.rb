# Dono único das duas regras de tempo do funil — "parado na etapa" e SLA de
# 1ª resposta. As variantes Ruby (por lead) e SQL (por escopo) da MESMA regra
# vivem lado a lado aqui de propósito: quem mudar uma enxerga a outra.
module Ramon::Cadencia
  module_function

  # ---- Parado na etapa (threshold por etapa: lead_stages.stalled_after_days) --

  # Variante SQL — filtra um escopo de leads pelos parados.
  def parados(leads)
    leads.joins(:lead_stage)
         .where.not(lead_stages: { stalled_after_days: nil })
         .where("leads.stage_entered_at < NOW() - (lead_stages.stalled_after_days || ' days')::interval")
  end

  # Variante Ruby — o booleano do jbuilder/broadcast (Lead#stalled?).
  def parado?(lead)
    limite = lead.lead_stage&.stalled_after_days
    return false if limite.blank? || lead.stage_entered_at.blank?

    lead.stage_entered_at < limite.days.ago
  end

  # ---- SLA de 1ª resposta (por inbox, fallback no env) ------------------------

  def sla_minutes(inbox)
    inbox.first_response_sla_minutes || ENV.fetch('RAMON_SLA_FIRST_RESPONSE_MINUTES', '15').to_i
  end

  # Interpolação segura: só o inteiro do env entra na string.
  def sla_threshold_sql
    "COALESCE(inboxes.first_response_sla_minutes, #{ENV.fetch('RAMON_SLA_FIRST_RESPONSE_MINUTES', '15').to_i})"
  end

  # Conversas que contam pro SLA: nascidas em inbox de lead dentro do período.
  def sla_conversations(account, range)
    account.conversations.joins(:inbox)
           .where(inboxes: { auto_create_lead: true })
           .where(conversations: { created_at: range })
  end

  # Estourou = sem resposta e criada há mais de N min, OU respondida além de N.
  # N por conversa: SLA da própria inbox, com fallback no env (COALESCE por linha).
  def sla_breached_count(scope, replied: scope)
    threshold = sla_threshold_sql
    # Epoch em vez de aritmética de interval: o bind de Time entrava como
    # literal de tipo desconhecido e o PG tentava resolvê-lo como interval.
    waiting = scope.where(first_reply_created_at: nil)
                   .where("EXTRACT(EPOCH FROM (? - conversations.created_at)) / 60.0 > (#{threshold})", Time.current).count
    over = replied.where("EXTRACT(EPOCH FROM (first_reply_created_at - conversations.created_at)) / 60.0 > (#{threshold})").count
    waiting + over
  end
end
