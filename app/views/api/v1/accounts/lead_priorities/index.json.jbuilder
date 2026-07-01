json.array! @records do |p|
  json.id p.id
  json.name p.name
  json.weight p.weight
  json.position p.position
end
