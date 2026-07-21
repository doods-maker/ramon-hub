json.payload do
  json.array! @leads, partial: 'lead', as: :lead, locals: { slim: true }
end
