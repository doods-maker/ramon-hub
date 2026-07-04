json.id lead_triage.id
json.status lead_triage.status
json.viability lead_triage.viability
json.result lead_triage.result
json.error_message lead_triage.error_message
json.created_at lead_triage.created_at
json.finished_at lead_triage.finished_at
if lead_triage.triage_agent
  json.triage_agent do
    json.id lead_triage.triage_agent.id
    json.name lead_triage.triage_agent.name
  end
end
