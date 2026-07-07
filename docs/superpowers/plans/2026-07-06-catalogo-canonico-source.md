# Catálogo Canônico de Source (canal) — Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development
> ou superpowers:executing-plans. Steps usam checkbox (`- [ ]`).

**Goal:** Normalizar a origem dos leads em um **canal canônico** (vocabulário fixo,
7 valores) para que atribuição/relatório parem de agrupar string livre. `source`
continua sendo o **detalhe livre** (qual campanha/LP/ad); `channel` é a dimensão
controlada. Onda 0 do plano "Organismo" — fundação de dados.

**Taxonomia (decidida pelo Eduardo, "por ponto de contato"):**
`meta_ads` "Meta Ads" · `landing_page` "Landing Page" · `instagram` "Instagram" ·
`google_seo` "Google/SEO" · `indicacao` "Indicação" · `whatsapp_direto`
"WhatsApp direto" · `outro` "Outro".

**Architecture:**
- `Ramon::SourceCatalog` (novo, `app/services/ramon/source_catalog.rb` ou
  `lib/ramon/`): `CHANNELS` (lista ordenada `[key, label]`) + `derive(source)` que
  classifica string livre por regra (fallback/backfill). **Não é tabela CRUD** — é
  constante de código (a regra de classificação vive no código de qualquer jeito;
  diferente de teses/benefícios que o Eduardo edita).
- Cada **caminho de escrita que sabe seu canal seta explicitamente** (LP →
  `landing_page`; referral Meta → `meta_ads`; manual → select do usuário). O
  `before_save` no Lead só **deriva se `channel` estiver blank** (root-cause: 1
  ponto cobre legado e qualquer caminho futuro que esqueça de setar).
- **Canal NÃO entra no snapshot do funil.** Canal é imutável → "leads por canal por
  dia" é sempre reconstruível de `leads.created_at + channel`. Só a *etapa* (que
  muda no tempo) precisa de foto diária. Corta migração e risco.

**Tech Stack:** Rails 7.1 (fork Chatwoot v4.15), Vue 3 `<script setup>`, Vuex,
Tailwind, RSpec, Vitest.

## Global Constraints
- Só `en.json`/`en.yml` de i18n editados à mão. Sem bare strings em template.
- Evento custom Vue SEMPRE camelCase. Action Vuex nunca desestrutura `state` cru
  (`state: moduleState`).
- Rubocop: `ENV.fetch`, 150 col. RSpec: máx 7 expectations/exemplo. `create(:account)`
  seeda o funil.
- `Lead` tem `default_scope order(...)` — `.last` NÃO é o mais recente; `DISTINCT`
  exige `reorder(nil)`.
- Tailwind only, sem CSS custom/scoped/inline.
- `db/schema.rb` NUNCA à mão — regenerado via scratch DB na VPS (Task 5).
- Checar `enterprise/` para qualquer core tocado (aqui: leads/dashboard são OSS).
- PR title = Conventional Commits. Ex.: `feat: catalogo canonico de source (canal)`.
- CI é o juiz. Verificação: `gh pr view N --json statusCheckRollup` filtrando
  conclusion != SUCCESS.

---

### Task 1: Backend núcleo — SourceCatalog, migração+backfill, Lead, serialização, params

**Files:**
- Create: `app/services/ramon/source_catalog.rb`
- Create: `db/migrate/20260706160001_add_channel_to_leads.rb`
- Modify: `app/models/lead.rb` (before_save fallback; `push_event_data` ~:43; params fica no controller)
- Modify: `app/controllers/api/v1/accounts/leads_controller.rb` (`permitted_params` ~:128 — add `:channel`)
- Modify: `app/views/api/v1/accounts/leads/_lead.json.jbuilder` (add `channel`)
- Modify: `app/views/api/v1/accounts/ramon_dashboard/_lead.json.jbuilder` (se existir; add `channel`)

**Interfaces / Produces:**
- `Ramon::SourceCatalog::CHANNELS` = array ordenado de `{ key:, label: }` (7 itens).
  `Ramon::SourceCatalog.labels` (hash key→label). `Ramon::SourceCatalog.valid?(key)`.
  `Ramon::SourceCatalog.derive(source)` → key ou `nil`, regras (case-insensitive,
  primeira que casar):
  - `/\Aanuncio-meta/` → `meta_ads`
  - `/indica/` → `indicacao`
  - `/instagram|\big\b/` → `instagram`
  - `/google|\bseo\b/` → `google_seo`
  - senão `nil` (fica "Outro"/não classificado).
- Coluna `leads.channel :string` (null, **index**). Migração faz backfill em SQL:
  `\Aanuncio-meta` → `meta_ads`; `custom_attributes ? 'utm'` (jsonb tem chave utm) →
  `landing_page`; keyword match indicacao/instagram/google como no derive; resto
  `outro`. (Backfill roda com `update_all`, sem callbacks.)
- `Lead` ganha `before_save :assign_channel` → `self.channel = Ramon::SourceCatalog.derive(source) || 'outro' if channel.blank?`. Broadcast/`push_event_data` inclui `channel`.
- `channel` nos dois jbuilders + strong params.

- [ ] Step 1: `Ramon::SourceCatalog` com CHANNELS + derive + helpers. Módulo compacto.
- [ ] Step 2: Migração add coluna+index + backfill SQL idempotente.
- [ ] Step 3: `before_save :assign_channel` no Lead (só se blank) + `channel` no push_event_data.
- [ ] Step 4: `channel` em strong params + nos jbuilders.
- [ ] Step 5 (spec, o mínimo): `spec/services/ramon/source_catalog_spec.rb` cobrindo derive (meta/indicacao/instagram/google/nil) e um caso de `assign_channel` no `spec/models/lead_spec.rb` (manual seta vence; blank deriva).

### Task 2: Caminhos de escrita setam canal autoritativo

**Files:**
- Modify: `app/controllers/public/api/v1/ramon_leads_controller.rb` (`create_lead` ~:67-75 — `channel: 'landing_page'`)
- Modify: `app/listeners/ramon_lead_listener.rb` (onde grava source `anuncio-meta` ~:38 — setar `channel: 'meta_ads'` no mesmo update)

**Interfaces:** lead de LP nasce `channel='landing_page'` (mesmo com utm pago — regra
do Eduardo: quem entra pela LP é Landing Page); lead de referral Meta nasce
`meta_ads`. Como setam explícito, o `before_save` não sobrescreve.

- [ ] Step 1: LP endpoint seta channel.
- [ ] Step 2: Listener Meta seta channel junto do source (respeitar o guard `source.blank?` existente — se já tinha source de LP, não mexe).

### Task 3: Leitura/relatório por canal

**Files:**
- Modify: `app/controllers/api/v1/accounts/ramon_dashboard_controller.rb` (`created_by_source` ~:96-100 → adicionar `created_by_channel` = `.group(:channel).count` mapeado p/ labels; manter created_by_source como detalhe OU trocar — decidir: **trocar** created_by_source por created_by_channel na resposta, source vira detalhe secundário se precisar)
- Modify: `app/controllers/api/v1/accounts/lead_config_controller.rb` (~:11 — servir `channels` = catálogo fixo, além do `sources` DISTINCT que pode ficar p/ autocomplete do detalhe)

**Interfaces:** `ramon_dashboard` retorna `created_by_channel: [{ key, label, count }]`
ordenado pelo CHANNELS. `lead_config` retorna `channels: CHANNELS`.

- [ ] Step 1: dashboard agrupa por channel com labels.
- [ ] Step 2: lead_config serve o catálogo fixo.

### Task 4: Frontend — select manual, filtro, exibição, CSV

**Files:**
- Modify: `app/javascript/dashboard/store/modules/leadConfig.js` (guardar `channels`; getter `getChannels`)
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/pages/kanban/NewLeadModal.vue` (~:178-185 — trocar input livre de source? NÃO: manter source livre como detalhe e **adicionar** `<select>` de canal)
- Modify: `.../ramon/.../lead/LeadFields.vue` (~:428-434 — add `<select>` de canal read/write; source segue livre)
- Modify: `.../ramon/.../kanban/KanbanFilters.vue` (~:99-103 — filtro por canal, além do de source)
- Modify: `.../ramon/pages/CommandCenter.vue` (~:322-333 — "criados por origem" passa a mostrar canal+label)
- Modify: `.../ramon/helpers/leadsCsv.js` (~:11 — add coluna `canal` = label do channel; manter `origem`=source)
- i18n: `en.json` (labels de UI: "Canal", etc.) — sem bare string.

**Interfaces:** canal é `<select>` das 7 opções (label PT vindo do store); no filtro é
igualdade exata por key; CSV ganha coluna `canal`.

- [ ] Step 1: store channels + getter.
- [ ] Step 2: select de canal em NewLeadModal e LeadFields (camelCase events, PascalCase).
- [ ] Step 3: filtro por canal no Kanban.
- [ ] Step 4: CommandCenter exibe canal; CSV ganha coluna.

### Task 5 (orquestrador, NÃO subagente): schema.rb + PR + CI

- [ ] Regenerar `db/schema.rb` via scratch DB na VPS (procedimento do repo — workflow
      temporário do Actions OU scratch DB; ver lição em [[pacote-especialista-crm]]).
- [ ] `pnpm eslint` / `rubocop -a` onde possível; abrir PR (`--body-file`); CI 100%
      verde por `statusCheckRollup`.
- [ ] Deploy = gate do Eduardo (migração `rails db:migrate` ANTES da imagem, pois há
      backfill). Smoke: criar lead manual escolhendo canal → aparece na gaveta/filtro;
      dashboard "criados por canal" agrupa certo.

## Notas
- `source` NUNCA é apagado — vira o detalhe. Nenhuma tela perde o campo livre.
- Legado ambíguo (manual antigo sem utm) cai em `outro`; Eduardo reclassifica pelo
  select. Aceitável (fatia de fundação, não de limpeza retroativa perfeita).
