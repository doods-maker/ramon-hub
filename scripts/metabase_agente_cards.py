#!/usr/bin/env python3
"""Cria/atualiza o bloco "Agente do hub" no dashboard Análise Comercial do Metabase.

Cards nativos sobre a tabela agente_execucoes (Task 9). Idempotente: casa os
cards por nome (cria se faltar, atualiza o SQL se mudou) e so acrescenta ao dashboard os que
ainda nao estao la.

Uso (credencial NUNCA no repo — vem do ambiente):
  METABASE_URL=https://bi... METABASE_ADMIN_KEY=... python scripts/metabase_agente_cards.py [--apply]
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
ROW0 = 80              # abaixo do bloco "Inteligência" (ROW0=56, heading + 2 linhas de 8 = ate 72)

HEADING = "Agente do hub — execuções do Claude"

CARDS = {
    "Agente: execuções por dia e status (30d)": dict(display="bar", sql=f"""
SELECT date_trunc('day', created_at)::date AS dia, status, COUNT(*) AS execucoes
FROM agente_execucoes
WHERE account_id = {ACCOUNT_ID} AND created_at > now() - interval '30 days'
GROUP BY 1, 2 ORDER BY 1, 2"""),
    "Agente: últimas 20 execuções": dict(display="table", sql=f"""
SELECT created_at, status, esforco, ROUND(duracao_ms / 1000.0, 1) AS segundos,
       left(pedido, 80) AS pedido, left(resumo, 120) AS resumo
FROM agente_execucoes
WHERE account_id = {ACCOUNT_ID}
ORDER BY created_at DESC LIMIT 20"""),
    "Agente: duração média por dia (30d)": dict(display="line", sql=f"""
SELECT date_trunc('day', created_at)::date AS dia, ROUND(AVG(duracao_ms) / 1000.0, 1) AS segundos_medios
FROM agente_execucoes
WHERE account_id = {ACCOUNT_ID} AND created_at > now() - interval '30 days'
GROUP BY 1 ORDER BY 1"""),
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


def ensure_cards(apply_):
    """Devolve {nome: card_id} criando/atualizando conforme preciso."""
    existing = {c["name"]: c for c in api("GET", "/card?f=all") if c.get("collection_id") == COLLECTION_ID}
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
