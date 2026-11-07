json.stages do
  json.array! @stages do |stage|
    json.id stage.id
    json.name stage.name
    # label fixo do seed (fase-reuniao-agendada…): o painel decide por ele, não pelo nome editável
    json.label stage.label
    json.color stage.color
    json.position stage.position
    json.is_won stage.is_won
    json.is_lost stage.is_lost
    # protegida: o código acha a etapa pelo label (não pode ser removida)
    json.automacao stage.automacao?
    json.nome_cliente stage.nome_cliente
    json.probability stage.probability
    json.stalled_after_days stage.stalled_after_days
    # Etapa Documentos: assistente próprio da etapa (nil = o da caixa)
    json.captain_assistant_id stage.captain_assistant_id
  end
end
json.lost_reasons do
  json.array! @lost_reasons do |reason|
    json.id reason.id
    json.name reason.name
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
json.channels @channels
# chave RAMON_ETAPA_DOCUMENTOS: o funil só pede o motivo de pular Documentos com ela ligada
json.etapa_documentos Ramon::EtapaDeGanho.documentos_ligado?
json.sources @sources
