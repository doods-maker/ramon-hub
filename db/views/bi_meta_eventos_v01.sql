-- Rastro dos avisos de conversão enviados à Meta (um por lead e evento).
SELECT
  account_id,
  lead_id,
  evento,
  status,
  erro,
  ocorrido_em,
  enviado_em
FROM ramon_meta_eventos
