#!/usr/bin/env python3
"""Cria/atualiza o bloco "Meta Ads" (gasto x reunioes x contratos por anuncio + rastro dos avisos) no dashboard Analise Comercial.

Cards nativos sobre as views bi_leads (v02), bi_meta_gastos, bi_meta_eventos e bi_stage_transitions.
Idempotente: casa os cards por nome (cria se faltar, atualiza o SQL se mudou) e so acrescenta ao
dashboard os que ainda nao estao la. O bloco entra abaixo da ultima linha ocupada do dashboard (lida pela API).

Uso (credencial NUNCA no repo — vem do ambiente):
  METABASE_URL=https://bi... METABASE_ADMIN_KEY=... python scripts/metabase_bi_meta_cards.py [--apply]
Sem --apply so mostra o que faria.
"""
import json
import os
import sys
import urllib.request

DASHBOARD_ID = 3       # Análise Comercial
DATABASE_ID = 2        # chatwoot_production (leitura)
COLLECTION_ID = 7      # colecao do dashboard
ACCOUNT_ID = 2

HEADING = "Meta Ads — gasto, reuniões e contratos por anúncio"

CARDS = {
    # Gasto (bi_meta_gastos) cruzado com os leads do anuncio (bi_leads.meta_ad_id = ad_id).
    # Reuniao agendada = lead com transicao para a etapa de label fase-reuniao-agendada (transicoes guardam o NOME da etapa).
    "Meta: gasto × reuniões × contratos por anúncio (30d)": dict(display="table", sql=f"""
WITH g AS (
  SELECT ad_id, MAX(ad_name) AS anuncio, SUM(spend) AS gasto
  FROM bi_meta_gastos
  WHERE account_id = {ACCOUNT_ID} AND data >= current_date - 30
  GROUP BY ad_id
), reu AS (
  SELECT DISTINCT st.lead_id
  FROM bi_stage_transitions st
  JOIN lead_stages s ON s.account_id = st.account_id AND s.label = 'fase-reuniao-agendada' AND s.name = st.to_value
), l AS (
  SELECT b.meta_ad_id AS ad_id, COUNT(*) AS leads, COUNT(reu.lead_id) AS reunioes,
         COUNT(*) FILTER (WHERE b.won_at IS NOT NULL) AS contratos
  FROM bi_leads b
  LEFT JOIN reu ON reu.lead_id = b.id
  WHERE b.account_id = {ACCOUNT_ID} AND b.meta_source_type = 'ad' AND b.meta_ad_id IS NOT NULL AND b.created_at > now() - interval '30 days'
  GROUP BY b.meta_ad_id
)
SELECT COALESCE(g.anuncio, g.ad_id, l.ad_id) AS anuncio, ROUND(COALESCE(g.gasto, 0), 2) AS gasto,
       COALESCE(l.leads, 0) AS leads, COALESCE(l.reunioes, 0) AS reunioes, COALESCE(l.contratos, 0) AS contratos,
       ROUND(g.gasto / NULLIF(l.reunioes, 0), 2) AS custo_por_reuniao,
       ROUND(g.gasto / NULLIF(l.contratos, 0), 2) AS custo_por_contrato
FROM g FULL JOIN l ON l.ad_id = g.ad_id
ORDER BY gasto DESC"""),
    "Meta: gasto por campanha (30d)": dict(display="bar", sql=f"""
SELECT COALESCE(campaign_name, campaign_id) AS campanha, ROUND(SUM(spend), 2) AS gasto
FROM bi_meta_gastos
WHERE account_id = {ACCOUNT_ID} AND data >= current_date - 30
GROUP BY 1 ORDER BY gasto DESC"""),
    "Meta: avisos enviados × com erro (7d)": dict(display="bar", sql=f"""
SELECT status, COUNT(*) AS avisos
FROM bi_meta_eventos
WHERE account_id = {ACCOUNT_ID} AND ocorrido_em > now() - interval '7 days'
GROUP BY status ORDER BY avisos DESC"""),
}


def api(method, path, body=None):
    url = os.environ["METABASE_URL"].rstrip("/") + "/api" + path
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, method=method, data=data,
                                 headers={"X-API-KEY": os.environ["METABASE_ADMIN_KEY"],
                                          "Content-Type": "application/json"})
    with urllib.request.urlopen(req) as r:
        raw = r.read()
        return json.loads(raw) if raw else None


def native(sql):
    return {"type": "native", "database": DATABASE_ID, "native": {"query": sql.strip()}}


def sql_atual(card):
    dq = card["dataset_query"]
    if "stages" in dq:  # formato novo (lib) que o Metabase devolve no GET
        return dq["stages"][0].get("native", "")
    return dq.get("native", {}).get("query", "")


def ensure_cards(cards, apply_):
    """Devolve {nome: card_id} criando/atualizando conforme preciso."""
    existing = {c["name"]: c for c in api("GET", "/card?f=all") if c.get("collection_id") == COLLECTION_ID}
    ids = {}
    for name, spec in cards.items():
        card = existing.get(name)
        if card is None:
            print(f"[CRIAR] {name}")
            if apply_:
                created = api("POST", "/card", {"name": name, "display": spec["display"], "collection_id": COLLECTION_ID,
                                                 "dataset_query": native(spec["sql"]), "visualization_settings": {}})
                ids[name] = created["id"]
            continue
        ids[name] = card["id"]
        atual = sql_atual(api("GET", f"/card/{card['id']}")).strip()
        if atual == spec["sql"].strip():
            print(f"[JA OK] {name}")
        else:
            print(f"[ATUALIZAR SQL] {name}")
            if apply_:
                api("PUT", f"/card/{card['id']}", {"dataset_query": native(spec["sql"])})
    return ids


def ensure_dashcards(ids, cards, heading, apply_):
    dash = api("GET", f"/dashboard/{DASHBOARD_ID}")
    dashcards = dash["dashcards"]
    present_cards = {dc["card_id"] for dc in dashcards if dc.get("card_id")}
    head = next((dc for dc in dashcards if (dc.get("visualization_settings") or {}).get("text") == heading), None)
    # Bloco novo entra abaixo da ultima linha ocupada; se o titulo ja existe, os cards faltantes usam a linha dele.
    row0 = head["row"] if head else max((dc["row"] + dc["size_y"] for dc in dashcards), default=0)
    novos = []
    if head is None:
        novos.append({"id": -1, "card_id": None, "row": row0, "col": 0, "size_x": 24, "size_y": 1,
                      "visualization_settings": {"virtual_card": {"display": "heading"}, "text": heading},
                      "parameter_mappings": []})
    for i, name in enumerate(cards):
        cid = ids.get(name)
        if cid is None or cid in present_cards:
            continue
        # 1º cartao (tabela) ocupa a largura toda; os demais, metade cada, lado a lado.
        if i == 0:
            row, col, w = row0 + 1, 0, 24
        else:
            row, col, w = row0 + 9, 12 * (i - 1), 12
        novos.append({"id": -(i + 2), "card_id": cid, "row": row, "col": col, "size_x": w, "size_y": 8,
                      "parameter_mappings": [], "visualization_settings": {}})
    if not novos:
        print("[DASHBOARD JA OK]")
        return
    print(f"[DASHBOARD] acrescentar {len(novos)} bloco(s) a partir da linha {row0}")
    if apply_:
        keep = [{k: dc[k] for k in ("id", "card_id", "row", "col", "size_x", "size_y", "parameter_mappings",
                                   "visualization_settings", "dashboard_tab_id") if k in dc} for dc in dashcards]
        api("PUT", f"/dashboard/{DASHBOARD_ID}", {"dashcards": keep + novos})
        print("gravado.")


def main():
    apply_ = "--apply" in sys.argv
    if not os.environ.get("METABASE_URL") or not os.environ.get("METABASE_ADMIN_KEY"):
        sys.exit("faltam METABASE_URL e/ou METABASE_ADMIN_KEY no ambiente.")
    print(f"== {HEADING}")
    ids = ensure_cards(CARDS, apply_)
    ensure_dashcards(ids, CARDS, HEADING, apply_)


if __name__ == "__main__":
    main()
