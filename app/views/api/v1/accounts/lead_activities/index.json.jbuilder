json.payload do
  json.array! @activities, partial: 'lead_activity', as: :activity
end
