json.array! @items do |item|
  json.id item.id
  json.thesis_id item.thesis_id
  json.section item.section
  json.title item.title
  json.content item.content
  json.position item.position
end
