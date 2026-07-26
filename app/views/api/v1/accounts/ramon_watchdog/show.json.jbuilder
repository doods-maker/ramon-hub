json.thresholds @thresholds
json.counters @counters
json.items @items do |item|
  json.merge! item
end
