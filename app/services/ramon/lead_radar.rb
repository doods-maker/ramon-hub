# Consultas de "radar do dia" compartilhadas entre o Centro de Comando
# (ramon_dashboard_controller) e a Esteira (esteira_builder).
module Ramon::LeadRadar
  TIME_ZONE = 'America/Sao_Paulo'.freeze

  module_function

  # includes cobre tudo que o partial _lead deriva do lead (sla_info via
  # conversation→inbox, next_open_task via lead_tasks, latest_triage,
  # docs_counts via thesis→thesis_items) — sem N+1.
  def active_leads(account)
    account.leads.funil.joins(:lead_stage)
           .includes(:lead_stage, :contact, :lead_tasks, :lead_triages, { conversation: :inbox }, { thesis: :thesis_items })
           .where(lead_stages: { is_won: false, is_lost: false })
  end

  def stalled_leads(account)
    Ramon::Cadencia.parados(active_leads(account))
  end

  def new_from_lp_leads(account)
    account.leads.funil
           .includes(:lead_stage, :contact, :lead_tasks, :lead_triages, { conversation: :inbox }, { thesis: :thesis_items })
           .where.not(source: [nil, ''])
           .where(conversation_id: nil, created_at: 48.hours.ago..)
           .where.not(id: account.lead_notes.select(:lead_id))
           .where.not(id: account.lead_tasks.select(:lead_id))
  end

  # "Ganhos na semana" do Centro: desde a segunda-feira, no fuso do escritório.
  def week_start
    Time.current.in_time_zone(TIME_ZONE).beginning_of_week
  end

  # Clique num KPI do Centro → Funil filtrado pela MESMA regra da contagem.
  # won_since chega como data (YYYY-MM-DD) e vale desde 00h dela em SP.
  def kpi_filters(account, leads, params)
    tasks = account.lead_tasks
    leads = leads.where(id: tasks.overdue.select(:lead_id)) if params[:overdue_task].present?
    leads = leads.where(id: tasks.due_today.select(:lead_id)) if params[:task_due_today].present?
    leads = leads.where(won_at: Date.parse(params[:won_since]).in_time_zone(TIME_ZONE)..) if params[:won_since].present?
    leads = leads.where(id: new_from_lp_leads(account).reorder(nil).select(:id)) if params[:new_from_lp].present?
    leads
  end

  # Pós-venda (ADR-0001): ganhos ficam em "Fechado"; aqui a visão deriva o
  # estado — pendente = checklist de documento incompleto; concluído = completo.
  # Ganho sem item de documento na tese fica fora (nada a coletar).
  def pos_venda(account)
    ganhos = account.leads.funil.where.not(won_at: nil)
                    .includes(:contact, thesis: :thesis_items)
    com_docs = ganhos.select { |l| l.docs_counts[:total].positive? }
    pendentes, concluidos = com_docs.partition { |l| l.docs_counts[:received] < l.docs_counts[:total] }
    { pendentes: pendentes.sort_by(&:won_at), concluidos: concluidos.sort_by(&:won_at).last(20).reverse }
  end
end
