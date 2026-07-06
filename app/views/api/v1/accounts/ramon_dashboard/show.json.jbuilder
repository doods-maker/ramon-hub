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
  json.created_by_source @week[:created_by_source] do |source, count|
    json.source source.presence || '—'
    json.count count
  end
  json.won @week[:won]
  json.lost @week[:lost]
  json.created @week[:created]
  json.lost_reasons_30d @week[:lost_reasons_30d] do |reason, count|
    json.reason reason.presence || '—'
    json.count count
  end
end

json.history @history do |row|
  json.date row[:date]
  json.leads_count row[:leads_count]
  json.value_sum row[:value_sum]
end
