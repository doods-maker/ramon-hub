# F2.1a — Teses & Playbooks nativos — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Teses (playbooks de venda) nativas no fork: tabelas + seed das 5 teses de incapacidade, CRUD com tela "Playbooks" no mundo Intranet, seletor de tese no painel do lead e aba "Playbook" de consulta na conversa.

**Architecture:** Réplica dos padrões da Fase 2A (lead_stages/benefit_types): migração única + seed idempotente por conta via service, API fina com Pundit, módulo Vuex próprio (`theses`), tela mestre-detalhe no mundo Intranet, aba nova no LeadConversationPanel. Realtime propaga `thesis_id/thesis_name` de graça via `push_event_data` + jbuilder.

**Tech Stack:** Rails 7 (fork Chatwoot v4.15.1), Vue 3 `<script setup>` + Vuex, RSpec/Vitest. Sem ambiente local — CI valida; schema.rb regenerado contra scratch DB na VPS (passo do CONTROLADOR, não do subagente).

## Global Constraints

- Fork merge-safe: novos arquivos em namespace `ramon/` quando frontend; edições de core mínimas, TODAS registradas em `docs/FORK-PONTOS-DE-REGISTRO.md`; NUNCA tocar `enterprise/`.
- Leitura obrigatória antes de cada task: o relatório de padrões `C:\Users\dudsl\AppData\Local\Temp\claude\C--Users-dudsl-RAdvogados\c9a90c7f-bed0-40cb-bcaf-28953ef6e21c\scratchpad\f21a-padroes-fork.md` (seções citadas em cada task) — ele tem arquivo:linha dos padrões a imitar.
- `create(:account)` seeda funil E (após Task 1) teses — specs não criam tese com nome seedado.
- `Lead` default_scope `order(:lead_stage_id, :position, :id)`; Rubocop `ENV.fetch`/150 chars; RSpec máx 7 expectations; eventos Vue camelCase; actions Vuex não desestruturar `state` cru (`state: moduleState`).
- i18n: só `en` + `pt_BR` (ramon.json e, se necessário, en.yml/pt_BR.yml).
- Commits Conventional Commits PT-BR, sem referência a Claude; `git add <paths>` específicos.
- Verificação de CI: SEMPRE rollup completo (`gh pr view N --json statusCheckRollup`).

## Decisões de produto travadas (Eduardo 03/07)

- Delete de tese com leads vinculados: PERMITIDO — `leads.thesis_id` vira NULL (FK `on_delete: :nullify`), igual à intranet.
- Seed = as 5 teses de incapacidade portadas VERBATIM de `C:\Users\dudsl\RAdvogados\comercial\projetos\intranet-ramon\supabase\12_playbook_seed_incapacidade.sql`. Os rascunhos novos (salário-maternidade etc.) NÃO entram neste plano — aguardam revisão do Eduardo e entrarão pela própria UI ou seed posterior.
- Seções fixas do item: `abertura, apresentacao, qualificacao, objecao, documento` (enum string, mesmos nomes da intranet para facilitar F3).
- Aba "Playbook" da conversa mostra SÓ `qualificacao/objecao/documento` (consulta ao vivo), como a intranet fazia.

## Estrutura de arquivos

| Arquivo | Ação |
|---|---|
| `db/migrate/2026070XXXXXXX_create_ramon_theses.rb` | Criar (tabelas + coluna + seed backfill) |
| `db/schema.rb` | Regenerar (CONTROLADOR, scratch DB na VPS) |
| `app/models/thesis.rb`, `app/models/thesis_item.rb` | Criar |
| `app/models/lead.rb` | Modificar (belongs_to, push_event_data, activities, jbuilder abaixo) |
| `app/models/account.rb` | Modificar (has_many :theses) |
| `app/services/leads/seed_default_config_service.rb` | Modificar (+seed_theses) |
| `db/seeds/ramon/theses_seed.yml` | Criar (conteúdo das 5 teses) |
| `app/controllers/api/v1/accounts/{theses,thesis_items}_controller.rb` | Criar |
| `app/policies/{thesis,thesis_item}_policy.rb` | Criar |
| `app/views/api/v1/accounts/theses/*.json.jbuilder` | Criar |
| `config/routes.rb` | Modificar (resources :theses + nested items) |
| `app/controllers/api/v1/accounts/leads_controller.rb` | Modificar (permitted_params +thesis_id) |
| `app/views/api/v1/accounts/leads/_lead.json.jbuilder` | Modificar (+thesis_id/thesis_name) |
| `app/javascript/dashboard/api/theses.js` | Criar |
| `app/javascript/dashboard/store/modules/theses.js` (+specs) | Criar |
| `app/javascript/dashboard/store/{index.js,mutation-types.js}` | Modificar |
| `.../ramon/pages/Playbooks.vue` | Criar (mestre-detalhe) |
| `.../ramon/ramon.routes.js`, `.../ramon/components/IntranetSidebar.vue` | Modificar |
| `.../ramon/components/lead/LeadFields.vue` | Modificar (seletor de tese) |
| `.../ramon/components/conversation/LeadConversationPanel.vue` | Modificar (aba) |
| `.../ramon/components/conversation/LeadPlaybook.vue` | Criar |
| `i18n/locale/{en,pt_BR}/ramon.json` | Modificar |
| `docs/FORK-PONTOS-DE-REGISTRO.md` | Modificar |

---

### Task 1: Migração, models e seed

**Files:** os 8 primeiros da tabela acima. **Test:** `spec/models/thesis_spec.rb`, `spec/services/leads/seed_default_config_service_spec.rb` (estender se existir; senão criar).

**Interfaces produzidas:** `Thesis(account_id, name, description, area, active:bool default true, position:int)`; `ThesisItem(thesis_id, section:string in 5 seções, title, content, position)`; `Lead#thesis` (optional); `Leads::SeedDefaultConfigService#perform` agora também semeia teses (idempotente por `find_or_create_by!(account:, name:)`).

- [ ] **Step 1: Specs que falham.** Model spec: validações (name presence + uniqueness por conta; section inclusion), associações, `dependent: :destroy` de items, nullify em leads. Seed spec: `create(:account)` → `account.theses.count == 5` e itens > 60; rodar 2x não duplica. Siga o estilo de specs existentes de LeadStage (procure em `spec/models/`). Fábricas novas em `spec/factories/{theses,thesis_items}.rb` no padrão de `spec/factories/leads.rb`.
- [ ] **Step 2: Migração** — padrão EXATO de `db/migrate/20260628000001_create_ramon_leads.rb` (relatório §1): cria `theses` (references account null:false + name/description/area/active default true/position int default 0 + index único [:account_id, :name]) e `thesis_items` (references thesis null:false FK cascade + section/title/content/position + index [:thesis_id, :section, :position]); `add_reference :leads, :thesis, null: true, foreign_key: { on_delete: :nullify }`; no `reversible dir.up`, `Account.find_each { |a| Leads::SeedDefaultConfigService.new(a).perform }`.
- [ ] **Step 3: Models** — `Thesis`: belongs_to :account, has_many :thesis_items (-> { order(:position) }, dependent: :destroy), has_many :leads (dependent: :nullify), validates name presence+uniqueness escopo conta, default_scope order(:position). `ThesisItem`: belongs_to :thesis, SECTIONS = %w[abertura apresentacao qualificacao objecao documento], validates section inclusion + content presence. `Lead`: `belongs_to :thesis, optional: true`; `push_event_data` ganha `thesis_id:` e `thesis_name: thesis&.name` (lead.rb:21-41); `record_change_activities` (lead.rb:57-63) ganha entrada para `thesis_id` no mesmo padrão. `Account`: `has_many :theses, dependent: :destroy_async` junto dos has_many ramon existentes.
- [ ] **Step 4: Seed** — extrair TODO o conteúdo (5 teses, ~65 itens, texto VERBATIM) de `intranet-ramon\supabase\12_playbook_seed_incapacidade.sql` para `db/seeds/ramon/theses_seed.yml` (estrutura: lista de teses com name/description/area/position e items com section/title/content/position). `seed_default_config_service.rb` ganha `seed_theses` (chamado no `perform`): lê o YAML (`YAML.safe_load_file(Rails.root.join('db/seeds/ramon/theses_seed.yml'))`), `find_or_create_by!` tese por nome e itens por (section, title) — idempotente.
- [ ] **Step 5: Commit** — `feat(ramon): teses e itens de playbook nativos com seed das 5 teses de incapacidade`.

### Task 2: API REST + policies + jbuilder

**Files:** controllers/policies/jbuilder/routes da tabela + `leads_controller` + `_lead.json.jbuilder`. **Test:** `spec/requests/api/v1/accounts/theses_controller_spec.rb` (+ thesis_items).

**Interfaces:** `GET/POST /api/v1/accounts/:id/theses`, `GET/PATCH/DELETE /theses/:id`, `POST /theses/reorder`; nested `POST/PATCH/DELETE /theses/:thesis_id/thesis_items` + `POST .../thesis_items/reorder`. `GET /theses/:id` inclui items agrupáveis (array ordenado com section). Policies: leitura (index/show) admin+agent (painel do lead consulta); escrita só administrator — padrão misto LeadPolicy/LeadStagePolicy (relatório §3).

- [ ] **Step 1: Request specs que falham** (agent lê mas não cria; admin CRUD completo; reorder transacional; delete de tese anula thesis_id do lead — máx 7 expectations/exemplo; padrão do spec de lead_stages se existir, senão leads).
- [ ] **Step 2: Implementar** seguindo `lead_stages_controller.rb` (create/update com next_position, reorder em transaction — relatório §3) e jbuilder no padrão `leads/_lead.json.jbuilder`. `leads_controller#permitted_params` ganha `:thesis_id`; `_lead.json.jbuilder` ganha `thesis_id`/`thesis_name`.
- [ ] **Step 3: Commit** — `feat(ramon): API de teses e itens de playbook`.

### Task 3: Vuex + API client

**Files:** `api/theses.js`, `store/modules/theses.js`, `store/modules/specs/theses/*` , `store/index.js`, `mutation-types.js`.

**Interfaces:** módulo `theses` — state `{ records: [], uiFlags }`; getters `getTheses` (ordenado por position), `getUIFlags`; actions `get`, `create/update/delete` (tese), `reorder`, `createItem/updateItem/deleteItem/reorderItems(thesisId, ...)`; a tese em `records` carrega `items` quando vier do `show`. Molde: `leadConfig.js` (relatório §4) com `bySortedPosition`. Mutations novas em `mutation-types.js`: `SET_THESES, ADD_THESIS, EDIT_THESIS, DELETE_THESIS, SET_THESES_UI_FLAG`.

- [ ] **Step 1: Specs de store que falham** (padrão `store/modules/specs/leads/actions.spec.js`), **Step 2: implementar**, **Step 3: lint se disponível**, **Step 4: Commit** — `feat(ramon): módulo Vuex de teses`.

### Task 4: Painel do lead — seletor de tese + aba Playbook

**Files:** `LeadFields.vue`, `LeadConversationPanel.vue`, novo `LeadPlaybook.vue`, `i18n/locale/{en,pt_BR}/ramon.json`.

- [ ] **Step 1:** Seletor de tese em `LeadFields.vue` replicando EXATAMENTE o bloco `benefit_type_id` (linhas 104-142; relatório §6): `useMapGetter('theses/getTheses')`, `<select>` nativo, `@change` → `saveSelect('thesis_id', ...)`, i18n `RAMON.DRAWER.THESIS`. Garantir dispatch de `theses/get` no `onMounted` do `LeadConversationPanel` (uma vez, guard por records.length).
- [ ] **Step 2:** Nova aba `playbook` no `LeadConversationPanel.vue` no padrão exato da aba histórico (`activeTab`, botão no header, `v-else-if`); componente `LeadPlaybook.vue` recebe `:lead`, lê a tese do lead nos getters, mostra SÓ seções qualificacao/objecao/documento agrupadas (título + conteúdo, botão copiar por item — reuse padrão de copiar existente no fork se houver; senão `navigator.clipboard.writeText` + feedback). Sem tese → empty state com instrução ("Escolha a tese no Resumo"). i18n `RAMON.LEAD_PANEL.TABS.PLAYBOOK` + bloco `RAMON.PLAYBOOK.*`.
- [ ] **Step 3:** Spec Vitest do `LeadPlaybook.vue` (renderiza seções, empty state) no padrão dos specs de kanban. **Step 4: Commit** — `feat(ramon): tese e playbook de consulta no painel do lead`.

### Task 5: Tela Playbooks no mundo Intranet

**Files:** `pages/Playbooks.vue`, `ramon.routes.js`, `IntranetSidebar.vue`, `ramon.json` (en/pt_BR).

- [ ] **Step 1:** Rota `ramon_playbooks` (path `accounts/:accountId/ramon/playbooks`, meta `{ permissions: ['administrator'], world: 'intranet' }` — padrão ramon_funil_config, relatório §5). Item "Playbooks" na seção COMERCIAL do `IntranetSidebar.vue` (icone `i-lucide-book-open`, chave `RAMON.NAV.PLAYBOOKS`).
- [ ] **Step 2:** `Playbooks.vue` mestre-detalhe: coluna esquerda = lista de teses (nome, badge ativo/inativo, add/remover/reordenar — data-testids `playbooks-*`); direita = tese selecionada com campos editáveis (nome/descrição/ativo) e itens agrupados por seção (5 seções com rótulos PT), add/editar/remover item inline (input título + textarea conteúdo). Tudo Tailwind, sem CSS custom, Composition API. CRUD via módulo `theses`.
- [ ] **Step 3:** Spec Vitest básico (renderiza lista, dispara create). **Step 4: Commit** — `feat(ramon): tela Playbooks (gestão de teses) no mundo Intranet`.

### Task 6: Registro de fork + PR

- [ ] Registrar em `docs/FORK-PONTOS-DE-REGISTRO.md` as edições de core: `routes.rb`, `store/index.js`, `mutation-types.js`, `leads_controller`, `_lead.json.jbuilder`, `lead.rb`, `account.rb`, `seed_default_config_service.rb` (+ arquivos novos na tabela própria). Commit `docs: registra pontos de fork das teses/playbooks`.

## Pós-CI (CONTROLADOR + Eduardo)

1. Schema regen: rodar a migração num scratch DB na VPS e commitar `db/schema.rb` regenerado ANTES do merge (lição registrada; sem isso o CI quebra em `db:schema:load`). **⚠️ Este passo é meu (controlador), via SSH, com scratch DB — nunca no banco de produção.**
2. PR → CI rollup completo → merge (Eduardo) → deploy com `db:migrate` → smoke funcional real (criar tese pela UI, escolher tese num lead, ver playbook na aba, conferir realtime) → smoke visual Eduardo.

## Fora de escopo (explícito)

Triagem/kit (F2.1b/c), rascunhos de playbook novos (aguardam revisão), import dos dados vivos do Supabase (F3), reorder drag&drop visual (botões bastam na v1).
