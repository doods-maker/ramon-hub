json.today do
  json.tasks_overdue do
    json.count @today[:tasks_overdue][:count]
    json.items @today[:tasks_overdue][:items], partial: 'task', as: :task
  end
  json.tasks_today do
    json.count @today[:tasks_today][:count]
    json.items @today[:tasks_today][:items], partial: 'task', as: :task
  end
  json.stalled do
    json.count @today[:stalled][:count]
    json.items @today[:stalled][:items], partial: 'lead', as: :lead
  end
  json.no_next_action do
    json.count @today[:no_next_action][:count]
    json.items @today[:no_next_action][:items], partial: 'lead', as: :lead
  end
  json.new_from_lp do
    json.count @today[:new_from_lp][:count]
    json.items @today[:new_from_lp][:items], partial: 'lead', as: :lead
  end
end

json.funnel do
  json.array! @funnel do |row|
    json.stage_id row[:stage_id]
    json.name row[:name]
    json.color row[:color]
    json.count row[:count]
    json.total_value row[:total_value]
    json.weighted_value row[:weighted_value]
    json.is_won row[:is_won]
    json.is_lost row[:is_lost]
  end
end

json.week do
  json.created_by_channel @week[:created_by_channel] do |row|
    json.key row[:key]
    json.label row[:label]
    json.count row[:count]
  end
  json.won @week[:won]
  json.lost @week[:lost]
  json.created @week[:created]
  json.lost_reasons_30d @week[:lost_reasons_30d] do |reason, count|
    json.reason reason.presence || '—'
    json.count count
  end
  json.nps do
    json.media @week[:nps][:media]
    json.respostas @week[:nps][:respostas]
  end
end

json.history @history do |row|
  json.date row[:date]
  json.leads_count row[:leads_count]
  json.value_sum row[:value_sum]
end

json.goal do
  json.target @goal[:target]
  json.done @goal[:done]
end

json.forecast_total @forecast_total

json.conversion @conversion do |row|
  json.stage_id row[:stage_id]
  json.name row[:name]
  json.entered row[:entered]
  json.advanced row[:advanced]
  json.rate row[:rate]
end

json.team_week @team_week do |row|
  json.user_id row[:user_id]
  json.name row[:name]
  json.avatar_url row[:avatar_url]
  json.won_count row[:won_count]
  json.won_value row[:won_value]
  json.activities_count row[:activities_count]
end

json.agenda_today @agenda_today do |row|
  json.id row[:id]
  json.lead_id row[:lead_id]
  json.lead_name row[:lead_name]
  json.title row[:title]
  json.due_at row[:due_at]
  json.user_name row[:user_name]
  json.source row[:source]
end

json.losses_by_thesis do
  json.window_days @losses_by_thesis[:window_days]
  json.theses @losses_by_thesis[:theses] do |thesis|
    json.thesis_id thesis[:thesis_id]
    json.name thesis[:name]
    json.total thesis[:total]
    json.prev_total thesis[:prev_total]
    json.reasons thesis[:reasons] do |reason|
      json.reason reason[:reason]
      json.count reason[:count]
    end
  end
end

json.sla_today do
  json.breached @sla_today[:breached]
  json.avg_first_response_minutes @sla_today[:avg_first_response_minutes]
end

# Placar de TV (/tv): hash pronto do CockpitMetrics — jbuilder serializa direto.
json.tv @tv
