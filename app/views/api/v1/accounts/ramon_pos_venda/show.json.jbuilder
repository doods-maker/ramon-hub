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
      # prescrição: o front calcula com o mesmo helper do painel (prescriptionInfo)
      json.dcb_em lead.dcb_em
      json.benefit_monthly_value lead.benefit_monthly_value&.to_f
      # o que falta (mesma fonte do checklist do painel) + nome pro rascunho "Cobrar pendentes"
      json.lead_name lead.name
      json.docs_pendentes(lead.doc_checklist.reject { |item| item[:status] == 'recebido' })
    end
  end
end

json.concluidos_total @dados[:concluidos_total]

# Ganhos sem tese (sem checklist → nunca contrato limpo): pedem "defina a tese".
json.sem_tese @dados[:sem_tese] do |lead|
  json.id lead.id
  json.name lead.contact&.name || lead.name
  json.dias ((Time.zone.now - lead.won_at) / 1.day).floor
  json.conversation_id lead.conversation_id
end
