funil_acoes = FunilAcao.chips(@leads.map(&:id))
json.payload do
  json.array! @leads, partial: 'lead', as: :lead, locals: { slim: true, funil_acoes: funil_acoes }
end
