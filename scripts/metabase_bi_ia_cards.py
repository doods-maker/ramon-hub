#!/usr/bin/env python3
"""Cria/atualiza o bloco "Inteligência" (metrica D8) no dashboard Análise Comercial do Metabase.

Cards nativos sobre as views bi_ia_rascunhos / bi_ia_conversas (Onda 4). Idempotente: casa os
cards por nome (cria se faltar, atualiza o SQL se mudou) e so acrescenta ao dashboard os que
ainda nao estao la.

Uso (credencial NUNCA no repo — vem do ambiente):
  METABASE_URL=https://bi... METABASE_ADMIN_KEY=... python scripts/metabase_bi_ia_cards.py [--apply]
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
ROW0 = 56              # primeira linha livre abaixo dos 13 cards (grid de 24 colunas)

HEADING = "Inteligência — rascunhos da IA e 1ª resposta"

CARDS = {
    "IA: rascunhos por desfecho (30d)": dict(display="bar", sql=f"""
SELECT desfecho, COUNT(*) AS rascunhos
FROM bi_ia_rascunhos
WHERE account_id = {ACCOUNT_ID} AND criado_em > now() - interval '30 days'
GROUP BY desfecho ORDER BY rascunhos DESC"""),
    "IA: % rascunho enviado sem edição (30d)": dict(display="scalar", sql=f"""
SELECT ROUND(100.0 * COUNT(*) FILTER (WHERE desfecho = 'igual')
             / NULLIF(COUNT(*) FILTER (WHERE desfecho IN ('igual','editado','descartado')), 0), 1) AS pct_igual
FROM bi_ia_rascunhos
WHERE account_id = {ACCOUNT_ID} AND criado_em > now() - interval '30 days'"""),
    "IA: minutos até 1ª resposta — com × sem IA (30d)": dict(display="bar", sql=f"""
SELECT CASE WHEN com_ia THEN 'com IA' ELSE 'sem IA' END AS grupo,
       ROUND(AVG(minutos_primeira_resposta), 1) AS minutos_medios, COUNT(*) AS conversas
FROM bi_ia_conversas
WHERE account_id = {ACCOUNT_ID} AND iniciada_em > now() - interval '30 days'
  AND minutos_primeira_resposta IS NOT NULL
GROUP BY com_ia ORDER BY com_ia DESC"""),
    "IA: conversas com handoff por dia (30d)": dict(display="line", sql=f"""
SELECT date_trunc('day', iniciada_em)::date AS dia, COUNT(*) FILTER (WHERE handoffs > 0) AS com_handoff
FROM bi_ia_conversas
WHERE account_id = {ACCOUNT_ID} AND iniciada_em > now() - interval '30 days'
GROUP BY 1 ORDER BY 1"""),
}
# ponytail: handoffs e 0/1 por conversa (o listener dedupa) — por isso "conversas com handoff", nao "numero de handoffs".


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


def ensure_cards(apply_):
    """Devolve {nome: card_id} criando/atualizando conforme preciso."""
    existing = {c["name"]: c for c in api("GET", f"/card?f=all") if c.get("collection_id") == COLLECTION_ID}
    ids = {}
    for name, spec in CARDS.items():
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


def ensure_dashcards(ids, apply_):
    dash = api("GET", f"/dashboard/{DASHBOARD_ID}")
    dashcards = dash["dashcards"]
    present_cards = {dc["card_id"] for dc in dashcards if dc.get("card_id")}
    has_heading = any((dc.get("visualization_settings") or {}).get("text") == HEADING for dc in dashcards)
    novos = []
    if not has_heading:
        novos.append({"id": -1, "card_id": None, "row": ROW0, "col": 0, "size_x": 24, "size_y": 1,
                      "visualization_settings": {"virtual_card": {"display": "heading"}, "text": HEADING},
                      "parameter_mappings": []})
    for i, name in enumerate(CARDS):
        cid = ids.get(name)
        if cid is None or cid in present_cards:
            continue
        novos.append({"id": -(i + 2), "card_id": cid, "row": ROW0 + 1 + 8 * (i // 2), "col": 12 * (i % 2),
                      "size_x": 12, "size_y": 8, "parameter_mappings": [], "visualization_settings": {}})
    if not novos:
        print("[DASHBOARD JA OK]")
        return
    print(f"[DASHBOARD] acrescentar {len(novos)} bloco(s)")
    if apply_:
        keep = [{k: dc[k] for k in ("id", "card_id", "row", "col", "size_x", "size_y", "parameter_mappings",
                                   "visualization_settings", "dashboard_tab_id") if k in dc} for dc in dashcards]
        api("PUT", f"/dashboard/{DASHBOARD_ID}", {"dashcards": keep + novos})
        print("gravado.")


def main():
    apply_ = "--apply" in sys.argv
    if not os.environ.get("METABASE_URL") or not os.environ.get("METABASE_ADMIN_KEY"):
        sys.exit("faltam METABASE_URL e/ou METABASE_ADMIN_KEY no ambiente.")
    ids = ensure_cards(apply_)
    ensure_dashcards(ids, apply_)


if __name__ == "__main__":
    main()
