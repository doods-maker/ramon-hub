-- Transições de etapa dos leads de funil (fonte: lead_activities stage_changed;
-- etapa por NOME — renomear etapa mantém o nome antigo no histórico).
SELECT
  la.lead_id,
  b.account_id,
  la.from_value,
  la.to_value,
  la.created_at
FROM lead_activities la
JOIN bi_leads b ON b.id = la.lead_id
WHERE la.kind = 'stage_changed'
