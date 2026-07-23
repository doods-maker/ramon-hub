json.reviewed_count @reviewed_count.to_i
json.payload do
  json.array! @copilot_suggestions, partial: 'copilot_suggestion', as: :suggestion
end
