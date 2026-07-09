json.contact do
  json.id @contact.id
  json.name @contact.name
  json.phone_number @contact.phone_number
  json.email @contact.email
  json.cpf @contact.cpf
  json.data_nascimento @contact.data_nascimento
  json.sexo @contact.sexo
end

json.leads @leads do |lead|
  json.id lead.id
  json.name lead.name
  json.created_at lead.created_at
  json.won_at lead.won_at
  json.lost_at lead.lost_at
  json.is_won lead.lead_stage&.is_won
  json.is_lost lead.lead_stage&.is_lost
  json.stage_name lead.lead_stage&.name
  json.stage_color lead.lead_stage&.color
  json.benefit_type_name lead.benefit_type&.name
  json.thesis_name lead.thesis&.name
  json.value lead.value
  json.lost_reason lead.lost_reason
  json.dcb_em lead.dcb_em
  json.benefit_monthly_value lead.benefit_monthly_value
  json.prescription lead.prescription
  json.conversation_id lead.conversation_id
end

json.marcos @marcos do |marco|
  json.key marco[:key]
  json.sexo marco[:sexo]
  json.idade marco[:idade]
  json.data marco[:data]
  json.atingido marco[:atingido]
end
