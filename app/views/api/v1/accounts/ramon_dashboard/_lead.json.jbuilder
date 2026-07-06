json.id lead.id
json.name lead.name
json.stage_name lead.lead_stage&.name
json.days_in_stage lead.stage_entered_at ? ((Time.current - lead.stage_entered_at) / 1.day).floor : 0
json.source lead.source
json.conversation_id lead.conversation_id
json.contact_phone lead.contact&.phone_number
json.dcb_em lead.dcb_em
json.benefit_monthly_value lead.benefit_monthly_value
