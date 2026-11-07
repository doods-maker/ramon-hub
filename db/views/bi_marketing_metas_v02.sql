-- Metas mensais vindas do modelo.mjs (mensal.json subido na aba Custos e metas).
-- v02: só as ligadas ("Usar metas" no hub); desligadas somem dos cartões de realizado × meta.
SELECT account_id, mes, metrica, valor
FROM ramon_marketing_metas
WHERE ativa
