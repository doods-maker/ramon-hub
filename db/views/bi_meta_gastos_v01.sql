-- Gasto diário por anúncio (Meta Ads), gravado por `rake ramon:meta:gasto`.
SELECT
  account_id,
  data,
  ad_id,
  ad_name,
  campaign_id,
  campaign_name,
  spend,
  impressions,
  clicks
FROM ramon_meta_gastos
