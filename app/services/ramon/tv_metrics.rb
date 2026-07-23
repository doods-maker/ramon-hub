# Agregados do Placar de TV (/tv): mês (meta/hoje), quebra por tese, corrida
# do mês, dinheiro prescrevendo, próximo compromisso e último ganho do dia.
# Herda do CockpitMetrics pra reusar leads_funil/today_range e o MESMO critério
# de SLA/ganho — classe separada só pelo limite de tamanho do rubocop.
class Ramon::TvMetrics < Ramon::CockpitMetrics
  def tv
    {
      month: tv_month,
      by_thesis: tv_by_thesis,
      race: tv_race,
      prescribing_total_monthly: open_prescribing.sum { |lead| lead.benefit_monthly_value.to_f },
      next_meeting: tv_next_meeting,
      last_won: tv_last_won
    }
  end

  private

  def month_range
    Time.current.in_time_zone(TIME_ZONE).all_month
  end

  def month_wins
    leads_funil.where(won_at: month_range).reorder(nil)
  end

  def tv_month
    {
      won_value: month_wins.sum(:value).to_f,
      won_count: month_wins.count,
      goal: ENV.fetch('RAMON_MONTHLY_GOAL_BRL', '0').to_f,
      business_days_left: business_days_left,
      today: tv_today
    }
  end

  # Dias úteis seg–sex restantes no mês (hoje inclusive), no fuso do escritório.
  def business_days_left
    today = Time.current.in_time_zone(TIME_ZONE).to_date
    (today..today.end_of_month).count { |day| (1..5).cover?(day.wday) }
  end

  def tv_today
    replied = sla_conversations.where.not(first_reply_created_at: nil)
    {
      won_count: leads_funil.where(won_at: today_range).count,
      new_count: leads_funil.where(created_at: today_range).count,
      avg_first_response_minutes: sla_average_minutes(replied)
    }
  end

  # Leads abertos carregados uma vez (volume pequeno): prescrição e parados
  # são regra por lead (Lead#prescription / Lead#stalled?), não agregável em SQL.
  def open_leads
    @open_leads ||= @account.leads.open.includes(:lead_stage).to_a
  end

  def open_prescribing
    open_leads.select { |lead| lead.prescription&.dig(:lost_installments).to_i.positive? }
  end

  def tv_by_thesis
    agg = tv_thesis_aggregates
    ids = agg[:open].keys | agg[:won].keys | agg[:new_week].keys
    ids.map { |thesis_id| tv_thesis_row(thesis_id, agg) }.sort_by { |row| -row[:leads_count] }
  end

  def tv_thesis_aggregates
    in_memory_thesis_aggregates.merge(sql_thesis_aggregates)
  end

  # Agregados que dependem de regra por lead (prescription/stalled?) — vêm
  # da coleção open_leads já em memória.
  def in_memory_thesis_aggregates
    {
      open: open_leads.group_by(&:thesis_id).transform_values(&:size),
      prescribing: open_prescribing.group_by(&:thesis_id),
      stalled: open_leads.select(&:stalled?).group_by(&:thesis_id)
    }
  end

  def sql_thesis_aggregates
    {
      new_week: leads_funil.where(created_at: 7.days.ago..).reorder(nil).group(:thesis_id).count,
      won: month_wins.group(:thesis_id).count,
      won_value: month_wins.group(:thesis_id).sum(:value),
      lost: leads_funil.where(lost_at: month_range).reorder(nil).group(:thesis_id).count,
      names: @account.theses.pluck(:id, :name).to_h
    }
  end

  def tv_thesis_row(thesis_id, agg)
    won = agg[:won][thesis_id].to_i
    lost = agg[:lost][thesis_id].to_i
    {
      thesis_id: thesis_id, name: agg[:names][thesis_id] || 'Sem tese',
      leads_count: agg[:open][thesis_id].to_i, new_week: agg[:new_week][thesis_id].to_i,
      won_month: won, won_value_month: agg[:won_value][thesis_id].to_f,
      conversion_pct: (won + lost).zero? ? nil : (won * 100.0 / (won + lost)).round
    }.merge(tv_thesis_risk(thesis_id, agg))
  end

  # Fatia de risco da linha: prescrição sangrando + parados na etapa.
  def tv_thesis_risk(thesis_id, agg)
    prescribing = agg[:prescribing][thesis_id] || []
    {
      prescribing_count: prescribing.size,
      prescribing_monthly: prescribing.sum { |lead| lead.benefit_monthly_value.to_f },
      stalled_count: (agg[:stalled][thesis_id] || []).size
    }
  end

  # Ganhos do mês por closer (fallback SDR), top 5 — mesmo critério do team_week.
  def tv_race
    wins = month_wins.pluck(:closer_id, :sdr_id, :value).each_with_object({}) do |(closer_id, sdr_id, value), acc|
      user_id = closer_id || sdr_id
      next if user_id.nil?

      win = (acc[user_id] ||= { won_count: 0, won_value: 0.0 })
      win[:won_count] += 1
      win[:won_value] += value.to_f
    end
    names = User.where(id: wins.keys).pluck(:id, :name).to_h
    wins.map { |user_id, win| { name: names[user_id] }.merge(win) }
        .sort_by { |row| -row[:won_value] }.first(5)
  end

  def tv_next_meeting
    task = @account.lead_tasks.open_tasks.where(kind: 'meeting').where(due_at: Time.current..)
                   .includes(:user, :lead).order(:due_at).first
    return nil if task.nil?

    { at: task.due_at, lead_name: task.lead&.name, user_name: task.user&.name }
  end

  # Último ganho de hoje — alimenta o ticker "Agora: <closer> fechou <lead>".
  def tv_last_won
    lead = leads_funil.where(won_at: today_range).reorder(won_at: :desc).includes(:closer, :sdr, :benefit_type).first
    return nil if lead.nil?

    { lead_name: lead.name, closer_name: (lead.closer || lead.sdr)&.name,
      value: lead.value.to_f, benefit: lead.benefit_type&.name, at: lead.won_at }
  end
end
