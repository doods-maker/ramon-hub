# Consultas de "radar do dia" compartilhadas entre o Centro de Comando
# (ramon_dashboard_controller) e a Esteira (esteira_builder).
module Ramon::LeadRadar
  TIME_ZONE = 'America/Sao_Paulo'.freeze
  # Funil: ganhos/perdidos aparecem só se fecharam nos últimos 90 dias.
  CLOSED_WINDOW = 90.days
  # Filtros que miram fechados de propósito (ou uma pessoa) dispensam a janela.
  CLOSED_WINDOW_BYPASS = %i[closed_all won_since lead_stage_id q contact_id].freeze
  # Pós-venda: concluídos mostrados (os mais recentes); o total vem à parte.
  CONCLUIDOS_LIMITE = 20

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

  # Data do fechamento = won_at/lost_at (o Lead grava ao entrar na etapa
  # ganha/perdida); stage_entered_at cobre etapa que virou ganha/perdida depois.
  def closed_window(account, leads, params)
    return leads if CLOSED_WINDOW_BYPASS.any? { |key| params[key].present? }

    closed_stage_ids = account.lead_stages.where('is_won OR is_lost').select(:id)
    leads.where.not(lead_stage_id: closed_stage_ids)
         .or(leads.where('COALESCE(leads.won_at, leads.lost_at, leads.stage_entered_at) >= ?', CLOSED_WINDOW.ago))
  end

  # Pós-venda (ADR-0001): ganhos ficam em "Fechado"; aqui a visão deriva o
  # estado — pendente = checklist de documento incompleto; concluído = completo.
  # Ganho sem tese não tem checklist (nunca vira contrato limpo): vai pro bloco
  # "Ganhos sem tese". Tese sem item de documento fica fora (nada a coletar).
  def pos_venda(account)
    ganhos = ganhos_pos_venda(account)
    com_docs = ganhos.select { |l| l.docs_counts[:total].positive? }
    pendentes, concluidos = com_docs.partition { |l| l.docs_counts[:received] < l.docs_counts[:total] }
    { pendentes: pendentes.sort_by { |l| urgencia(l) }, concluidos: concluidos.sort_by(&:won_at).last(CONCLUIDOS_LIMITE).reverse,
      concluidos_total: concluidos.size, sem_tese: ganhos.select { |l| l.thesis_id.nil? }.sort_by(&:won_at) }
  end

  def ganhos_pos_venda(account)
    account.leads.funil.where.not(won_at: nil).includes(:contact, thesis: :thesis_items)
  end

  # Ordem dos pendentes por prescrição: sangrando primeiro (maior valor mensal
  # antes), depois o prazo mais curto, sem DCB por último; empate → ganho mais antigo.
  def urgencia(lead)
    info = lead.prescription
    return [2, 0, lead.won_at] if info.nil?
    return [0, -lead.benefit_monthly_value.to_f, lead.won_at] if info[:lost_installments].positive?

    [1, Lead::PRESCRIPTION_WINDOW_MONTHS - info[:months_since_dcb], lead.won_at]
  end
end
