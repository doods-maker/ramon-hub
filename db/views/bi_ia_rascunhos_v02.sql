-- v02: content_attributes e gravado como STRING JSON (store coder: JSON) -> (col #>> '{}')::jsonb.
-- Notas-rascunho do Assistente e o que o humano fez com elas (metrica D8 / decisao D7).
WITH notas AS (
  SELECT m.id AS nota_id, m.account_id, m.conversation_id, m.inbox_id, m.created_at AS criado_em
  FROM messages m
  WHERE m.private = true AND m.sender_type = 'Captain::Assistant'
    AND m.content LIKE 'RASCUNHO (revisar antes de enviar):%'
),
enviadas AS (
  SELECT DISTINCT ON (nota_id)
         ((m.content_attributes #>> '{}')::jsonb->'ramon_rascunho_ia'->>'nota_id')::bigint AS nota_id,
         m.id AS mensagem_id, m.created_at AS enviada_em,
         (m.content_attributes #>> '{}')::jsonb->'ramon_rascunho_ia'->>'desfecho' AS desfecho
  FROM messages m
  WHERE (m.content_attributes #>> '{}')::jsonb ? 'ramon_rascunho_ia'
  ORDER BY nota_id, m.created_at
)
SELECT n.nota_id, n.account_id, n.conversation_id, n.inbox_id, n.criado_em,
       COALESCE(e.desfecho,
                CASE WHEN EXISTS (SELECT 1 FROM messages i WHERE i.conversation_id = n.conversation_id
                                    AND i.message_type = 0 AND i.created_at > n.criado_em)
                     THEN 'sem_resposta' ELSE 'pendente' END) AS desfecho,
       e.mensagem_id,
       ROUND(EXTRACT(EPOCH FROM (e.enviada_em - n.criado_em)) / 60.0, 1) AS minutos_ate_envio
FROM notas n
LEFT JOIN enviadas e ON e.nota_id = n.nota_id
