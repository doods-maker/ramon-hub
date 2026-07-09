# A Esteira: fila única do dia ordenada por urgência x dinheiro.
# Junta as fontes que já alimentam o Centro de Comando (Ramon::LeadRadar),
# mescla motivos por lead (um lead aparece UMA vez) e pontua cada item.
class Ramon::EsteiraBuilder
  # Pesos de urgência; lead.value desempata (maior primeiro).
  WEIGHTS = {
    'PRESCRIPTION_BLEEDING' => 100,
    'PRESCRIPTION_LOST' => 100,
    'PRESCRIPTION_SOON' => 85,
    'TASK_OVERDUE' => 80,
    'TASK_TODAY' => 75,
    'NEW_FROM_LP' => 70,
    'AWAITING_HUMAN' => 60,
    'STALLED' => 40
  }.freeze

  # Ação sugerida deriva do motivo mais urgente do item.
  ACTIONS = {
    'PRESCRIPTION_BLEEDING' => 'contact',
    'PRESCRIPTION_LOST' => 'contact',
    'PRESCRIPTION_SOON' => 'contact',
    'TASK_OVERDUE' => 'task',
    'TASK_TODAY' => 'task',
    'NEW_FROM_LP' => 'reply',
    'AWAITING_HUMAN' => 'reply',
    'STALLED' => 'follow_up'
  }.freeze

  PRESCRIPTION_SOON_MONTHS = 6
  DONE_KIND = 'esteira_done'.freeze

  def initialize(account:)
    @account = account
    @entries = {} # lead_id => { lead:, reasons: [{key:, params:}], task_id: }
  end

  def perform
    collect_tasks
    collect_prescription
    collect_new_from_lp
    collect_awaiting_human
    collect_stalled
    items = build_items
    { items: items, board: board(items) }
  end

  private

  # ---- Fontes ------------------------------------------------------------

  def collect_tasks
    @account.lead_tasks.overdue.order(:due_at).includes(lead: [:lead_stage, :contact]).each do |task|
      add(task.lead, 'TASK_OVERDUE', { title: task.title }, task_id: task.id)
    end
    @account.lead_tasks.due_today.order(:due_at).includes(lead: [:lead_stage, :contact]).each do |task|
      add(task.lead, 'TASK_TODAY', { title: task.title }, task_id: task.id)
    end
  end

  def collect_prescription
    Ramon::LeadRadar.active_leads(@account).where.not(dcb_em: nil).each do |lead|
      add_prescription_reason(lead, lead.prescription)
    end
  end

  def add_prescription_reason(lead, info)
    return if info.blank?

    if info[:lost_installments].positive?
      return add(lead, 'PRESCRIPTION_BLEEDING', { monthly: lead.benefit_monthly_value.to_f }) if lead.benefit_monthly_value.present?

      add(lead, 'PRESCRIPTION_LOST', { count: info[:lost_installments] })
    else
      months_to_cliff = Lead::PRESCRIPTION_WINDOW_MONTHS - info[:months_since_dcb]
      add(lead, 'PRESCRIPTION_SOON', { months: months_to_cliff }) if months_to_cliff <= PRESCRIPTION_SOON_MONTHS
    end
  end

  def collect_new_from_lp
    Ramon::LeadRadar.new_from_lp_leads(@account).each do |lead|
      add(lead, 'NEW_FROM_LP', { source: lead.source })
    end
  end

  # ponytail: status como string até o PR #48 (handoff por confiança) chegar
  # na ramon — antes dele a query só devolve vazio, sem quebrar nada.
  def collect_awaiting_human
    triaged_ids = @account.lead_triages.where(status: 'awaiting_human').select(:lead_id)
    Ramon::LeadRadar.active_leads(@account).where(id: triaged_ids).each do |lead|
      add(lead, 'AWAITING_HUMAN')
    end
  end

  def collect_stalled
    Ramon::LeadRadar.stalled_leads(@account).each do |lead|
      add(lead, 'STALLED', { days: days_in_stage(lead) })
    end
  end

  # ---- Montagem ----------------------------------------------------------

  # Mescla por lead: 1ª ocorrência cria a entrada; motivos repetidos (ex.: duas
  # tasks vencidas) não duplicam; task_id guarda a task mais urgente (p/ Adiar).
  def add(lead, key, params = {}, task_id: nil)
    return if lead.nil?

    entry = @entries[lead.id] ||= { lead: lead, reasons: [], task_id: nil }
    entry[:task_id] ||= task_id
    return if entry[:reasons].any? { |r| r[:key] == key }

    entry[:reasons] << { key: key, params: params }
  end

  def build_items
    @entries.except(*done_today_lead_ids).values.map { |entry| item_for(entry) }
            .sort_by { |item| [-item[:score], -item[:value].to_f] }
  end

  def item_for(entry)
    lead = entry[:lead]
    reasons = entry[:reasons].sort_by { |r| -WEIGHTS.fetch(r[:key]) }
    {
      lead_id: lead.id, name: lead.name,
      stage_name: lead.lead_stage&.name, stage_color: lead.lead_stage&.color,
      value: lead.value&.to_f,
      conversation_id: lead.conversation_id, contact_id: lead.contact_id,
      contact_phone: lead.contact&.phone_number,
      task_id: entry[:task_id],
      score: WEIGHTS.fetch(reasons.first[:key]),
      suggested_action: ACTIONS.fetch(reasons.first[:key]),
      reasons: reasons
    }
  end

  # "Feito" tira o lead da fila do dia inteiro, independente da fonte.
  def done_today_lead_ids
    @done_today_lead_ids ||= @account.lead_activities
                                     .where(kind: DONE_KIND, created_at: Time.current.all_day)
                                     .reorder(nil).distinct.pluck(:lead_id)
  end

  def days_in_stage(lead)
    return 0 if lead.stage_entered_at.blank?

    ((Time.current - lead.stage_entered_at) / 1.day).floor
  end

  def board(items)
    {
      total: items.size,
      value_sum: items.sum { |item| item[:value].to_f },
      done_today: @account.lead_activities.where(kind: DONE_KIND, created_at: Time.current.all_day).count
    }
  end
end
