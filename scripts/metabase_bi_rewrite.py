#!/usr/bin/env python3
"""Reescreve os cards do Metabase sobre as views bi_leads/bi_stage_transitions.

APLICAR SO NO DEPLOY DA ONDA 3. Dry-run por padrao: nada e gravado sem --apply.

SQL novo dos 13 cards do dashboard "Analise Comercial" (id 3) documentado
(com o "antes"/"depois" e o que cada view absorveu) em
docs/superpowers/specs/2026-08-14-metabase-cards-sobre-views.md. Os SQLs
ficam embutidos aqui (nao lidos do doc) por decisao explicita: parsear
markdown pra extrair SQL e uma camada fragil a mais pra um script que roda
uma vez, num deploy assistido, com diff na tela antes de gravar. Se um SQL
mudar, atualizar o doc e este dict juntos (mesma string).

Dashboard "Placar do Dono" (id 2, cards 40-47) nao tem SQL no repo: o script
baixa o SQL atual de cada card e aplica 2 transformacoes (remove o predicado
calculo-advbox, troca `FROM leads` por `FROM bi_leads`), mostrando o diff.

Env obrigatorias (a chave NUNCA fica no repo):
  METABASE_URL        ex.: https://bi.ramonantonio.adv.br
  METABASE_ADMIN_KEY  API key admin do Metabase (conhecimento\\metabase-credenciais.txt)

Uso:
  python scripts/metabase_bi_rewrite.py                 # dry-run, so mostra diffs
  python scripts/metabase_bi_rewrite.py --apply          # grava, confirma card a card
  python scripts/metabase_bi_rewrite.py --apply --yes    # grava sem confirmar cada card
  python scripts/metabase_bi_rewrite.py --only 2         # so o Placar (cards 40-47)
  python scripts/metabase_bi_rewrite.py --only 3         # so a Analise Comercial
"""
import argparse
import difflib
import json
import os
import re
import sys
import urllib.error
import urllib.request

DASHBOARD_ANALISE_COMERCIAL_ID = 3
DASHBOARD_PLACAR_ID = 2
PLACAR_CARD_IDS = range(40, 48)

CALCULO_ADVBOX_PATTERN = re.compile(r"(?:\w+\.)?source IS DISTINCT FROM 'calculo-advbox'")
FROM_LEADS_RE = re.compile(r"\bFROM leads\b")


def strip_calculo_advbox_predicate(sql):
    """Remove o predicado calculo-advbox (1a ocorrencia) engolindo o AND
    vizinho, de qualquer lado. Se o predicado for a UNICA condicao do WHERE
    (sem AND de nenhum lado), vira `WHERE TRUE` em vez de deixar um WHERE
    penduricado com nada depois."""
    m = CALCULO_ADVBOX_PATTERN.search(sql)
    if not m:
        return sql
    before, after = sql[:m.start()], sql[m.end():]
    after_sem_and = re.sub(r"^\s+AND\s+", "", after, count=1)
    if after_sem_and != after:
        return before + after_sem_and
    before_sem_and = re.sub(r"AND\s+$", "", before, count=1)
    if before_sem_and != before:
        return before_sem_and + after
    return before + "TRUE" + after

CARDS_ANALISE_COMERCIAL = {
    "Leads novos por mês (12m)": """
SELECT date_trunc('month', l.created_at)::date AS mes, COUNT(*) AS leads
FROM bi_leads l
WHERE l.account_id = 2
  AND l.created_at >= date_trunc('month', now()) - interval '11 months'
GROUP BY 1 ORDER BY 1""",

    "Contratos e valor fechado por mês (12m)": """
SELECT date_trunc('month', l.won_at)::date AS mes, COUNT(*) AS contratos, COALESCE(SUM(l.value),0) AS valor
FROM bi_leads l
WHERE l.account_id = 2
  AND l.won_at >= date_trunc('month', now()) - interval '11 months'
GROUP BY 1 ORDER BY 1""",

    "Conversão por mês de criação (12m)": """
SELECT date_trunc('month', l.created_at)::date AS mes_de_criacao,
       ROUND(100.0 * COUNT(*) FILTER (WHERE l.won_at IS NOT NULL) / COUNT(*), 1) AS conversao_pct
FROM bi_leads l
WHERE l.account_id = 2
  AND l.created_at >= date_trunc('month', now()) - interval '11 months'
GROUP BY 1 ORDER BY 1""",

    "Tempo médio lead → contrato (12m)": """
SELECT date_trunc('month', l.won_at)::date AS mes,
       ROUND(AVG(EXTRACT(EPOCH FROM (l.won_at - l.created_at)) / 86400)::numeric, 1) AS dias_medios
FROM bi_leads l
WHERE l.account_id = 2
  AND l.won_at >= date_trunc('month', now()) - interval '11 months'
GROUP BY 1 ORDER BY 1""",

    "Tempo médio em cada etapa (histórico)": """
WITH passagens AS (
  SELECT st.to_value AS etapa, st.created_at,
         LEAD(st.created_at) OVER (PARTITION BY st.lead_id ORDER BY st.created_at) AS saiu_em
  FROM bi_stage_transitions st
  WHERE st.account_id = 2
), entrada AS (
  SELECT 'Entrada (1ª etapa)' AS etapa, l.created_at, MIN(st.created_at) AS saiu_em
  FROM bi_leads l LEFT JOIN bi_stage_transitions st ON st.lead_id = l.id
  WHERE l.account_id = 2
  GROUP BY l.id, l.created_at
)
SELECT etapa,
       ROUND(AVG(EXTRACT(EPOCH FROM (COALESCE(saiu_em, now()) - created_at)) / 86400)::numeric, 1) AS dias_medios,
       COUNT(*) AS passagens
FROM (SELECT * FROM passagens UNION ALL SELECT * FROM entrada) t
GROUP BY etapa ORDER BY dias_medios DESC""",

    "Transições de etapa (12m)": """
SELECT st.from_value || ' → ' || st.to_value AS transicao, COUNT(*) AS vezes
FROM bi_stage_transitions st
WHERE st.account_id = 2
  AND st.created_at >= now() - interval '12 months'
GROUP BY 1 ORDER BY 2 DESC""",

    "Motivos de perda (12m)": """
SELECT COALESCE(l.lost_reason, '(sem motivo)') AS motivo, COUNT(*) AS leads, COALESCE(SUM(l.value),0) AS valor_perdido
FROM bi_leads l
WHERE l.account_id = 2
  AND l.lost_at >= now() - interval '12 months'
GROUP BY 1 ORDER BY 2 DESC""",

    "Canal: leads, conversão e valor (12m)": """
SELECT l.channel AS canal, COUNT(*) AS leads,
       COUNT(*) FILTER (WHERE l.won_at IS NOT NULL) AS fechados,
       ROUND(100.0 * COUNT(*) FILTER (WHERE l.won_at IS NOT NULL) / COUNT(*), 1) AS conversao_pct,
       COALESCE(SUM(l.value) FILTER (WHERE l.won_at IS NOT NULL), 0) AS valor_fechado
FROM bi_leads l
WHERE l.account_id = 2
  AND l.created_at >= now() - interval '12 months'
GROUP BY 1 ORDER BY leads DESC""",

    "Tese: leads, conversão e valor (12m)": """
SELECT COALESCE(l.thesis_name, '(sem tese)') AS tese, COUNT(*) AS leads,
       COUNT(*) FILTER (WHERE l.won_at IS NOT NULL) AS fechados,
       ROUND(100.0 * COUNT(*) FILTER (WHERE l.won_at IS NOT NULL) / COUNT(*), 1) AS conversao_pct,
       COALESCE(SUM(l.value) FILTER (WHERE l.won_at IS NOT NULL), 0) AS valor_fechado
FROM bi_leads l
WHERE l.account_id = 2
  AND l.created_at >= now() - interval '12 months'
GROUP BY 1 ORDER BY leads DESC""",

    "Campanha (UTM): leads e fechados (12m)": """
SELECT l.utm_campaign AS campanha, COUNT(*) AS leads,
       COUNT(*) FILTER (WHERE l.won_at IS NOT NULL) AS fechados
FROM bi_leads l
WHERE l.account_id = 2
  AND l.utm_campaign IS NOT NULL
  AND l.created_at >= now() - interval '12 months'
GROUP BY 1 ORDER BY 2 DESC""",

    "SLA de 1ª resposta por mês (12m)": """
SELECT date_trunc('month', c.created_at)::date AS mes,
       ROUND(AVG(EXTRACT(EPOCH FROM (c.first_reply_created_at - c.created_at)) / 60)::numeric, 1) AS minutos_medios,
       ROUND(100.0 * COUNT(*) FILTER (
         WHERE c.first_reply_created_at - c.created_at <= (COALESCE(i.first_response_sla_minutes, 15) || ' minutes')::interval
       ) / COUNT(*), 1) AS dentro_do_sla_pct
FROM bi_leads l
JOIN leads l_raw ON l_raw.id = l.id
JOIN conversations c ON c.id = l_raw.conversation_id
JOIN inboxes i ON i.id = c.inbox_id
WHERE l.account_id = 2 AND c.first_reply_created_at IS NOT NULL
  AND c.created_at >= date_trunc('month', now()) - interval '11 months'
GROUP BY 1 ORDER BY 1""",

    "Reuniões: marcadas × realizadas (12m)": """
SELECT date_trunc('month', lt.due_at)::date AS mes, COUNT(*) AS marcadas, COUNT(lt.completed_at) AS realizadas
FROM lead_tasks lt JOIN bi_leads l ON l.id = lt.lead_id
WHERE lt.account_id = 2 AND lt.kind = 'meeting'
  AND lt.due_at >= date_trunc('month', now()) - interval '11 months'
GROUP BY 1 ORDER BY 1""",

    "Follow-ups feitos × contratos (12m)": """
SELECT mes, SUM(follow_ups) AS follow_ups, SUM(contratos) AS contratos FROM (
  SELECT date_trunc('month', lt.completed_at)::date AS mes, COUNT(*) AS follow_ups, 0 AS contratos
  FROM lead_tasks lt JOIN bi_leads l ON l.id = lt.lead_id
  WHERE lt.account_id = 2 AND lt.kind = 'follow_up' AND lt.completed_at IS NOT NULL
    AND lt.completed_at >= date_trunc('month', now()) - interval '11 months'
  GROUP BY 1
  UNION ALL
  SELECT date_trunc('month', l.won_at)::date, 0, COUNT(*)
  FROM bi_leads l WHERE l.account_id = 2 AND l.won_at >= date_trunc('month', now()) - interval '11 months'
  GROUP BY 1
) t GROUP BY mes ORDER BY mes""",
}


def api(method, path, key, body=None):
    url = os.environ["METABASE_URL"].rstrip("/") + "/api" + path
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        url, method=method, data=data,
        headers={"X-API-KEY": key, "Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req) as r:
        raw = r.read()
        return json.loads(raw) if raw else None


def get_sql(card):
    dq = card["dataset_query"]
    if "stages" in dq:  # formato novo (lib), visto no historico do mb_faxina.py
        return dq["stages"][0]["native"]
    return dq["native"]["query"]


def show_diff(old, new, label):
    diff = difflib.unified_diff(
        old.splitlines(keepends=True), new.splitlines(keepends=True),
        fromfile=f"{label} (atual)", tofile=f"{label} (novo)",
    )
    sys.stdout.writelines(diff)
    print()


def confirm(label, yes):
    if yes:
        return True
    return input(f"Aplicar em '{label}'? [s/N] ").strip().lower() == "s"


def apply_card(card_id, database, new_sql, key):
    api("PUT", f"/card/{card_id}", key, {
        "dataset_query": {"type": "native", "database": database,
                           "native": {"query": new_sql}},
    })


def rewrite_analise_comercial(key, apply_, yes):
    dash = api("GET", f"/dashboard/{DASHBOARD_ANALISE_COMERCIAL_ID}", key)
    id_by_name = {}
    for dc in dash.get("dashcards", []):
        c = dc.get("card") or {}
        if c.get("name"):
            id_by_name[c["name"]] = c["id"]

    for name, new_sql in CARDS_ANALISE_COMERCIAL.items():
        new_sql = new_sql.strip()
        card_id = id_by_name.get(name)
        if card_id is None:
            print(f"[AUSENTE] card '{name}' nao encontrado no dashboard {DASHBOARD_ANALISE_COMERCIAL_ID}")
            continue
        card = api("GET", f"/card/{card_id}", key)
        old_sql = get_sql(card).strip()
        if old_sql == new_sql:
            print(f"[JA OK] {name}")
            continue
        print(f"--- {name} (card {card_id}) ---")
        show_diff(old_sql, new_sql, name)
        if not apply_:
            continue
        if not confirm(name, yes):
            print("pulado.")
            continue
        apply_card(card_id, card["dataset_query"].get("database", 2), new_sql, key)
        print("gravado.")


def transform_placar_sql(sql):
    sql = strip_calculo_advbox_predicate(sql)
    sql = FROM_LEADS_RE.sub("FROM bi_leads", sql)
    return sql


def rewrite_placar(key, apply_, yes):
    for card_id in PLACAR_CARD_IDS:
        card = api("GET", f"/card/{card_id}", key)
        old_sql = get_sql(card).strip()
        new_sql = transform_placar_sql(old_sql).strip()
        if old_sql == new_sql:
            print(f"[NADA A MUDAR] card {card_id} ({card.get('name', '')})")
            continue
        print(f"--- card {card_id} ({card.get('name', '')}) ---")
        show_diff(old_sql, new_sql, f"card {card_id}")
        if not apply_:
            continue
        if not confirm(f"card {card_id}", yes):
            print("pulado.")
            continue
        apply_card(card_id, card["dataset_query"].get("database", 2), new_sql, key)
        print("gravado.")


def main():
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--apply", action="store_true", help="grava (default: so mostra diff)")
    parser.add_argument("--yes", action="store_true", help="pula confirmacao por card")
    parser.add_argument("--only", choices=["2", "3"], help="so um dos dois dashboards")
    args = parser.parse_args()

    key = os.environ.get("METABASE_ADMIN_KEY")
    if not os.environ.get("METABASE_URL") or not key:
        sys.exit("faltam METABASE_URL e/ou METABASE_ADMIN_KEY no ambiente.")

    if not args.apply:
        print("*** DRY-RUN — nada sera gravado. Use --apply para gravar. ***\n")

    if args.only != "2":
        print(f"=== Dashboard {DASHBOARD_ANALISE_COMERCIAL_ID} — Análise Comercial ===")
        rewrite_analise_comercial(key, args.apply, args.yes)
    if args.only != "3":
        print(f"\n=== Dashboard {DASHBOARD_PLACAR_ID} — Placar do Dono (cards 40-47) ===")
        rewrite_placar(key, args.apply, args.yes)


if __name__ == "__main__":
    try:
        main()
    except urllib.error.HTTPError as e:
        sys.exit(f"HTTP {e.code} em {e.url}: {e.read().decode(errors='replace')}")
