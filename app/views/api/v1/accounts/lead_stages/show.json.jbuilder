json.id @stage.id
json.name @stage.name
json.color @stage.color
json.label @stage.label
json.position @stage.position
json.is_won @stage.is_won
json.is_lost @stage.is_lost
# protegida: o código acha a etapa pelo label (não pode ser removida)
json.automacao @stage.automacao?
json.nome_cliente @stage.nome_cliente
json.probability @stage.probability
json.stalled_after_days @stage.stalled_after_days
