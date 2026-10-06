json.summary do
  json.bleeding_monthly @summary[:bleeding_monthly]
  json.bleeding_count @summary[:bleeding_count]
  json.at_risk_90d_monthly @summary[:at_risk_90d_monthly]
  json.at_risk_90d_count @summary[:at_risk_90d_count]
  json.total_count @summary[:total_count]
  json.rescue_count @summary[:rescue_count]
end

json.items @items do |item|
  json.merge! item
end
