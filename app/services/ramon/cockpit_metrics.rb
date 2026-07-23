# Agregados do Cockpit do SDR (redesign): meta do dia, conversão etapa→etapa,
# time da semana, agenda de hoje, perdas por tese e SLA de 1ª resposta.
# Todas as consultas são agregadas (group/pluck) — nada de N+1 por lead.
class Ramon::CockpitMetrics
  AGENDA_LIMIT = 12
  TIME_ZONE = 'America/Sao_Paulo'.freeze

  def initialize(account)
    @account = account
  end

  # ---- Meta do dia --------------------------------------------------------

  def goal
    done = @account.lead_activities.where(kind: Ramon::EsteiraBuilder::DONE_KIND, created_at: today_range).count
    { target: ENV.fetch('RAMON_DAILY_GOAL', '12').to_i, done: done }
  end

  # ---- Conversão etapa→etapa (90d) ----------------------------------------

  # Aproximação documentada: "entrou" = teve stage_changed com to_value da
  # etapa (lead criado direto na etapa fica de fora); "avançou" = qualquer
  # stage_changed posterior para etapa de position maior (won conta, lost não).
  def conversion
    stages = @account.lead_stages.to_a # default_scope já ordena por position
    activities_by_lead = stage_changes_by_lead
    position_by_name = stages.reject(&:is_lost).to_h { |s| [s.name, s.position] }
    stages.reject { |s| s.is_won || s.is_lost }.map do |stage|
      conversion_row(stage, position_by_name, activities_by_lead)
    end
  end

  # ---- Time da semana (7d) ------------------------------------------------

  # Só entra quem teve ganho ou atividade no período; ordenado por valor ganho.
  def team_week
    wins = week_wins_by_user
    activities = @account.lead_activities.where(created_at: 7.days.ago..)
                         .where.not(user_id: nil).reorder(nil).group(:user_id).count
    users = User.where(id: wins.keys | activities.keys).index_by(&:id)
    users.map { |user_id, user| team_week_row(user_id, user, wins, activities) }
         .sort_by { |row| -row[:won_value] }
  end

  # ---- Agenda de hoje -----------------------------------------------------

  # Reuniões de hoje, abertas ou não (o Cockpit mostra o dia inteiro).
  def agenda_today
    @account.lead_tasks.where(kind: 'meeting', due_at: today_range)
            .includes(:user, :lead).order(:due_at).limit(AGENDA_LIMIT).map do |task|
      { id: task.id, lead_id: task.lead_id, lead_name: task.lead&.name, title: task.title,
        due_at: task.due_at, user_name: task.user&.name, source: task.lead&.source }
    end
  end

  # ---- Perdas por tese (90d + trimestre anterior p/ o delta ↑/↓) ----------

  def losses_by_thesis
    totals = lost_leads_90d.group(:thesis_id).count
    reasons = lost_leads_90d.group(:thesis_id, :lost_reason).count
    prev_totals = leads_funil.where(lost_at: 180.days.ago...90.days.ago).reorder(nil).group(:thesis_id).count
    { window_days: 90, theses: losses_theses(totals, prev_totals, reasons) }
  end

  # ---- SLA de 1ª resposta (hoje) ------------------------------------------

  # Mesmo critério do RamonLeadListener: conversas nascidas em inbox com
  # auto_create_lead (é a coluna booleana da inbox que marca inbox de lead).
  def sla_today
    replied = sla_conversations.where.not(first_reply_created_at: nil)
    { breached: sla_breached_count(replied), avg_first_response_minutes: sla_average_minutes(replied) }
  end

  private

  # Placar comercial não conta caso de cálculo (tela Cálculos ← AdvBox).
  def leads_funil
    @account.leads.funil
  end

  # "Hoje" sempre no fuso do escritório.
  def today_range
    Time.current.in_time_zone(TIME_ZONE).all_day
  end

  # 1 pluck; agregação por lead em memória (volume de 90d é pequeno).
  def stage_changes_by_lead
    @account.lead_activities
            .where(kind: 'stage_changed', created_at: 90.days.ago..)
            .reorder(nil).pluck(:lead_id, :created_at, :to_value)
            .group_by(&:first)
  end

  def conversion_row(stage, position_by_name, activities_by_lead)
    entered = 0
    advanced = 0
    activities_by_lead.each_value do |acts|
      entry = acts.select { |(_id, _at, to)| to == stage.name }.min_by { |(_id, at, _to)| at }
      next if entry.nil?

      entered += 1
      advanced += 1 if acts.any? { |(_id, at, to)| at > entry[1] && position_by_name.fetch(to, -1) > stage.position }
    end
    { stage_id: stage.id, name: stage.name, entered: entered, advanced: advanced,
      rate: entered.zero? ? 0 : (advanced * 100.0 / entered).round }
  end

  # won atribuído ao closer; sem closer, cai pro SDR.
  def week_wins_by_user
    rows = leads_funil.where(won_at: 7.days.ago..).reorder(nil).pluck(:closer_id, :sdr_id, :value)
    rows.each_with_object({}) do |(closer_id, sdr_id, value), acc|
      user_id = closer_id || sdr_id
      next if user_id.nil?

      win = (acc[user_id] ||= { won_count: 0, won_value: 0.0 })
      win[:won_count] += 1
      win[:won_value] += value.to_f
    end
  end

  def team_week_row(user_id, user, wins, activities)
    win = wins[user_id] || { won_count: 0, won_value: 0.0 }
    { user_id: user_id, name: user.name, avatar_url: user.avatar_url,
      won_count: win[:won_count], won_value: win[:won_value], activities_count: activities[user_id].to_i }
  end

  def lost_leads_90d
    leads_funil.where(lost_at: 90.days.ago..).reorder(nil)
  end

  def losses_theses(totals, prev_totals, reasons)
    thesis_ids = totals.keys | prev_totals.keys
    names = @account.theses.where(id: thesis_ids.compact).pluck(:id, :name).to_h
    thesis_ids.map { |thesis_id| losses_row(thesis_id, names, totals, prev_totals, reasons) }
              .sort_by { |row| -row[:total] }
  end

  def losses_row(thesis_id, names, totals, prev_totals, reasons)
    {
      thesis_id: thesis_id,
      name: names[thesis_id] || 'Sem tese',
      total: totals[thesis_id].to_i,
      prev_total: prev_totals[thesis_id].to_i,
      reasons: reasons.select { |(tid, _reason), _count| tid == thesis_id }
                      .map { |(_tid, reason), count| { reason: reason.presence || '—', count: count } }
                      .sort_by { |row| -row[:count] }
    }
  end

  def sla_conversations
    @account.conversations
            .where(inbox_id: @account.inboxes.where(auto_create_lead: true).select(:id))
            .where(created_at: today_range)
  end

  # Estourou = sem resposta e criada há mais de N min, OU respondida além de N.
  def sla_breached_count(replied)
    minutes = ENV.fetch('RAMON_SLA_FIRST_RESPONSE_MINUTES', '15').to_i
    waiting = sla_conversations.where(first_reply_created_at: nil).where(created_at: ...minutes.minutes.ago).count
    over = replied.where('EXTRACT(EPOCH FROM (first_reply_created_at - created_at)) > ?', minutes * 60).count
    waiting + over
  end

  def sla_average_minutes(replied)
    avg = replied.average(Arel.sql('EXTRACT(EPOCH FROM (first_reply_created_at - created_at)) / 60.0'))
    avg&.to_f&.round(1)
  end
end
