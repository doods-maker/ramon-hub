json.resumo do
  json.total_24h @resumo[:total_24h]
  json.erros_24h @resumo[:erros_24h]
  json.por_tool @resumo[:por_tool]
  json.tools @resumo[:tools]
end

json.items @tool_runs do |run|
  json.id run.id
  json.tool_name run.tool_name
  json.status run.status
  json.duration_ms run.duration_ms
  json.params run.params
  json.resultado run.resultado
  json.lead_id run.lead_id
  json.conversation_id run.conversation_id
  json.assistant_id run.assistant_id
  json.created_at run.created_at
end
