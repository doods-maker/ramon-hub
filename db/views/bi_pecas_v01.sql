-- Peças de conteúdo do Instagram com o desempenho lido da Meta (alcance etc.; nulo enquanto o puxador está desligado).
SELECT
  id,
  account_id,
  tipo,
  tese,
  gancho,
  status,
  COALESCE(agendado_para, updated_at) AS publicado_em,
  permalink,
  alcance,
  salvamentos,
  compartilhamentos,
  curtidas,
  comentarios,
  metricas_em
FROM ramon_pecas
WHERE status = 'publicado'
