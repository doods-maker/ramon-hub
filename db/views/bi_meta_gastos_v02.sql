-- Gasto diário por anúncio (Meta Ads): API (cron/rake) ou CSV do Gerenciador (origem).
-- v02: conjunto, objetivo e os resultados que a própria Meta conta (conferência Meta × hub).
SELECT
  account_id,
  data,
  ad_id,
  ad_name,
  campaign_id,
  campaign_name,
  spend,
  impressions,
  clicks,
  adset_id,
  adset_name,
  objetivo,
  conversas,
  leads_meta,
  origem
FROM ramon_meta_gastos
