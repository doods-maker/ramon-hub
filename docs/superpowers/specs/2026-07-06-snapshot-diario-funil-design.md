# Snapshot Diário do Funil — design

**Ramon Antônio Advogados · ramon-hub · 06/07/2026**
**Organismo, Onda 0 · aprovado pelo Eduardo em 06/07/2026**

> Primeira fatia do "Organismo" (visão aprovada 05/07 em
> `comercial\docs\specs\2026-07-05-plano-sem-freios.md`). Onda 0 = fundação de
> dados barata. Este documento cobre **só** o snapshot diário do funil; o
> catálogo canônico de `source` (outro item da Onda 0) é fatia separada.

---

## 1. Problema

O hub só conhece o estado **atual** do funil. A jornada de cada lead já é
rastreada (`lead_activities` grava mudança de etapa, ganho, perda, valor; e
`won_at`/`lost_at` são timestamps nos leads — nada disso se perde). O que
**evapora todo dia** é o **retrato agregado**: quantos leads e quanto valor
havia parados em cada etapa do funil naquele dia. Isso é caríssimo (e
impreciso) de reconstruir depois e é exatamente o insumo do Placar do Dono
(Onda 4): funil ao longo do tempo, P&L por tese, "onde os casos vazam".

Por isso a urgência: cada dia sem captura é um dia de história agregada perdida
pra sempre. Começamos a capturar **de hoje pra frente**; não há reconstrução do
passado (é justamente o que não dá pra fazer com fidelidade).

## 2. O que se grava (e o que não precisa)

- **Grava:** o **estoque** por (dia × etapa × tese) — contagem de leads e soma
  de valor em pipeline.
- **NÃO grava (porque não se perde):** ganhos/perdas do dia — derivam sempre de
  `won_at`/`lost_at`; e como "Fechado"/"Perdido" são etapas, a contagem
  cumulativa deles já aparece como estoque das próprias etapas won/lost.

## 3. Granularidade

Uma linha por **(conta × dia × etapa × tese)**. Decisão do Eduardo (06/07):
agregado dia×etapa×tese — a quebra por tese é o coração do P&L. Snapshot
por-lead foi descartado (YAGNI: a jornada por-lead já vem das `lead_activities`).

## 4. Arquitetura

### 4.1 Tabela `funnel_snapshots` (fato append-only)

| coluna | tipo | notas |
|---|---|---|
| `account_id` | bigint, not null | index; multi-conta como toda tabela Ramon |
| `snapshot_date` | date, not null | o dia capturado (TZ América/São_Paulo) |
| `lead_stage_id` | bigint, nullable | FK `on_delete: :nullify` — join com a etapa atual |
| `stage_name` | string, not null | **denormalizado**: história sobrevive a rename/delete |
| `stage_position` | integer, not null | ordena o funil no read |
| `is_won` | boolean, not null, default false | denormalizado (P&L sabe o que é fechado) |
| `is_lost` | boolean, not null, default false | denormalizado |
| `thesis_id` | bigint, nullable | FK `on_delete: :nullify` |
| `thesis_name` | string, nullable | denormalizado; `null` = "sem tese" |
| `leads_count` | integer, not null, default 0 | nº de leads naquela etapa×tese |
| `value_sum` | decimal, not null, default 0 | R$ em pipeline (mesma precisão de `leads.value`) |
| `created_at`/`updated_at` | timestamps | |

Índice: `(account_id, snapshot_date)` — cobre a query de leitura e o
delete-then-insert. **Sem índice único** de propósito: `thesis_id` nulo
quebraria unicidade no Postgres (nulls distintos), e a idempotência vem do
delete-then-insert (§4.3), não de constraint.

Denormalização de `stage_name`/`thesis_name`/flags é intencional: é tabela de
fatos; o rótulo tem que **congelar no tempo**. Se a etapa "Reunião" virar
"Fechamento" mês que vem, o snapshot de hoje ainda mostra "Reunião".

Nome sem prefixo `ramon_` seguindo a convenção do fork (`leads`, `theses`,
`lead_triages`, `lead_activities`…).

### 4.2 Serviço `Ramon::FunnelSnapshotService`

`app/services/ramon/funnel_snapshot_service.rb`. Interface:

```ruby
Ramon::FunnelSnapshotService.new(account:, date: Time.zone.today).perform
```

- Agrega `Lead.unscoped.where(account:).group(:lead_stage_id, :thesis_id)` com
  `count` + `sum(:value)`. `unscoped` evita o `default_scope order(...)` do Lead
  interferir na agregação (lição das queries do fork).
- Para cada grupo, resolve `stage_name`/`position`/`is_won`/`is_lost` da
  `LeadStage` e `thesis_name` da `Thesis` (nulo se sem tese), e monta a linha.
- **Idempotente**: numa transação, `FunnelSnapshot.where(account:,
  snapshot_date: date).delete_all` seguido de `insert_all` das linhas novas.
  Re-rodar o mesmo dia substitui — sem duplicar.
- Etapa×tese sem nenhum lead simplesmente não gera linha (ausência = zero na
  leitura).

### 4.3 Job `Ramon::DailyFunnelSnapshotJob`

`app/jobs/ramon/daily_funnel_snapshot_job.rb`. `Account.find_each` chamando o
serviço para `Time.zone.today`. Registrado em `config/schedule.yml`:

```yaml
ramon_daily_funnel_snapshot_job:
  cron: '5 3 * * *'   # 00:05 America/Sao_Paulo (UTC-3) — captura a virada do dia
  class: 'Ramon::DailyFunnelSnapshotJob'
  queue: scheduled_jobs
```

`snapshot_date` = `Time.zone.today` no momento da rodada. Com a app em TZ
Brasília, rodar 00:05 BRT grava o retrato "na entrada do dia" (≈ fechamento do
dia anterior).

**Dia 0 no deploy**: rodar uma vez à mão logo após subir
(`rails runner "Ramon::DailyFunnelSnapshotJob.perform_now"`), pra o primeiro
snapshot existir na hora e não esperar até a próxima 00:05. **Não** no
migration (lição 03/07: migration não chama service de app que evolui).

### 4.4 Leitura mínima (não é o Placar do Dono)

Reaproveita o endpoint **existente** `GET .../ramon_dashboard` (que já serve o
Centro de Comando com `today`/`funnel`/`week`) em vez de criar endpoint/store
novos (mais lazy, mesmo seam do futuro Placar). Ganha uma chave `history`:
últimos 30 dias, uma entrada por dia `{ date, leads_count, value_sum }`, rolada
sobre as **etapas abertas** (is_won=false, is_lost=false) — o "pipeline vivo"
ao longo do tempo. O store `ramonDashboard` já guarda a resposta inteira, então
o front lê `data.history` sem mudança de store.

**Painel** no **Centro de Comando** (`CommandCenter.vue`, a superfície que
sucedeu o RamonOverview placeholder): seção "Funil nos últimos 30 dias" — uma
**tabela compacta** (por dia: nº de leads ativos + R$ em pipeline) e um
**sparkline SVG inline** (helper puro `sparklinePath`, sem dependência de chart
nova). Objetivo é verificação/smoke visual, não análise.

**Adiado (YAGNI, sem retrato dedicado agora):** filtro por tese no painel e
endpoint dedicado. O dado gravado já tem a quebra por tese (§4.1), então ambos
entram sem retrabalho quando o Placar do Dono (Onda 4) precisar.

## 5. Fora de escopo

- Catálogo canônico de `source` (fatia Onda 0 separada).
- Reconstrução de dias passados (impossível com fidelidade — é o próprio motivo
  de começar já). Nota: uma reconstrução *grosseira* de membership por etapa ao
  longo do tempo seria possível a partir de `lead_activities`, mas é imprecisa e
  fica fora.
- Placar do Dono / P&L por tese / recebíveis (Onda 4).
- Contadores de fluxo (ganho/perda do dia) na tabela — deriváveis de
  `won_at`/`lost_at`, não se perdem.

## 6. Enterprise

Código 100% novo do Ramon, sem override de core → sem espelho em `enterprise/`.

## 7. Invariante do Organismo

Este órgão é pura memória: só lê estado interno e grava fato interno, nunca
fala com cliente. A regra "a IA prepara, o humano dispara" não é sequer tocada
aqui.

## 8. Verificação

- Spec do serviço: dado um conjunto de leads em etapas/teses conhecidas, o
  serviço grava as contagens e somas certas; re-rodar o mesmo dia não duplica.
- Spec do job: registra em `schedule_spec` (o fork valida `schedule.yml`).
- Smoke funcional (deploy): `rails runner` gera o dia 0; conferir linhas.
- Smoke visual (Eduardo): painel "Funil nos últimos 30 dias" aparece no
  RamonOverview com o dia de hoje.

## 9. Gates do Eduardo

Nenhum gate externo novo (sem token, sem conta de terceiro). Segue o regime do
fork: writing-plans por fatia → PR/CI verde → deploy só com OK explícito.
Migração nova → regenerar `db/schema.rb` via scratch DB na VPS.
