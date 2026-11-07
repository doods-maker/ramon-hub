-- Custos de marketing lançados à mão (aba Custos e metas). Sem tese = custo geral, rateado no Metabase.
SELECT
  c.id,
  c.account_id,
  c.data,
  c.valor,
  c.categoria,
  c.thesis_id,
  t.name AS thesis_name,
  c.observacao
FROM ramon_marketing_custos c
LEFT JOIN theses t ON t.id = c.thesis_id
