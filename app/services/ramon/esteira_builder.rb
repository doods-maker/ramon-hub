# A Esteira: fila única do dia ordenada por urgência x dinheiro.
# Junta as fontes que já alimentam o Centro de Comando (Ramon::LeadRadar),
# mescla motivos por lead (um lead aparece UMA vez) e pontua cada item.
class Ramon::EsteiraBuilder
  # Pesos de urgência; lead.value desempata (maior primeiro).
  WEIGHTS = {
    'PRESCRIPTION_BLEEDING' => 100,
    'PRESCRIPTION_LOST' => 100,
    'PRESCRIPTION_SOON' => 85,
    'SLA_BREACH' => 82,
    'TASK_OVERDUE' => 80,
    'TASK_TODAY' => 75,
    'NEW_FROM_LP' => 70,
    'STALLED' => 40
  }.freeze

  # Ação sugerida deriva do motivo mais urgente do item.
  ACTIONS = {
    'PRESCRIPTION_BLEEDING' => 'contact',
    'PRESCRIPTION_LOST' => 'contact',
    'PRESCRIPTION_SOON' => 'contact',
    'SLA_BREACH' => 'reply',
    'TASK_OVERDUE' => 'task',
    'TASK_TODAY' => 'task',
    'NEW_FROM_LP' => 'reply',
    'STALLED' => 'follow_up'
  }.freeze

  PRESCRIPTION_SOON_MONTHS = 6
  DONE_KIND = 'esteira_done'.freeze
  # "Hoje" no fuso do escritório — o mesmo dia da meta (Ramon::CockpitMetrics).
  TIME_ZONE = 'America/Sao_Paulo'.freeze

  def initialize(account:)
    @account = account
    @entries = {} # lead_id => { lead:, reasons: [{key:, params:}], task_id: }
  end

  def perform
    collect_tasks
    collect_prescription
    collect_sla_breach
    collect_new_from_lp
    collect_stalled
    items = build_items
    { items: items, board: board(items) }
  end

  private

  # ---- Fontes ------------------------------------------------------------

  def collect_tasks
    @account.lead_tasks.overdue.order(:due_at).includes(lead: [:lead_stage, :contact]).each do |task|
      add(task.lead, 'TASK_OVERDUE', { title: task.title }, task: task)
    end
    @account.lead_tasks.due_today.order(:due_at).includes(lead: [:lead_stage, :contact]).each do |task|
      add(task.lead, 'TASK_TODAY', { title: task.title }, task: task)
    end
  end

  def collect_prescription
    Ramon::LeadRadar.active_leads(@account).where.not(dcb_em: nil).find_each do |lead|
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

  # SLA de 1º contato estourado (mock 3a): conversa aberta, sem 1ª resposta,
  # além do SLA da inbox (ou do padrão do env) — o lead sobe na Esteira.
  def collect_sla_breach
    Ramon::LeadRadar.active_leads(@account)
                    .joins(:conversation).includes(conversation: :inbox)
                    .where(conversations: { first_reply_created_at: nil, status: Conversation.statuses[:open] })
                    .find_each do |lead|
      sla = lead.sla_info
      add(lead, 'SLA_BREACH', { minutes: sla[:minutes] }) if sla.present? && sla[:due_at] < Time.current
    end
  end

  def collect_new_from_lp
    Ramon::LeadRadar.new_from_lp_leads(@account).each do |lead|
      add(lead, 'NEW_FROM_LP', { source: lead.source })
    end
  end

  def collect_stalled
    Ramon::LeadRadar.stalled_leads(@account).each do |lead|
      add(lead, 'STALLED', { days: days_in_stage(lead) })
    end
  end

  # ---- Montagem ----------------------------------------------------------

  # Mescla por lead: 1ª ocorrência cria a entrada; motivos repetidos (ex.: duas
  # tasks vencidas) não duplicam; task_id guarda a task mais urgente (p/ Adiar)
  # e task_kind diz se é reunião (essa não se adia: Remarcar no painel).
  def add(lead, key, params = {}, task: nil)
    return if lead.nil?

    entry = @entries[lead.id] ||= { lead: lead, reasons: [], task_id: nil, task_kind: nil }
    guardar_task(entry, task)
    return if entry[:reasons].any? { |r| r[:key] == key }

    entry[:reasons] << { key: key, params: params }
  end

  # A 1ª task que chega é a mais urgente (vencidas vêm antes) — as seguintes não trocam.
  def guardar_task(entry, task)
    return if task.nil? || entry[:task_id]

    entry[:task_id] = task.id
    entry[:task_kind] = task.kind
  end

  def build_items
    entries = @entries.except(*done_today_lead_ids).values
    messages = last_messages_for(entries)
    entries.map { |entry| item_for(entry, messages) }
           .sort_by { |item| [-item[:score], -item[:value].to_f] }
  end

  def item_for(entry, messages)
    lead = entry[:lead]
    reasons = entry[:reasons].sort_by { |r| -WEIGHTS.fetch(r[:key]) }
    lead_fields(lead).merge(
      task_id: entry[:task_id], task_kind: entry[:task_kind],
      score: WEIGHTS.fetch(reasons.first[:key]),
      suggested_action: ACTIONS.fetch(reasons.first[:key]),
      reasons: reasons
    ).merge(context_fields(lead, messages))
  end

  def lead_fields(lead)
    {
      lead_id: lead.id, name: lead.name,
      stage_name: lead.lead_stage&.name, stage_color: lead.lead_stage&.color,
      value: lead.value&.to_f,
      conversation_id: lead.conversation_id, contact_id: lead.contact_id,
      contact_phone: lead.contact&.phone_number
    }
  end

  # Contexto de trabalho do item: tese, última simulação e última mensagem.
  def context_fields(lead, messages)
    {
      thesis_id: lead.thesis_id,
      ultima_simulacao: (lead.custom_attributes || {})['ultima_simulacao'],
      last_message: last_message_payload(messages[lead.conversation_id])
    }
  end

  # Última mensagem visível (não-privada) de cada conversa da fila, numa query
  # só (DISTINCT ON) — a fila é pequena, mas sem N+1 mesmo assim.
  def last_messages_for(entries)
    conversation_ids = entries.filter_map { |entry| entry[:lead].conversation_id }
    return {} if conversation_ids.blank?

    # reorder (não order): o default_scope do Message ordena por created_at e o
    # ORDER BY inicial precisa começar pelo conversation_id do DISTINCT ON.
    Message.where(conversation_id: conversation_ids, private: false, message_type: [:incoming, :outgoing])
           .select('DISTINCT ON (conversation_id) messages.*')
           .reorder('conversation_id, created_at DESC')
           .index_by(&:conversation_id)
  end

  def last_message_payload(message)
    return if message.nil?

    { content: message.content.to_s.truncate(200), at: message.created_at.to_i, incoming: message.incoming? }
  end

  # "Feito" tira o lead da fila do dia inteiro, independente da fonte.
  def done_today_lead_ids
    @done_today_lead_ids ||= @account.lead_activities
                                     .where(kind: DONE_KIND, created_at: today_range)
                                     .reorder(nil).distinct.pluck(:lead_id)
  end

  def today_range
    Time.current.in_time_zone(TIME_ZONE).all_day
  end

  def days_in_stage(lead)
    return 0 if lead.stage_entered_at.blank?

    ((Time.current - lead.stage_entered_at) / 1.day).floor
  end

  def board(items)
    {
      total: items.size,
      value_sum: items.sum { |item| item[:value].to_f },
      done_today: @account.lead_activities.where(kind: DONE_KIND, created_at: today_range).count
    }
  end
end
