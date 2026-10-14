-- Roteiro da tese por lead (spec 2026-10-13 §3.9, F4). Fonte: leads.custom_attributes->'roteiro' (motor F1; 'passo' =
-- próximo a perguntar) e o carimbo copiloto_limite da conversa (F3). Sem o texto das respostas (spec §5): só quantas,
-- quando, o desfecho, o motivo (texto da saída configurada pelo admin) e o passo que decidiu.
SELECT l.id AS lead_id,
       l.account_id,
       l.conversation_id,
       l.created_at AS lead_criado_em,
       l.custom_attributes ? 'roteiro' AS em_roteiro,
       (l.custom_attributes #>> '{roteiro,tese_id}')::bigint AS thesis_id,
       t.name AS thesis_name,
       l.custom_attributes #>> '{roteiro,passo}' AS passo_atual,
       l.custom_attributes #>> '{roteiro,desfecho}' AS desfecho,
       l.custom_attributes #>> '{roteiro,motivo}' AS motivo,
       l.custom_attributes #>> '{roteiro,decisivo}' AS passo_decisivo,
       COALESCE((l.custom_attributes #>> '{roteiro,aguarda_equipe}')::boolean, false) AS aguarda_equipe,
       r.respondidos,
       r.iniciado_em,
       r.ultima_resposta_em,
       c.custom_attributes ->> 'copiloto_modo' AS modo,
       c.custom_attributes #>> '{copiloto_limite,limite}' AS limite_atingido,
       (c.custom_attributes #>> '{copiloto_limite,em}')::timestamptz AS limite_em
FROM leads l
LEFT JOIN theses t ON t.id = (l.custom_attributes #>> '{roteiro,tese_id}')::bigint
LEFT JOIN conversations c ON c.id = l.conversation_id
CROSS JOIN LATERAL (
  SELECT COUNT(*) AS respondidos,
         MIN((e.v ->> 'em')::timestamptz) AS iniciado_em,
         MAX((e.v ->> 'em')::timestamptz) AS ultima_resposta_em
  FROM jsonb_each(COALESCE(l.custom_attributes #> '{roteiro,respostas}', '{}'::jsonb)) AS e(chave, v)
) r
WHERE l.custom_attributes ? 'roteiro' OR c.custom_attributes ? 'copiloto_limite'
