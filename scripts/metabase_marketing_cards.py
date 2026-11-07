#!/usr/bin/env python3
"""Cria/atualiza o dashboard "Marketing" do Metabase (aba Tráfego da área Marketing no hub).

Spec: docs/superpowers/specs/2026-11-07-marketing-trafego-design.md. Três conferências (Meta × hub,
custo descendo o funil, retorno), CAC mídia e completo, realizado × meta e desempenho das peças.
Views: bi_leads (v03), bi_stage_transitions, bi_meta_gastos (v02), bi_marketing_custos,
bi_marketing_metas, bi_pecas. Reaproveita api/ensure_cards do script do bloco Meta Ads.

Regras dos números (conferir com o modelo.mjs):
- "Online" = canal meta_ads ou landing_page (o CAC do modelo mede só a operação online).
- Funil por tese = coorte do mês de entrada do lead; etapa alcançada = maior posição já visitada.
- Gasto do anúncio vai para as teses dos leads que ele trouxe no mês (proporção); sem lead = "Sem lead".
- Custo sem tese é rateado entre as teses pela proporção de leads online do mês.
- CAC mídia = gasto em anúncio / contratos online; CAC completo = (anúncio + custos lançados) / contratos online.

Uso (credencial NUNCA no repo — vem do ambiente):
  METABASE_URL=https://bi... METABASE_ADMIN_KEY=... python scripts/metabase_marketing_cards.py [--apply]
Sem --apply só mostra o que faria. No fim imprime o id do dashboard → RAMON_METABASE_MARKETING_ID.
"""
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from metabase_bi_meta_cards import ACCOUNT_ID, COLLECTION_ID, api, ensure_cards  # noqa: E402

DASHBOARD_NOME = "Marketing"
A = ACCOUNT_ID
ONLINE = "('meta_ads', 'landing_page')"
TZ = "'America/Sao_Paulo'"
AGORA = f"(now() AT TIME ZONE {TZ})"


def mes(col):
    """Mês local de uma coluna timestamp (UTC no banco)."""
    return f"date_trunc('month', {col} AT TIME ZONE 'UTC' AT TIME ZONE {TZ})::date"


# Leads do funil com tese, mês de entrada e a maior etapa já alcançada (perdido não conta).
LEADS = f"""lead AS (
  SELECT b.id, b.meta_ad_id, COALESCE(b.thesis_name, 'Sem tese') AS tese, b.won_at, b.value, b.channel,
         {mes('b.created_at')} AS mes
  FROM bi_leads b WHERE b.account_id = {A}
), alc AS (
  SELECT b.id, MAX(s.position) AS max_pos
  FROM bi_leads b
  LEFT JOIN bi_stage_transitions st ON st.lead_id = b.id
  JOIN lead_stages s ON s.account_id = b.account_id AND NOT s.is_lost AND s.name IN (st.to_value, b.stage_name)
  WHERE b.account_id = {A}
  GROUP BY b.id
), pos AS (
  SELECT MAX(position) FILTER (WHERE label = 'fase-qualificacao') AS q,
         MAX(position) FILTER (WHERE label = 'fase-reuniao-agendada') AS r
  FROM lead_stages WHERE account_id = {A}
)"""

# Realizado mês a mês com as mesmas métricas do mensal.json (Ramon::MetasDoModelo::METRICAS).
REALIZADO = f"""midia AS (
  SELECT date_trunc('month', data)::date AS mes, SUM(spend) AS v FROM bi_meta_gastos WHERE account_id = {A} GROUP BY 1
), outros AS (
  SELECT date_trunc('month', data)::date AS mes, SUM(valor) AS v FROM bi_marketing_custos WHERE account_id = {A} GROUP BY 1
), contr AS (
  SELECT {mes('won_at')} AS mes, COUNT(*) AS v FROM bi_leads
  WHERE account_id = {A} AND won_at IS NOT NULL AND channel IN {ONLINE} GROUP BY 1
), reun AS (
  SELECT {mes('st.created_at')} AS mes, s.label, COUNT(DISTINCT st.lead_id) AS v
  FROM bi_stage_transitions st
  JOIN lead_stages s ON s.account_id = st.account_id AND s.name = st.to_value
  WHERE st.account_id = {A} AND s.label IN ('fase-reuniao-agendada', 'fase-reuniao-realizada')
  GROUP BY 1, 2
), meses AS (
  SELECT DISTINCT mes FROM bi_marketing_metas WHERE account_id = {A}
), realizado AS (
  SELECT m.mes, x.metrica, x.valor
  FROM meses m
  LEFT JOIN midia ON midia.mes = m.mes
  LEFT JOIN outros ON outros.mes = m.mes
  LEFT JOIN contr ON contr.mes = m.mes
  CROSS JOIN LATERAL (VALUES
    ('contratos', COALESCE(contr.v, 0)),
    ('reunioes_agendadas', (SELECT COALESCE(SUM(v), 0) FROM reun WHERE reun.mes = m.mes AND label = 'fase-reuniao-agendada')),
    ('reunioes_realizadas', (SELECT COALESCE(SUM(v), 0) FROM reun WHERE reun.mes = m.mes AND label = 'fase-reuniao-realizada')),
    ('gasto_anuncio', COALESCE(midia.v, 0)),
    ('custo_area', COALESCE(midia.v, 0) + COALESCE(outros.v, 0)),
    ('cac', (COALESCE(midia.v, 0) + COALESCE(outros.v, 0)) / NULLIF(contr.v, 0))
  ) AS x(metrica, valor)
  WHERE m.mes <= date_trunc('month', {AGORA})::date
)"""

CARDS = {
    # 1. Meta × hub: o que a Meta diz ter gerado contra o que chegou no hub, por campanha.
    "Mkt: Meta × hub por campanha (30d)": dict(display="table", sql=f"""
WITH g AS (
  SELECT campaign_id, MAX(campaign_name) AS campanha, SUM(spend) AS gasto,
         SUM(conversas) AS conversas_meta, SUM(leads_meta) AS leads_meta
  FROM bi_meta_gastos WHERE account_id = {A} AND data >= current_date - 30
  GROUP BY campaign_id
), ad AS (
  SELECT DISTINCT ad_id, campaign_id FROM bi_meta_gastos WHERE account_id = {A}
), h AS (
  SELECT ad.campaign_id, COUNT(*) AS leads_hub
  FROM bi_leads b JOIN ad ON ad.ad_id = b.meta_ad_id
  WHERE b.account_id = {A} AND b.created_at > now() - interval '30 days'
  GROUP BY ad.campaign_id
)
SELECT COALESCE(g.campanha, g.campaign_id) AS campanha, ROUND(g.gasto, 2) AS gasto,
       g.conversas_meta + g.leads_meta AS resultados_meta, COALESCE(h.leads_hub, 0) AS leads_hub,
       COALESCE(h.leads_hub, 0) - (g.conversas_meta + g.leads_meta) AS diferenca,
       ROUND(g.gasto / NULLIF(h.leads_hub, 0), 2) AS custo_por_lead_hub
FROM g LEFT JOIN h ON h.campaign_id = g.campaign_id
ORDER BY gasto DESC"""),

    # 2. Custo descendo o funil por tese, mês atual e anterior (coorte de entrada).
    "Mkt: custo por etapa do funil por tese (mês e anterior)": dict(display="table", sql=f"""
WITH {LEADS}, meses AS (
  SELECT (date_trunc('month', {AGORA}) - interval '1 month')::date AS mes
  UNION ALL SELECT date_trunc('month', {AGORA})::date
), funil AS (
  SELECT l.mes, l.tese, COUNT(*) AS leads,
         COUNT(*) FILTER (WHERE a.max_pos >= pos.q) AS qualificados,
         COUNT(*) FILTER (WHERE a.max_pos >= pos.r) AS reunioes,
         COUNT(*) FILTER (WHERE l.won_at IS NOT NULL) AS contratos
  FROM lead l LEFT JOIN alc a ON a.id = l.id CROSS JOIN pos
  WHERE l.channel IN {ONLINE} AND l.mes IN (SELECT mes FROM meses)
  GROUP BY 1, 2
), parte AS (
  SELECT mes, meta_ad_id AS ad_id, tese,
         COUNT(*)::numeric / SUM(COUNT(*)) OVER (PARTITION BY mes, meta_ad_id) AS parte
  FROM lead WHERE meta_ad_id IS NOT NULL GROUP BY 1, 2, 3
), gasto_ad AS (
  SELECT date_trunc('month', data)::date AS mes, ad_id, SUM(spend) AS gasto
  FROM bi_meta_gastos WHERE account_id = {A} GROUP BY 1, 2
), midia AS (
  SELECT g.mes, COALESCE(p.tese, 'Sem lead') AS tese, SUM(g.gasto * COALESCE(p.parte, 1)) AS midia
  FROM gasto_ad g LEFT JOIN parte p ON p.mes = g.mes AND p.ad_id = g.ad_id
  WHERE g.mes IN (SELECT mes FROM meses) GROUP BY 1, 2
), custo_tese AS (
  SELECT date_trunc('month', data)::date AS mes, thesis_name AS tese, SUM(valor) AS v
  FROM bi_marketing_custos WHERE account_id = {A} AND thesis_name IS NOT NULL GROUP BY 1, 2
), custo_geral AS (
  SELECT date_trunc('month', data)::date AS mes, SUM(valor) AS v
  FROM bi_marketing_custos WHERE account_id = {A} AND thesis_name IS NULL GROUP BY 1
), base AS (
  SELECT COALESCE(f.mes, m.mes) AS mes, COALESCE(f.tese, m.tese) AS tese,
         COALESCE(f.leads, 0) AS leads, COALESCE(f.qualificados, 0) AS qualificados,
         COALESCE(f.reunioes, 0) AS reunioes, COALESCE(f.contratos, 0) AS contratos, COALESCE(m.midia, 0) AS midia
  FROM funil f FULL JOIN midia m ON m.mes = f.mes AND m.tese = f.tese
), custo AS (
  SELECT b.*, b.midia + COALESCE(ct.v, 0)
              + COALESCE(cg.v, 0) * b.leads / NULLIF(SUM(b.leads) OVER (PARTITION BY b.mes), 0) AS completo
  FROM base b
  LEFT JOIN custo_tese ct ON ct.mes = b.mes AND ct.tese = b.tese
  LEFT JOIN custo_geral cg ON cg.mes = b.mes
)
SELECT to_char(mes, 'MM/YYYY') AS mes, tese, leads, qualificados, reunioes, contratos,
       ROUND(midia, 2) AS gasto_anuncio, ROUND(completo, 2) AS custo_completo,
       ROUND(completo / NULLIF(leads, 0), 2) AS por_lead,
       ROUND(completo / NULLIF(qualificados, 0), 2) AS por_qualificado,
       ROUND(completo / NULLIF(reunioes, 0), 2) AS por_reuniao,
       ROUND(midia / NULLIF(contratos, 0), 2) AS cac_midia,
       ROUND(completo / NULLIF(contratos, 0), 2) AS cac_completo
FROM custo
ORDER BY custo.mes DESC, completo DESC NULLS LAST"""),

    # 3. Retorno: custo × honorário dos contratos online fechados no mês, com os dois CACs.
    "Mkt: retorno e CAC por mês (12m)": dict(display="table", sql=f"""
WITH meses AS (
  SELECT generate_series(date_trunc('month', {AGORA}) - interval '11 months', date_trunc('month', {AGORA}), interval '1 month')::date AS mes
), midia AS (
  SELECT date_trunc('month', data)::date AS mes, SUM(spend) AS v FROM bi_meta_gastos WHERE account_id = {A} GROUP BY 1
), outros AS (
  SELECT date_trunc('month', data)::date AS mes, SUM(valor) AS v FROM bi_marketing_custos WHERE account_id = {A} GROUP BY 1
), ganho AS (
  SELECT {mes('won_at')} AS mes, COUNT(*) AS contratos, SUM(value) AS honorario
  FROM bi_leads WHERE account_id = {A} AND won_at IS NOT NULL AND channel IN {ONLINE} GROUP BY 1
)
SELECT to_char(m.mes, 'MM/YYYY') AS mes, ROUND(COALESCE(midia.v, 0), 2) AS gasto_anuncio,
       ROUND(COALESCE(outros.v, 0), 2) AS custos_lancados,
       COALESCE(ganho.contratos, 0) AS contratos, ROUND(COALESCE(ganho.honorario, 0), 2) AS honorario,
       ROUND(midia.v / NULLIF(ganho.contratos, 0), 2) AS cac_midia,
       ROUND((COALESCE(midia.v, 0) + COALESCE(outros.v, 0)) / NULLIF(ganho.contratos, 0), 2) AS cac_completo,
       ROUND(ganho.honorario / NULLIF(COALESCE(midia.v, 0) + COALESCE(outros.v, 0), 0), 2) AS retorno_por_real
FROM meses m
LEFT JOIN midia ON midia.mes = m.mes
LEFT JOIN outros ON outros.mes = m.mes
LEFT JOIN ganho ON ganho.mes = m.mes
ORDER BY m.mes DESC"""),

    # 4. Realizado × meta do modelo, mês a mês.
    "Mkt: realizado × meta (mês a mês)": dict(display="table", sql=f"""
WITH {REALIZADO}
SELECT to_char(r.mes, 'MM/YYYY') AS mes, r.metrica, ROUND(mt.valor, 2) AS meta, ROUND(r.valor, 2) AS realizado,
       ROUND(100 * r.valor / NULLIF(mt.valor, 0)) AS pct_da_meta
FROM realizado r
JOIN bi_marketing_metas mt ON mt.account_id = {A} AND mt.mes = r.mes AND mt.metrica = r.metrica
ORDER BY r.mes DESC, r.metrica"""),

    # 5. Realizado × meta acumulado no ano (CAC = custo somado / contratos somados).
    "Mkt: realizado × meta (acumulado do ano)": dict(display="table", sql=f"""
WITH {REALIZADO}, ano AS (
  SELECT r.metrica, SUM(mt.valor) AS meta, SUM(r.valor) AS realizado
  FROM realizado r
  JOIN bi_marketing_metas mt ON mt.account_id = {A} AND mt.mes = r.mes AND mt.metrica = r.metrica
  WHERE date_trunc('year', r.mes) = date_trunc('year', {AGORA})
  GROUP BY r.metrica
)
SELECT metrica, ROUND(meta, 2) AS meta, ROUND(realizado, 2) AS realizado, ROUND(100 * realizado / NULLIF(meta, 0)) AS pct_da_meta
FROM ano WHERE metrica <> 'cac'
UNION ALL
SELECT 'cac',
       ROUND((SELECT meta FROM ano WHERE metrica = 'custo_area') / NULLIF((SELECT meta FROM ano WHERE metrica = 'contratos'), 0), 2),
       ROUND((SELECT realizado FROM ano WHERE metrica = 'custo_area') / NULLIF((SELECT realizado FROM ano WHERE metrica = 'contratos'), 0), 2),
       NULL"""),

    # 6. Conteúdo: peças publicadas, alcance e leads que chegaram pelo Instagram, por semana.
    "Mkt: peças × alcance × leads do Instagram (12 semanas)": dict(display="table", sql=f"""
WITH semanas AS (
  SELECT generate_series(date_trunc('week', {AGORA}) - interval '11 weeks', date_trunc('week', {AGORA}), interval '1 week')::date AS semana
), p AS (
  SELECT date_trunc('week', publicado_em AT TIME ZONE 'UTC' AT TIME ZONE {TZ})::date AS semana, COUNT(*) AS pecas,
         SUM(alcance) AS alcance, SUM(salvamentos) AS salvamentos, SUM(compartilhamentos) AS compartilhamentos
  FROM bi_pecas WHERE account_id = {A} GROUP BY 1
), l AS (
  SELECT date_trunc('week', created_at AT TIME ZONE 'UTC' AT TIME ZONE {TZ})::date AS semana, COUNT(*) AS leads_instagram
  FROM bi_leads WHERE account_id = {A} AND channel = 'instagram' GROUP BY 1
)
SELECT to_char(s.semana, 'DD/MM') AS semana, COALESCE(p.pecas, 0) AS pecas, p.alcance, p.salvamentos, p.compartilhamentos,
       COALESCE(l.leads_instagram, 0) AS leads_instagram
FROM semanas s LEFT JOIN p ON p.semana = s.semana LEFT JOIN l ON l.semana = s.semana
ORDER BY s.semana DESC"""),
}


def ensure_dashboard(apply_):
    """Devolve o id do dashboard Marketing (cria se faltar) com o embed assinado ligado."""
    achado = next((d for d in api("GET", "/dashboard?f=all") if d["name"] == DASHBOARD_NOME and not d.get("archived")), None)
    if achado is None:
        print(f"[CRIAR DASHBOARD] {DASHBOARD_NOME}")
        if not apply_:
            return None
        achado = api("POST", "/dashboard", {"name": DASHBOARD_NOME, "collection_id": COLLECTION_ID})
    if apply_ and not achado.get("enable_embedding"):
        api("PUT", f"/dashboard/{achado['id']}", {"enable_embedding": True})
        print("[EMBED LIGADO]")
    return achado["id"]


def ensure_dashcards(dash_id, ids, apply_):
    """Um cartão por linha, largura toda, na ordem de CARDS; só acrescenta o que falta."""
    dash = api("GET", f"/dashboard/{dash_id}")
    dashcards = dash["dashcards"]
    presentes = {dc["card_id"] for dc in dashcards if dc.get("card_id")}
    linha = max((dc["row"] + dc["size_y"] for dc in dashcards), default=0)
    novos = []
    for i, nome in enumerate(CARDS):
        cid = ids.get(nome)
        if cid is None or cid in presentes:
            continue
        novos.append({"id": -(i + 1), "card_id": cid, "row": linha, "col": 0, "size_x": 24, "size_y": 8,
                      "parameter_mappings": [], "visualization_settings": {}})
        linha += 8
    if not novos:
        print("[DASHBOARD JA OK]")
        return
    print(f"[DASHBOARD] acrescentar {len(novos)} cartão(ões)")
    if apply_:
        keep = [{k: dc[k] for k in ("id", "card_id", "row", "col", "size_x", "size_y", "parameter_mappings",
                                   "visualization_settings", "dashboard_tab_id") if k in dc} for dc in dashcards]
        api("PUT", f"/dashboard/{dash_id}", {"dashcards": keep + novos})


def main():
    apply_ = "--apply" in sys.argv
    if not os.environ.get("METABASE_URL") or not os.environ.get("METABASE_ADMIN_KEY"):
        sys.exit("faltam METABASE_URL e/ou METABASE_ADMIN_KEY no ambiente.")
    dash_id = ensure_dashboard(apply_)
    ids = ensure_cards(CARDS, apply_)
    if dash_id is not None:
        ensure_dashcards(dash_id, ids, apply_)
        print(f"RAMON_METABASE_MARKETING_ID={dash_id}")


if __name__ == "__main__":
    main()
