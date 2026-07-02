json.stages do
  json.array! @stages do |stage|
    json.id stage.id
    json.name stage.name
    json.color stage.color
    json.position stage.position
    json.is_won stage.is_won
    json.is_lost stage.is_lost
  end
end
json.benefit_types do
  json.array! @benefit_types do |bt|
    json.id bt.id
    json.name bt.name
    json.position bt.position
  end
end
json.priorities do
  json.array! @priorities do |p|
    json.id p.id
    json.name p.name
    json.weight p.weight
    json.position p.position
  end
end
json.sources @sources
