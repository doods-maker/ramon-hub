%i[pendentes concluidos].each do |grupo|
  json.set! grupo do
    json.array! @dados[grupo] do |lead|
      docs = lead.docs_counts
      json.id lead.id
      json.name lead.contact&.name || lead.name
      json.won_at lead.won_at
      json.dias ((Time.zone.now - lead.won_at) / 1.day).floor
      json.docs_received docs[:received]
      json.docs_total docs[:total]
      json.conversation_id lead.conversation_id
      json.drive_concluido lead.custom_attributes&.dig('drive', 'concluido_em').present?
    end
  end
end
