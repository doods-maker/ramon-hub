#!/usr/bin/env python3
"""Cria/atualiza o dashboard "Marketing" do Metabase (aba Tráfego da área Marketing no hub).

Spec: docs/superpowers/specs/2026-11-07-marketing-trafego-design.md. Três conferências (Meta × hub,
custo descendo o funil, retorno), CAC mídia e completo, realizado × meta e desempenho das peças.
Views: bi_leads (v03), bi_stage_transitions, bi_meta_gastos (v02), bi_marketing_custos,
bi_marketing_metas, bi_pecas. Reaproveita api/ensure_cards do script do bloco Meta Ads.

Regras dos números (conferir com o modelo.mjs):
- "Online" = canal meta_ads ou landing_page (o CAC do modelo mede só a operação online).
- Funil = coorte do mês de entrada do lead; etapa alcançada = maior posição já visitada (perdido não conta).
- Contratos = fechados no mês (won_at), igual em todos os cartões, para o CAC bater entre eles.
- Gasto do anúncio vai para as teses dos leads que ele trouxe no mês (proporção); sem lead = "Sem lead".
- Custo sem tese é rateado pela proporção de leads online do mês; mês sem leads = linha "Geral (mês sem leads)".
- CAC mídia = gasto em anúncio / contratos; CAC completo = (anúncio + custos lançados) / contratos.

Uso (credencial NUNCA no repo — vem do ambiente):
  METABASE_URL=https://bi... METABASE_ADMIN_KEY=... python scripts/metabase_marketing_cards.py [--apply]
Sem --apply só mostra o que faria. No fim imprime o id do dashboard → RAMON_METABASE_MARKETING_ID.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from metabase_bi_meta_cards import ACCOUNT_ID, COLLECTION_ID, api, ensure_cards  # noqa: E402

DASHBOARD_NOME = "Marketing"
A = ACCOUNT_ID
ONLINE = "('meta_ads', 'landing_page')"
TZ = "'America/Sao_Paulo'"
AGORA = f"(now() AT TIME ZONE {TZ})"
HOJE = f"{AGORA}::date"
MES_ATUAL = f"date_trunc('month', {AGORA})::date"
GERAL_SEM_LEADS = "'Geral (mês sem leads)'"


def local(col):
    """Timestamp UTC do banco → horário de Brasília."""
    return f"({col} AT TIME ZONE 'UTC' AT TIME ZONE {TZ})"


def mes(col):
    return f"date_trunc('month', {local(col)})::date"


# Leads com tese, mês de entrada, mês do ganho e a maior etapa já alcançada (perdido não conta);
# posições das etapas de referência; mapa anúncio → campanha.
LEADS = f"""lead AS (
  SELECT b.id, b.meta_ad_id, COALESCE(b.thesis_name, 'Sem tese') AS tese, b.won_at, b.value, b.channel,
         {mes('b.created_at')} AS mes, {mes('b.won_at')} AS mes_ganho
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
         MAX(position) FILTER (WHERE label = 'fase-reuniao-agendada') AS r,
         MAX(position) FILTER (WHERE label = 'fase-reuniao-realizada') AS rr
  FROM lead_stages WHERE account_id = {A}
), adc AS (
  SELECT DISTINCT ad_id, campaign_id FROM bi_meta_gastos WHERE account_id = {A}
), nomes AS (
  SELECT campaign_id, MAX(campaign_name) AS campanha FROM bi_meta_gastos WHERE account_id = {A} GROUP BY 1
), meses AS (
  SELECT ({MES_ATUAL} - interval '1 month')::date AS mes UNION ALL SELECT {MES_ATUAL}
)"""

# Realizado mês a mês com as mesmas métricas do mensal.json (Ramon::MetasDoModelo::METRICAS), só online.
# Reunião conta no mês em que o lead chegou pela 1ª vez na etapa (ou além): pular etapa não some com ela.
REALIZADO = f"""{LEADS}, midia AS (
  SELECT date_trunc('month', data)::date AS mes, SUM(spend) AS v FROM bi_meta_gastos WHERE account_id = {A} GROUP BY 1
), outros AS (
  SELECT date_trunc('month', data)::date AS mes, SUM(valor) AS v FROM bi_marketing_custos WHERE account_id = {A} GROUP BY 1
), contr AS (
  SELECT mes_ganho AS mes, COUNT(*) AS v FROM lead WHERE won_at IS NOT NULL AND channel IN {ONLINE} GROUP BY 1
), chegada AS (
  SELECT st.lead_id,
         MIN(st.created_at) FILTER (WHERE s.position >= pos.r) AS agendada,
         MIN(st.created_at) FILTER (WHERE s.position >= pos.rr) AS realizada
  FROM bi_stage_transitions st
  JOIN lead l ON l.id = st.lead_id AND l.channel IN {ONLINE}
  JOIN lead_stages s ON s.account_id = st.account_id AND s.name = st.to_value AND NOT s.is_lost
  CROSS JOIN pos
  WHERE st.account_id = {A}
  GROUP BY st.lead_id
), meses_meta AS (
  SELECT DISTINCT mes FROM bi_marketing_metas WHERE account_id = {A}
), realizado AS (
  SELECT m.mes, x.metrica, x.valor
  FROM meses_meta m
  LEFT JOIN midia ON midia.mes = m.mes
  LEFT JOIN outros ON outros.mes = m.mes
  LEFT JOIN contr ON contr.mes = m.mes
  CROSS JOIN LATERAL (VALUES
    ('contratos', COALESCE(contr.v, 0)),
    ('reunioes_agendadas', (SELECT COUNT(*) FROM chegada WHERE {mes('chegada.agendada')} = m.mes)),
    ('reunioes_realizadas', (SELECT COUNT(*) FROM chegada WHERE {mes('chegada.realizada')} = m.mes)),
    ('gasto_anuncio', COALESCE(midia.v, 0)),
    ('custo_area', COALESCE(midia.v, 0) + COALESCE(outros.v, 0)),
    ('cac', (COALESCE(midia.v, 0) + COALESCE(outros.v, 0)) / NULLIF(contr.v, 0))
  ) AS x(metrica, valor)
  WHERE m.mes <= {MES_ATUAL}
)"""

CARDS = {
    # 1. Meta × hub por campanha e dia: o que a Meta diz ter gerado contra o que chegou no hub.
    # FULL JOIN: lead de anúncio sem gasto no período também aparece (é a divergência que se procura).
    "Mkt: Meta × hub por campanha e dia (30d)": dict(display="table", sql=f"""
WITH g AS (
  SELECT data AS dia, campaign_id, SUM(spend) AS gasto, SUM(conversas + leads_meta) AS resultados_meta
  FROM bi_meta_gastos WHERE account_id = {A} AND data > {HOJE} - 30
  GROUP BY 1, 2
), h AS (
  SELECT {local('b.created_at')}::date AS dia, COALESCE(ad.campaign_id, 'anúncio ' || b.meta_ad_id) AS campaign_id,
         COUNT(*) AS leads_hub
  FROM bi_leads b
  LEFT JOIN (SELECT DISTINCT ad_id, campaign_id FROM bi_meta_gastos WHERE account_id = {A}) ad ON ad.ad_id = b.meta_ad_id
  WHERE b.account_id = {A} AND b.meta_ad_id IS NOT NULL AND {local('b.created_at')}::date > {HOJE} - 30
  GROUP BY 1, 2
), nomes AS (
  SELECT campaign_id, MAX(campaign_name) AS campanha FROM bi_meta_gastos WHERE account_id = {A} GROUP BY 1
)
SELECT to_char(x.dia, 'DD/MM') AS dia, COALESCE(n.campanha, x.campaign_id) AS campanha,
       ROUND(COALESCE(x.gasto, 0), 2) AS gasto, COALESCE(x.resultados_meta, 0) AS resultados_meta,
       COALESCE(x.leads_hub, 0) AS leads_hub, COALESCE(x.leads_hub, 0) - COALESCE(x.resultados_meta, 0) AS diferenca
FROM (g FULL JOIN h USING (dia, campaign_id)) x
LEFT JOIN nomes n ON n.campaign_id = x.campaign_id
ORDER BY x.dia DESC, gasto DESC"""),

    # 2a. Custo descendo o funil por tese (mês atual e anterior), com os dois CACs.
    "Mkt: custo por etapa do funil por tese (mês e anterior)": dict(display="table", sql=f"""
WITH {LEADS}, funil AS (
  SELECT l.mes, l.tese, COUNT(*) AS leads,
         COUNT(*) FILTER (WHERE a.max_pos >= pos.q) AS qualificados,
         COUNT(*) FILTER (WHERE a.max_pos >= pos.r) AS reunioes
  FROM lead l LEFT JOIN alc a ON a.id = l.id CROSS JOIN pos
  WHERE l.channel IN {ONLINE} AND l.mes IN (SELECT mes FROM meses)
  GROUP BY 1, 2
), ganho AS (
  SELECT mes_ganho AS mes, tese, COUNT(*) AS contratos
  FROM lead WHERE won_at IS NOT NULL AND channel IN {ONLINE} AND mes_ganho IN (SELECT mes FROM meses)
  GROUP BY 1, 2
), parte AS (
  SELECT mes, meta_ad_id AS ad_id, tese,
         COUNT(*)::numeric / SUM(COUNT(*)) OVER (PARTITION BY mes, meta_ad_id) AS parte
  FROM lead WHERE meta_ad_id IS NOT NULL GROUP BY 1, 2, 3
), midia AS (
  SELECT g.mes, COALESCE(p.tese, 'Sem lead') AS tese, SUM(g.gasto * COALESCE(p.parte, 1)) AS midia
  FROM (SELECT date_trunc('month', data)::date AS mes, ad_id, SUM(spend) AS gasto
        FROM bi_meta_gastos WHERE account_id = {A} GROUP BY 1, 2) g
  LEFT JOIN parte p ON p.mes = g.mes AND p.ad_id = g.ad_id
  WHERE g.mes IN (SELECT mes FROM meses) GROUP BY 1, 2
), custo_tese AS (
  SELECT date_trunc('month', data)::date AS mes, thesis_name AS tese, SUM(valor) AS v
  FROM bi_marketing_custos WHERE account_id = {A} AND thesis_name IS NOT NULL GROUP BY 1, 2
), custo_geral AS (
  SELECT date_trunc('month', data)::date AS mes, SUM(valor) AS v
  FROM bi_marketing_custos WHERE account_id = {A} AND thesis_name IS NULL GROUP BY 1
), chaves AS (
  SELECT mes, tese FROM funil UNION SELECT mes, tese FROM ganho UNION SELECT mes, tese FROM midia
  UNION SELECT mes, tese FROM custo_tese WHERE mes IN (SELECT mes FROM meses)
  UNION SELECT cg.mes, {GERAL_SEM_LEADS} FROM custo_geral cg
        WHERE cg.mes IN (SELECT mes FROM meses) AND NOT EXISTS (SELECT 1 FROM funil f WHERE f.mes = cg.mes)
), base AS (
  SELECT k.mes, k.tese, COALESCE(f.leads, 0) AS leads, COALESCE(f.qualificados, 0) AS qualificados,
         COALESCE(f.reunioes, 0) AS reunioes, COALESCE(gn.contratos, 0) AS contratos,
         COALESCE(m.midia, 0) AS midia, COALESCE(ct.v, 0) AS custo_tese
  FROM chaves k
  LEFT JOIN funil f ON f.mes = k.mes AND f.tese = k.tese
  LEFT JOIN ganho gn ON gn.mes = k.mes AND gn.tese = k.tese
  LEFT JOIN midia m ON m.mes = k.mes AND m.tese = k.tese
  LEFT JOIN custo_tese ct ON ct.mes = k.mes AND ct.tese = k.tese
), custo AS (
  SELECT b.*, b.midia + b.custo_tese + COALESCE(cg.v * CASE
           WHEN b.tese = {GERAL_SEM_LEADS} THEN 1
           ELSE b.leads::numeric / NULLIF(SUM(b.leads) OVER (PARTITION BY b.mes), 0) END, 0) AS completo
  FROM base b LEFT JOIN custo_geral cg ON cg.mes = b.mes
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

    # 2b. O mesmo funil por campanha (só leads de anúncio; custo = gasto da campanha).
    "Mkt: custo por etapa do funil por campanha (mês e anterior)": dict(display="table", sql=f"""
WITH {LEADS}, funil AS (
  SELECT l.mes, adc.campaign_id, COUNT(*) AS leads,
         COUNT(*) FILTER (WHERE a.max_pos >= pos.q) AS qualificados,
         COUNT(*) FILTER (WHERE a.max_pos >= pos.r) AS reunioes
  FROM lead l JOIN adc ON adc.ad_id = l.meta_ad_id LEFT JOIN alc a ON a.id = l.id CROSS JOIN pos
  WHERE l.mes IN (SELECT mes FROM meses)
  GROUP BY 1, 2
), ganho AS (
  SELECT l.mes_ganho AS mes, adc.campaign_id, COUNT(*) AS contratos
  FROM lead l JOIN adc ON adc.ad_id = l.meta_ad_id
  WHERE l.won_at IS NOT NULL AND l.mes_ganho IN (SELECT mes FROM meses)
  GROUP BY 1, 2
), midia AS (
  SELECT date_trunc('month', data)::date AS mes, campaign_id, SUM(spend) AS gasto
  FROM bi_meta_gastos WHERE account_id = {A} GROUP BY 1, 2
), chaves AS (
  SELECT mes, campaign_id FROM funil UNION SELECT mes, campaign_id FROM ganho
  UNION SELECT mes, campaign_id FROM midia WHERE mes IN (SELECT mes FROM meses)
)
SELECT to_char(k.mes, 'MM/YYYY') AS mes, COALESCE(n.campanha, k.campaign_id) AS campanha,
       COALESCE(f.leads, 0) AS leads, COALESCE(f.qualificados, 0) AS qualificados,
       COALESCE(f.reunioes, 0) AS reunioes, COALESCE(gn.contratos, 0) AS contratos,
       ROUND(COALESCE(m.gasto, 0), 2) AS gasto_anuncio,
       ROUND(m.gasto / NULLIF(f.leads, 0), 2) AS por_lead,
       ROUND(m.gasto / NULLIF(f.qualificados, 0), 2) AS por_qualificado,
       ROUND(m.gasto / NULLIF(f.reunioes, 0), 2) AS por_reuniao,
       ROUND(m.gasto / NULLIF(gn.contratos, 0), 2) AS cac_midia
FROM chaves k
LEFT JOIN funil f ON f.mes = k.mes AND f.campaign_id = k.campaign_id
LEFT JOIN ganho gn ON gn.mes = k.mes AND gn.campaign_id = k.campaign_id
LEFT JOIN midia m ON m.mes = k.mes AND m.campaign_id = k.campaign_id
LEFT JOIN nomes n ON n.campaign_id = k.campaign_id
ORDER BY k.mes DESC, gasto_anuncio DESC"""),

    # 3. Retorno: custo × honorário dos contratos online fechados no mês, com os dois CACs.
    "Mkt: retorno e CAC por mês (12m)": dict(display="table", sql=f"""
WITH meses AS (
  SELECT generate_series({MES_ATUAL} - interval '11 months', {MES_ATUAL}, interval '1 month')::date AS mes
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

    # 4. Realizado × meta do modelo, mês a mês (o mês corrente aparece parcial).
    "Mkt: realizado × meta (mês a mês)": dict(display="table", sql=f"""
WITH {REALIZADO}
SELECT to_char(r.mes, 'MM/YYYY') AS mes, r.metrica, ROUND(mt.valor, 2) AS meta, ROUND(r.valor, 2) AS realizado,
       ROUND(100 * r.valor / NULLIF(mt.valor, 0)) AS pct_da_meta
FROM realizado r
JOIN bi_marketing_metas mt ON mt.account_id = {A} AND mt.mes = r.mes AND mt.metrica = r.metrica
ORDER BY r.mes DESC, r.metrica"""),

    # 5. Acumulado do ano só com meses fechados (o mês corrente parcial puxaria o % para baixo).
    # CAC = custo somado / contratos somados; a meta de CAC é a do modelo ponderada pelos contratos.
    "Mkt: realizado × meta (acumulado do ano, meses fechados)": dict(display="table", sql=f"""
WITH {REALIZADO}, par AS (
  SELECT r.mes, r.metrica, mt.valor AS meta, r.valor AS realizado
  FROM realizado r
  JOIN bi_marketing_metas mt ON mt.account_id = {A} AND mt.mes = r.mes AND mt.metrica = r.metrica
  WHERE date_trunc('year', r.mes) = date_trunc('year', {AGORA}) AND r.mes < {MES_ATUAL}
), ano AS (
  SELECT metrica, SUM(meta) AS meta, SUM(realizado) AS realizado FROM par WHERE metrica <> 'cac' GROUP BY metrica
)
SELECT metrica, ROUND(meta, 2) AS meta, ROUND(realizado, 2) AS realizado, ROUND(100 * realizado / NULLIF(meta, 0)) AS pct_da_meta
FROM ano
UNION ALL
SELECT 'cac',
       ROUND((SELECT SUM(c.meta * k.meta) FROM par c JOIN par k ON k.mes = c.mes AND k.metrica = 'contratos' WHERE c.metrica = 'cac')
             / NULLIF((SELECT meta FROM ano WHERE metrica = 'contratos'), 0), 2),
       ROUND((SELECT realizado FROM ano WHERE metrica = 'custo_area') / NULLIF((SELECT realizado FROM ano WHERE metrica = 'contratos'), 0), 2),
       NULL"""),

    # 6. Conteúdo: peças publicadas, alcance e leads que chegaram pelo Instagram, por semana.
    "Mkt: peças × alcance × leads do Instagram (12 semanas)": dict(display="table", sql=f"""
WITH semanas AS (
  SELECT generate_series(date_trunc('week', {AGORA}) - interval '11 weeks', date_trunc('week', {AGORA}), interval '1 week')::date AS semana
), p AS (
  SELECT date_trunc('week', {local('publicado_em')})::date AS semana, COUNT(*) AS pecas,
         SUM(alcance) AS alcance, SUM(salvamentos) AS salvamentos, SUM(compartilhamentos) AS compartilhamentos
  FROM bi_pecas WHERE account_id = {A} GROUP BY 1
), l AS (
  SELECT date_trunc('week', {local('created_at')})::date AS semana, COUNT(*) AS leads_instagram
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
