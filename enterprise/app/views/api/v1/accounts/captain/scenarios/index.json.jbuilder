json.payload do
  json.array! @scenarios do |scenario|
    json.partial! 'api/v1/models/captain/scenario', scenario: scenario
    json.uso_30d(scenario.tools.to_a.sum { |tool| @uso[tool].to_i })
  end
end

json.meta do
  json.total_count @scenarios.count
  json.page 1
end
