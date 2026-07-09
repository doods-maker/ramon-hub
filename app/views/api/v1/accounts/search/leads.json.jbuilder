json.payload do
  json.leads do
    json.array! @result[:leads] do |lead|
      json.partial! 'lead', formats: [:json], lead: lead
    end
  end
end
