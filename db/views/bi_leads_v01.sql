-- Regra canônica de "lead de funil" (espelho de Lead.funil — lead.rb:27-36).
-- Mudou a regra no modelo → mude AQUI na mesma PR (decisão 13 da spec 13/08).
SELECT
  l.id,
  l.account_id,
  l.contact_id,
  l.created_at,
  l.won_at,
  l.lost_at,
  l.lost_reason,
  l.value,
  l.benefit_monthly_value,
  l.source,
  COALESCE(l.channel, 'outro') AS channel,
  l.thesis_id,
  t.name  AS thesis_name,
  s.id    AS stage_id,
  s.name  AS stage_name,
  s.probability AS stage_probability,
  s.is_won,
  s.is_lost,
  (l.custom_attributes #>> '{utm,utm_campaign}') AS utm_campaign,
  (l.custom_attributes #>> '{valor_estimado,origem}') AS valor_origem
FROM leads l
LEFT JOIN theses t ON t.id = l.thesis_id
LEFT JOIN lead_stages s ON s.id = l.lead_stage_id
WHERE l.source IS DISTINCT FROM 'calculo-advbox'
