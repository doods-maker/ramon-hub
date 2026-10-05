json.array! @tools do |tool|
  json.id tool[:id]
  json.title tool[:title]
  json.description tool[:description]
  json.icon tool[:icon]
  json.nivel tool[:nivel]
end
