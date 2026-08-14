json.id lead.id
json.name lead.name
json.lead_stage_id lead.lead_stage_id
json.benefit_type_id lead.benefit_type_id
json.lead_priority_id lead.lead_priority_id
json.thesis_id lead.thesis_id
json.contact_id lead.contact_id
json.conversation_id lead.conversation_id
json.sdr_id lead.sdr_id
json.closer_id lead.closer_id
json.position lead.position
json.lost_reason lead.lost_reason
# slim = índice do Kanban: o card não lê custom_attributes (colheita/advbox/
# zapsign) e o jsonb inteiro × N leads incha o payload — a gaveta busca o show.
json.custom_attributes lead.custom_attributes unless local_assigns[:slim]
# Retomadas (cadência de follow-up): escalares presentes TAMBÉM no slim — o
# badge do card precisa deles sem carregar o jsonb inteiro.
json.follow_up_count lead.custom_attributes&.dig('follow_up', 'tentativas').to_i
json.follow_up_last_at lead.custom_attributes&.dig('follow_up', 'ultima_em')
# Checklist de documentos: escalares presentes TAMBÉM no slim — o badge do
# card precisa deles sem carregar o jsonb inteiro.
docs = lead.docs_counts
json.docs_received docs[:received]
json.docs_total docs[:total]
# SLA de 1ª resposta (slim TAMBÉM: o timer do card precisa dele no índice).
if (sla = lead.sla_info)
  json.sla do
    json.due_at sla[:due_at]
    json.replied_at sla[:replied_at]
    json.minutes sla[:minutes]
  end
else
  json.sla nil
end

json.value lead.value
json.source lead.source
json.channel lead.channel

json.stage_entered_at lead.stage_entered_at
json.won_at lead.won_at
json.lost_at lead.lost_at
json.dcb_em lead.dcb_em
json.benefit_monthly_value lead.benefit_monthly_value
json.stalled lead.stalled?
json.open_tasks_count lead.lead_tasks.open_tasks.size
next_task = lead.next_open_task
json.next_task_due_at next_task&.due_at
json.next_task_title next_task&.title

json.stage_name lead.lead_stage&.name
json.stage_color lead.lead_stage&.color
json.benefit_type_name lead.benefit_type&.name
json.lead_priority_name lead.lead_priority&.name
json.thesis_name lead.thesis&.name
json.sdr_name lead.sdr&.name
json.closer_name lead.closer&.name

json.contact_name lead.contact&.name
json.contact_phone lead.contact&.phone_number
json.contact_email lead.contact&.email
json.contact_cpf lead.contact&.cpf
json.contact_data_nascimento lead.contact&.data_nascimento
json.contact_sexo lead.contact&.sexo
json.contact_consent_marketing lead.contact&.custom_attributes&.dig('consent_marketing')

if lead.latest_triage
  json.latest_triage do
    json.id lead.latest_triage.id
    json.status lead.latest_triage.status
    json.viability lead.latest_triage.viability
  end
else
  json.latest_triage nil
end
