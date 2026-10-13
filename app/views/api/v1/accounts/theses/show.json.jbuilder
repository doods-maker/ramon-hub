json.id @thesis.id
json.name @thesis.name
json.description @thesis.description
json.area @thesis.area
json.active @thesis.active
json.position @thesis.position
json.honorario_percentual @thesis.honorario_percentual
json.honorario_n_mensalidades @thesis.honorario_n_mensalidades
json.honorario_minimo_qtd @thesis.honorario_minimo_qtd
json.honorario_minimo_base @thesis.honorario_minimo_base
json.honorario_na_tabela @thesis.honorario_na_tabela

json.items @thesis.thesis_items do |item|
  json.id item.id
  json.section item.section
  json.title item.title
  json.content item.content
  json.position item.position
end
