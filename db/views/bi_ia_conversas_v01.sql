-- Tempo ate a 1a resposta com/sem IA + contagens por conversa (metrica D8).
WITH base AS (
  SELECT c.id AS conversation_id, c.account_id, c.inbox_id,
         MIN(CASE WHEN m.message_type = 0 THEN m.created_at END) AS iniciada_em,
         MIN(CASE WHEN m.message_type = 1 AND m.private = false THEN m.created_at END) AS primeira_resposta_em,
         COUNT(*) FILTER (WHERE (m.content_attributes::jsonb) ? 'ramon_piloto') AS pilotos_enviados,
         COUNT(*) FILTER (WHERE m.private = true AND m.sender_type = 'Captain::Assistant'
                            AND m.content LIKE 'RASCUNHO (revisar antes de enviar):%') AS rascunhos,
         COUNT(*) FILTER (WHERE (m.content_attributes::jsonb) ? 'ramon_rascunho_ia') AS rascunhos_usados
  FROM conversations c
  JOIN messages m ON m.conversation_id = c.id
  GROUP BY c.id, c.account_id, c.inbox_id
)
SELECT b.conversation_id, b.account_id, b.inbox_id, b.iniciada_em, b.primeira_resposta_em,
       ROUND(EXTRACT(EPOCH FROM (b.primeira_resposta_em - b.iniciada_em)) / 60.0, 1) AS minutos_primeira_resposta,
       (b.pilotos_enviados + b.rascunhos_usados) > 0 AS com_ia,
       b.pilotos_enviados, b.rascunhos, b.rascunhos_usados,
       (SELECT COUNT(*) FROM reporting_events r
         WHERE r.conversation_id = b.conversation_id AND r.name = 'conversation_bot_handoff') AS handoffs
FROM base b
WHERE b.iniciada_em IS NOT NULL;
