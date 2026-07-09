# Consultas de "radar do dia" compartilhadas entre o Centro de Comando
# (ramon_dashboard_controller) e a Esteira (esteira_builder).
module Ramon::LeadRadar
  module_function

  def active_leads(account)
    account.leads.joins(:lead_stage).includes(:lead_stage, :contact)
           .where(lead_stages: { is_won: false, is_lost: false })
  end

  def stalled_leads(account)
    active_leads(account)
      .where.not(lead_stages: { stalled_after_days: nil })
      .where("leads.stage_entered_at < NOW() - (lead_stages.stalled_after_days || ' days')::interval")
  end

  def new_from_lp_leads(account)
    account.leads.includes(:lead_stage, :contact)
           .where.not(source: [nil, ''])
           .where(conversation_id: nil, created_at: 48.hours.ago..)
           .where.not(id: account.lead_notes.select(:lead_id))
           .where.not(id: account.lead_tasks.select(:lead_id))
  end
end
