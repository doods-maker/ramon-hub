# Cards do Metabase reescritos sobre as views `bi_*` (Onda 3)

> ⚠️ **APLICAR SÓ NO DEPLOY DA ONDA 3 — via `scripts/metabase_bi_rewrite.py`.**
> Este documento é a **fonte de leitura** dos SQLs novos; nada aqui é executado
> pela leitura do doc. A aplicação de verdade é o script (dry-run por padrão).
> **Nenhuma credencial do Metabase aparece neste arquivo nem no script** — a
> chave vive fora do repo, em `conhecimento\metabase-credenciais.txt`, e é lida
> só do ambiente (`METABASE_URL` / `METABASE_ADMIN_KEY`) na hora de rodar.

## Por quê

As views `bi_leads` e `bi_stage_transitions` (Task 5, `db/views/*.sql`) passam
a ser a fonte canônica de "lead de funil" pro Metabase — a mesma regra que
hoje cada card do dashboard "Análise Comercial" (id 3) repete na mão via
`l.source IS DISTINCT FROM 'calculo-advbox'`. Reescrever os cards sobre as
views mata a dívida "mudou a regra de Lead → revisar queries do Metabase"
(decisão 13 da spec de 13/08): a regra passa a viver **só** na view.

Fonte do SQL atual (o "antes" de cada card abaixo): `docs/superpowers/plans/2026-07-31-bi-relatorios-metabase.md:85-206`.
Colunas das views: `db/views/bi_leads_v01.sql` e `db/views/bi_stage_transitions_v01.sql`.

## Regras da reescrita (aplicadas nos 13 cards abaixo)

- `WHERE ... account_id = 2` **fica** no card — as views não filtram conta.
- `l.source IS DISTINCT FROM 'calculo-advbox'` **some** — `bi_leads` já garante.
- `COALESCE(l.channel, 'outro')` (card 8) **some** — a view entrega `channel` pronto.
- `LEFT JOIN theses t ON t.id = l.thesis_id` (card 9) **some** — usa `thesis_name` da view.
- `l.custom_attributes #>> '{utm,utm_campaign}'` (card 10) **some** — usa `utm_campaign` da view.
- Cards 5 e 6 trocam `lead_activities la JOIN leads l` por `bi_stage_transitions`
  (a view já faz esse join e já filtra `kind = 'stage_changed'` + funil).
- Cards 11–13 mantêm `conversations`/`lead_tasks`/`inboxes` nativos; o lado de
  leads vira `bi_leads`.
- Toda janela de tempo (`interval '11 months'`, `interval '12 months'`, com ou
  sem `date_trunc`) fica **byte-idêntica** ao card original — só a fonte muda,
  nunca a métrica.

## ⚠️ Gap encontrado: card 11 precisa de `conversation_id`, ausente em `bi_leads`

`bi_leads` não expõe `conversation_id` (não estava nas colunas pedidas pela
Task 5 — só entra em cena no card 11, SLA de 1ª resposta). Sem essa coluna não
dá pra chegar em `conversations` a partir da view. Solução mínima, sem tocar
na view (fora de escopo desta task): um `JOIN leads l_raw ON l_raw.id = l.id`
1:1 só pra pegar essa coluna — o filtro de funil continua 100% garantido por
`bi_leads` (que já restringe `l.id` aos leads corretos); o join extra não abre
brecha nenhuma, é só um lookup de coluna. Registrar como pendência pra uma
`bi_leads_v02` futura (acrescentar `conversation_id`) se isso incomodar depois.

---

## Card 1 — Leads novos por mês (12m)

```sql
SELECT date_trunc('month', l.created_at)::date AS mes, COUNT(*) AS leads
FROM bi_leads l
WHERE l.account_id = 2
  AND l.created_at >= date_trunc('month', now()) - interval '11 months'
GROUP BY 1 ORDER BY 1
```

O que a view absorveu: o filtro `source IS DISTINCT FROM 'calculo-advbox'`.

## Card 2 — Contratos e valor fechado por mês (12m)

```sql
SELECT date_trunc('month', l.won_at)::date AS mes, COUNT(*) AS contratos, COALESCE(SUM(l.value),0) AS valor
FROM bi_leads l
WHERE l.account_id = 2
  AND l.won_at >= date_trunc('month', now()) - interval '11 months'
GROUP BY 1 ORDER BY 1
```

O que a view absorveu: o filtro `source IS DISTINCT FROM 'calculo-advbox'`.

## Card 3 — Conversão por mês de criação (12m)

```sql
SELECT date_trunc('month', l.created_at)::date AS mes_de_criacao,
       ROUND(100.0 * COUNT(*) FILTER (WHERE l.won_at IS NOT NULL) / COUNT(*), 1) AS conversao_pct
FROM bi_leads l
WHERE l.account_id = 2
  AND l.created_at >= date_trunc('month', now()) - interval '11 months'
GROUP BY 1 ORDER BY 1
```

O que a view absorveu: o filtro `source IS DISTINCT FROM 'calculo-advbox'`.

## Card 4 — Tempo médio lead → contrato (12m)

```sql
SELECT date_trunc('month', l.won_at)::date AS mes,
       ROUND(AVG(EXTRACT(EPOCH FROM (l.won_at - l.created_at)) / 86400)::numeric, 1) AS dias_medios
FROM bi_leads l
WHERE l.account_id = 2
  AND l.won_at >= date_trunc('month', now()) - interval '11 months'
GROUP BY 1 ORDER BY 1
```

O que a view absorveu: o filtro `source IS DISTINCT FROM 'calculo-advbox'`.

## Card 5 — Tempo médio em cada etapa (histórico)

```sql
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
GROUP BY etapa ORDER BY dias_medios DESC
```

O que a view absorveu: `lead_activities la JOIN leads l` (+ `kind = 'stage_changed'`
+ filtro de funil) virou `bi_stage_transitions`; `entrada` usa `bi_leads` no
lugar de `leads` puro.

## Card 6 — Transições de etapa (12m)

```sql
SELECT st.from_value || ' → ' || st.to_value AS transicao, COUNT(*) AS vezes
FROM bi_stage_transitions st
WHERE st.account_id = 2
  AND st.created_at >= now() - interval '12 months'
GROUP BY 1 ORDER BY 2 DESC
```

O que a view absorveu: o `JOIN leads` + `kind = 'stage_changed'` + filtro de
funil — tudo dentro de `bi_stage_transitions`.

## Card 7 — Motivos de perda (12m)

```sql
SELECT COALESCE(l.lost_reason, '(sem motivo)') AS motivo, COUNT(*) AS leads, COALESCE(SUM(l.value),0) AS valor_perdido
FROM bi_leads l
WHERE l.account_id = 2
  AND l.lost_at >= now() - interval '12 months'
GROUP BY 1 ORDER BY 2 DESC
```

O que a view absorveu: o filtro `source IS DISTINCT FROM 'calculo-advbox'`.

## Card 8 — Canal: leads, conversão e valor (12m)

```sql
SELECT l.channel AS canal, COUNT(*) AS leads,
       COUNT(*) FILTER (WHERE l.won_at IS NOT NULL) AS fechados,
       ROUND(100.0 * COUNT(*) FILTER (WHERE l.won_at IS NOT NULL) / COUNT(*), 1) AS conversao_pct,
       COALESCE(SUM(l.value) FILTER (WHERE l.won_at IS NOT NULL), 0) AS valor_fechado
FROM bi_leads l
WHERE l.account_id = 2
  AND l.created_at >= now() - interval '12 months'
GROUP BY 1 ORDER BY leads DESC
```

O que a view absorveu: o `COALESCE(l.channel, 'outro')` — `bi_leads.channel`
já vem pronto — e o filtro `source IS DISTINCT FROM 'calculo-advbox'`.

## Card 9 — Tese: leads, conversão e valor (12m)

```sql
SELECT COALESCE(l.thesis_name, '(sem tese)') AS tese, COUNT(*) AS leads,
       COUNT(*) FILTER (WHERE l.won_at IS NOT NULL) AS fechados,
       ROUND(100.0 * COUNT(*) FILTER (WHERE l.won_at IS NOT NULL) / COUNT(*), 1) AS conversao_pct,
       COALESCE(SUM(l.value) FILTER (WHERE l.won_at IS NOT NULL), 0) AS valor_fechado
FROM bi_leads l
WHERE l.account_id = 2
  AND l.created_at >= now() - interval '12 months'
GROUP BY 1 ORDER BY leads DESC
```

O que a view absorveu: o `LEFT JOIN theses t ON t.id = l.thesis_id` —
`bi_leads.thesis_name` já vem pronto — e o filtro de funil.

## Card 10 — Campanha (UTM): leads e fechados (12m)

```sql
SELECT l.utm_campaign AS campanha, COUNT(*) AS leads,
       COUNT(*) FILTER (WHERE l.won_at IS NOT NULL) AS fechados
FROM bi_leads l
WHERE l.account_id = 2
  AND l.utm_campaign IS NOT NULL
  AND l.created_at >= now() - interval '12 months'
GROUP BY 1 ORDER BY 2 DESC
```

O que a view absorveu: o `l.custom_attributes #>> '{utm,utm_campaign}'` —
`bi_leads.utm_campaign` já vem extraído — e o filtro de funil.

## Card 11 — SLA de 1ª resposta por mês (12m)

```sql
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
GROUP BY 1 ORDER BY 1
```

O que a view absorveu: o filtro de funil. O `JOIN leads l_raw ON l_raw.id = l.id`
é só pra pegar `conversation_id` (ausente em `bi_leads` — ver gap acima); não
reabre a exclusão de calculo-advbox porque `l.id` já vem restrito por `bi_leads`.

## Card 12 — Reuniões: marcadas × realizadas (12m)

```sql
SELECT date_trunc('month', lt.due_at)::date AS mes, COUNT(*) AS marcadas, COUNT(lt.completed_at) AS realizadas
FROM lead_tasks lt JOIN bi_leads l ON l.id = lt.lead_id
WHERE lt.account_id = 2 AND lt.kind = 'meeting'
  AND lt.due_at >= date_trunc('month', now()) - interval '11 months'
GROUP BY 1 ORDER BY 1
```

O que a view absorveu: o filtro `source IS DISTINCT FROM 'calculo-advbox'`.

## Card 13 — Follow-ups feitos × contratos (12m)

```sql
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
) t GROUP BY mes ORDER BY mes
```

O que a view absorveu: o filtro `source IS DISTINCT FROM 'calculo-advbox'` (nas
duas metades do `UNION ALL`).

---

## Placar do Dono (dashboard id 2, cards 40–47)

Esses 8 cards não têm SQL neste repo — nasceram direto na API do Metabase
(Task 1 do plano de 31/07) e já foram corrigidos uma vez com
`AND {alias}source IS DISTINCT FROM 'calculo-advbox'` logo após o `WHERE`
(script `mb_faxina.py`, histórico). Sem o texto fonte, o script **baixa** o
SQL atual de cada card (`GET /api/card/:id`) e aplica 2 transformações:

1. Remove o predicado `source IS DISTINCT FROM 'calculo-advbox'` (com ou sem
   alias `l.`), engolindo o `AND` vizinho — de qualquer lado. Se o predicado
   for a única condição do `WHERE` (sem `AND` de nenhum lado), vira
   `WHERE TRUE` em vez de deixar um `WHERE` penduricado sem nada depois.
2. Troca `FROM leads` (com ou sem alias `l`) por `FROM bi_leads`.

Mostra o diff de cada card antes de gravar (mesmo fluxo dry-run/`--apply` dos
13 cards acima). Ver `scripts/metabase_bi_rewrite.py`.

## Decisão: SQL embutido no script, não lido do doc

Os 13 SQLs novos ficam **embutidos em `scripts/metabase_bi_rewrite.py`**
(dict `CARDS_ANALISE_COMERCIAL`, casado por nome do card) em vez de
parseados deste markdown. Ler markdown pra extrair SQL é mais uma camada de
parsing frágil (fences, nomes de card como heading) pra um script que já vai
rodar uma vez, num deploy assistido, com diff na tela antes de gravar — não
compensa. Este doc é a documentação humana; o script é a fonte executável.
Se um SQL mudar, atualizar os dois juntos (é a mesma string).

## Como aplicar (gate do deploy, fora desta task)

```bash
export METABASE_URL=https://bi.ramonantonio.adv.br
export METABASE_ADMIN_KEY=<ler de conhecimento\metabase-credenciais.txt>

python scripts/metabase_bi_rewrite.py                # dry-run: só mostra diff
python scripts/metabase_bi_rewrite.py --apply         # grava, confirma card a card
python scripts/metabase_bi_rewrite.py --apply --yes   # grava sem confirmar cada card
python scripts/metabase_bi_rewrite.py --only 2        # só o Placar (cards 40-47)
python scripts/metabase_bi_rewrite.py --only 3        # só a Análise Comercial
```

Depois de aplicar: `POST /api/card/:id/query` em cada card tocado e conferir
`status == 'completed'` (mesmo critério de verificação da Task 2 do plano de
31/07).
