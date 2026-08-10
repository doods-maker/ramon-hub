# Consultas de "radar do dia" compartilhadas entre o Centro de Comando
# (ramon_dashboard_controller) e a Esteira (esteira_builder).
module Ramon::LeadRadar
  module_function

  # includes cobre tudo que o partial _lead deriva do lead (sla_info via
  # conversation→inbox, next_open_task via lead_tasks, latest_triage) — sem N+1.
  def active_leads(account)
    account.leads.funil.joins(:lead_stage)
           .includes(:lead_stage, :contact, :lead_tasks, :lead_triages, { conversation: :inbox })
           .where(lead_stages: { is_won: false, is_lost: false })
  end

  def stalled_leads(account)
    Ramon::Cadencia.parados(active_leads(account))
  end

  def new_from_lp_leads(account)
    account.leads.funil.includes(:lead_stage, :contact, :lead_tasks, :lead_triages, { conversation: :inbox })
           .where.not(source: [nil, ''])
           .where(conversation_id: nil, created_at: 48.hours.ago..)
           .where.not(id: account.lead_notes.select(:lead_id))
           .where.not(id: account.lead_tasks.select(:lead_id))
  end
end
