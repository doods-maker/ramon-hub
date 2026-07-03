# Fork Ramon Hub — Pontos de registro tocados no core

> Toda edição em arquivo que **já existe no Chatwoot upstream** entra AQUI.
> Antes de cada rebase numa nova release, conferir esta lista é a checagem rápida.
> Regra de ouro: **adicionar (namespace `ramon/`), quase nunca editar.** Nunca tocar `enterprise/`.

## Base do fork
- Upstream: `chatwoot/chatwoot`
- Versão fixada: **v4.15.1** (commit `97bb8ec`)
- Branch de trabalho: `ramon`
- Imagem publicada: `ghcr.io/<owner>/ramon-hub:v4.15.1-ramon`

## Arquivos do core editados (manter mínimo)
| Arquivo | Linhas/trecho | Motivo | Fase |
|---|---|---|---|
| `app/javascript/dashboard/assets/scss/_woot.scss` | +1 `@import 'ramon-brand'` após `next-colors` | rebrand fork-safe | 1A |
| `app/javascript/dashboard/helper/themeHelper.js` | default `'auto'` → `'dark'` (linha 6) | marca é dark por padrão | 1A |
| `tailwind.config.js` | +chave `cormorant` em `theme.fontFamily` | fonte de títulos | 1A |
| `app/models/account.rb` | `has_many :benefit_types/:lead_priorities/:lead_stages/:leads` (após `:labels`) + `after_create :seed_lead_config` + método privado `seed_lead_config` | associações + seed automático do funil de leads | 2A |
| `config/routes.rb` | `resource :lead_config, only: [:show]` dentro do bloco `namespace :accounts do` (ao lado de `resources :labels`) | endpoint de leitura da config do funil | 2A |
| `config/routes.rb` | `resources :leads` dentro do bloco `namespace :accounts do` (após `resource :lead_config`) | API CRUD de leads (index/show/create/update/destroy) | 2A |
| `config/routes.rb` | collection route `for_conversation` em `leads` | painel do lead na conversa acha-ou-cria | 1a |
| `app/javascript/dashboard/components/widgets/conversation/ConversationSidebar.vue` | renderiza `LeadConversationPanel` no lugar do `ContactPanel` quando não-descartado (`discardedConversations` Set por conversationId) + largura ~metade (`md:w-[420px] 2xl:w-[480px]` vs `md:w-[320px] 2xl:w-[360px]`) | painel do lead na conversa | 1a |
| `app/javascript/dashboard/store/index.js` | `import leads/leadConfig` após `labels`; `leads, leadConfig,` no objeto `modules` | registra módulos Vuex do funil de leads | 2A |
| `app/javascript/dashboard/store/mutation-types.js` | bloco `// Ramon — Leads` (SET_LEAD_UI_FLAG, SET_LEADS, ADD_LEAD, EDIT_LEAD, DELETE_LEAD, SET_LEAD_CONFIG) após bloco Labels | mutation types dos módulos leads/leadConfig | 2A |
| `app/javascript/dashboard/routes/dashboard/dashboard.routes.js` | import `ramonRoutes` + `...ramonRoutes` no array children | seção Intranet | 1A |
| `app/javascript/dashboard/components-next/sidebar/Sidebar.vue` | item Ramon do `menuItems` **revertido** na 1B (trilho substitui o item) | o WorldRail faz a troca de mundo agora | 1B |
| `app/javascript/dashboard/i18n/locale/en/settings.json` | +`"RAMON": "Intranet"` dentro de `"SIDEBAR"` | i18n sidebar (inofensivo, mantido) | 1A |
| `app/javascript/dashboard/i18n/locale/pt_BR/settings.json` | +`"RAMON": "Intranet"` dentro de `"SIDEBAR"` | i18n sidebar (inofensivo, mantido) | 1A |
| `app/javascript/dashboard/i18n/locale/en/index.js` | +import e spread de `ramon.json` | registra locale ramon | 1A |
| `app/javascript/dashboard/i18n/locale/pt_BR/index.js` | +import e spread de `ramon.json` | registra locale ramon | 1A |
| `app/javascript/dashboard/routes/dashboard/Dashboard.vue` | +imports `WorldRail`/`IntranetSidebar`; +computed `isIntranetWorld`; template: `WorldRail` antes de `NextSidebar` (v-if) + `IntranetSidebar` (v-else) | trilho de dois níveis | 1B |
| `app/javascript/dashboard/components-next/sidebar/Sidebar.vue` | item `KanbanBoard` no `menuItems` inserido após `Conversation` (icon `i-lucide-columns-3`, rota `kanban_board`) — ordem: Inbox → Conversation → Kanban Board | Kanban Board no mundo Conversas | 2A |
| `app/javascript/dashboard/routes/dashboard/conversation/conversation.routes.js` | +rota `{ path: frontendURL('accounts/:accountId/kanban'), name: 'kanban_board', meta: { permissions: CONVERSATION_PERMISSIONS }, component: () => import('./KanbanView.vue') }` | Kanban Board no mundo Conversas | 2A |
| `app/javascript/dashboard/i18n/locale/pt_BR/settings.json` | +`"KANBAN_BOARD": "Kanban Board"` dentro de `"SIDEBAR"` | rótulo do item de menu | 2A |
| `app/javascript/dashboard/i18n/locale/en/settings.json` | +`"KANBAN_BOARD": "Kanban Board"` dentro de `"SIDEBAR"` | rótulo do item de menu | 2A |
| `lib/events/types.rb` | +`LEAD_CREATED`/`LEAD_UPDATED` (bloco `# Ramon — leads` antes de `# contact events`) | constantes de evento para o canal realtime de leads | 2B |
| `app/listeners/action_cable_listener.rb` | +`lead_created`/`lead_updated` após `contact_merged` — broadcast account-wide com `lead.push_event_data` | realtime de leads via ActionCable | 2B |
| `app/dispatchers/async_dispatcher.rb` | +`RamonLeadListener.instance` no array `listeners` (após `WebhookListener.instance`) | registra listener de auto-criação de leads | 2B |
| `app/controllers/api/v1/accounts/inboxes_controller.rb` | `:auto_create_lead` adicionado ao array de `inbox_attributes` (método `inbox_attributes`, ~linha 160) | expõe parâmetro para o update da inbox | 2D |
| `app/models/account.rb` | +`has_many :lead_activities, dependent: :destroy_async` (junto de `:lead_priorities`/`:lead_stages`/`:leads`) | timeline de atividades do lead | 1b-i |
| `app/models/lead.rb` | +`has_many :lead_activities, dependent: :destroy_async` (junto das demais associações) | timeline de atividades do lead | 1b-i |
| `app/models/lead.rb` | +callbacks `after_create_commit :record_created_activity` / `after_update_commit :record_change_activities` + métodos privados `record_created_activity`/`record_change_activities`/`record_change` | grava `lead_activities` (com autor via `Current.user`) na criação e em mudanças de `lead_stage_id`/`sdr_id`/`closer_id`/`lead_priority_id`/`value` | 1b-i |
| `config/routes.rb` | `resources :activities, only: [:index], controller: 'lead_activities'` dentro do bloco `resources :leads` (após `collection { post :for_conversation }`) | endpoint read-only de timeline de atividades do lead | 1b-i |
| `app/views/api/v1/models/_inbox.json.jbuilder` | +`json.auto_create_lead resource.auto_create_lead` após `json.business_name` (~linha 21) | serializa flag para o frontend | 2D |
| `app/models/account.rb` | +`has_many :lead_notes, dependent: :destroy_async` (junto de `:lead_activities`, alfabético) | notas discretas do lead | 1b-ii |
| `app/models/lead.rb` | +`has_many :lead_notes, dependent: :destroy_async` (junto de `:lead_activities`) | notas discretas do lead | 1b-ii |
| `app/javascript/dashboard/routes/dashboard/settings/inbox/Settings.vue` | +`autoCreateLead` em `data()`, `syncInboxData()`, payload de `updateInbox()` e template (`SettingsToggleSection` sem `v-if`) | toggle UI da flag em todas as inboxes | 2D |
| `app/javascript/dashboard/i18n/locale/en/inboxMgmt.json` e `pt_BR/inboxMgmt.json` | +`AUTO_CREATE_LEAD.LABEL`/`SUB_TEXT` dentro de `SETTINGS_POPUP` | i18n do toggle | 2D |
| `app/views/api/v1/accounts/leads/_lead.json.jbuilder` | -`json.notes lead.notes` (removida, coluna dropada; notas viraram `lead_notes`) | fim do blob `leads.notes` | 1b-ii |
| `app/controllers/api/v1/accounts/leads_controller.rb` | -`:notes` removido de `permitted_params` | fim do blob `leads.notes` | 1b-ii |
| `config/routes.rb` | `post 'ramon_leads/:capture_token'` no namespace `public/api/v1` (ao lado de `csat_survey`) | captação de leads das landing pages | A-leads |
| `config/initializers/rack_attack.rb` | throttle `public/ramon_leads` (5 POST/min por IP) | anti-abuso do endpoint público | A-leads |
| `app/models/notification.rb` | `ramon_lead_created: 9` no enum NOTIFICATION_TYPES + título/corpo em `push_message_title`/`push_message_body` (branch para `Lead`, não `Conversation`) | notificação nativa do tipo lead | A-notif |
| `config/locales/en.yml` | +`ramon_lead_created: 'New lead from landing page: %{name}'` no bloco `notifications.notification_title` | título da notificação (inglês) | A-notif |
| `config/locales/pt_BR.yml` | +`ramon_lead_created: 'Novo lead da landing page: %{name}'` no bloco `notifications.notification_title` | título da notificação (português) | A-notif |
| `app/javascript/dashboard/routes/dashboard/notifications/components/NotificationTable.vue` | `meta.assignee` → `meta?.assignee` (safe navigation operator) | guarda `meta?` para tipo Lead sem `assignee` | A-notif |
| `app/javascript/dashboard/routes/dashboard/notifications/components/NotificationsView.vue` | +branch `if (notificationType === 'ramon_lead_created')` que navega `name: 'kanban_board'` | rota para o Kanban Board ao clicar na notificação | A-notif |
| `app/javascript/dashboard/i18n/locale/en/generalSettings.json` | +`"ramon_lead_created": "New lead (LP)"` no bloco `NOTIFICATIONS_PAGE.TYPE_LABEL` | rótulo do tipo de notificação (inglês) | A-notif |
| `app/javascript/dashboard/i18n/locale/pt_BR/generalSettings.json` | +`"ramon_lead_created": "Lead novo (LP)"` no bloco `NOTIFICATIONS_PAGE.TYPE_LABEL` | rótulo do tipo de notificação (português) | A-notif |
| `config/routes.rb` | `resources :theses do ... resources :thesis_items ... end` dentro do bloco `namespace :accounts do` (após `lead_stages`) | API CRUD de teses e itens de playbook | F2.1a |
| `app/models/account.rb` | +`has_many :theses, dependent: :destroy_async` (junto das demais associações) | associação teses → account | F2.1a |
| `app/models/lead.rb` | +`belongs_to :thesis, optional: true` + `thesis_id` em `push_event_data` + `thesis_name` em `push_event_data` + `record_change('thesis_id', 'thesis_changed')` | tese no lead; eventos realtime enriquecidos | F2.1a |
| `app/services/leads/seed_default_config_service.rb` | +método `seed_theses` chamado em `seed_default_config`; seed das 5 teses de incapacidade nativas | seed automático das 5 teses padrão | F2.1a |
| `app/controllers/api/v1/accounts/leads_controller.rb` | +`:thesis_id` em `permitted_params` | parâmetro thesis_id aceitável no update de lead | F2.1a |
| `app/views/api/v1/accounts/leads/_lead.json.jbuilder` | +`json.thesis_id lead.thesis_id` e `json.thesis_name lead.thesis&.name` | serializa tese no lead (JSON) | F2.1a |
| `app/javascript/dashboard/store/index.js` | +import e spread de `modules/theses` (após `leadConfig`) | registra módulo Vuex de teses | F2.1a |
| `app/javascript/dashboard/store/mutation-types.js` | +bloco `// Ramon — Teses` com 5 tipos (SET_THESES_UI_FLAG, SET_THESES, ADD_THESIS, EDIT_THESIS, DELETE_THESIS) | mutation types do módulo teses | F2.1a |
| `app/javascript/dashboard/i18n/locale/en/ramon.json` | +blocos/strings para Playbooks (tela, labels, erros, placeholders) | i18n inglês para UI de teses e playbooks | F2.1a |
| `app/javascript/dashboard/i18n/locale/pt_BR/ramon.json` | +blocos/strings para Playbooks (tela, labels, erros, placeholders) | i18n português para UI de teses e playbooks | F2.1a |
| `config/routes.rb` | `resources :tasks, only: [:index, :create, :update, :destroy], controller: 'lead_tasks' do member { post :complete } end` dentro do bloco `resources :leads` (após `resources :notes`) | API de tarefas (próxima ação) aninhada ao lead + rota member `complete` | PR-A t2 |
| `config/routes.rb` | `resources :lead_tasks, only: [:index], as: :account_lead_tasks` no nível da conta (após o bloco `resources :leads`; `as:` evita colisão de named route com o nested `tasks` do lead) | coleção de tarefas da conta com `scope=open\|overdue\|today` (agenda) | PR-A t2 |
| `app/models/lead.rb` | +`inverse_of: :lead` no `has_many :lead_tasks` | evita N+1 de `task.lead.name` no index escopado ao lead | PR-A t2 |

### Decisão: Tipo NÃO exposto em Perfil → Notificações

**`settings/profile/constants.js` intocado de propósito.** O novo tipo `ramon_lead_created` é **intencionalmente excluído** do toggles de e-mail e push no painel de configurações (Perfil → Notificações). Razão: `Lead` é um `primary_actor` diferente de `Conversation`, e as notificações push/e-mail do Chatwoot upstream esperam sempre `Conversation` (leem `primary_actor.display_id`, `.inbox.name`, `.messages`, etc.). Deixar o tipo exposto quebraria o envio de e-mail e push; mantém-se invisível no UI de propósito — o sino renderiza, clique navega ao Kanban Board (UI nativa nova), e a entrega limita-se a **realtime (ActionCable) no painel**.

## Arquivos NOVOS (namespace `ramon/` — não conflitam no rebase)
| Arquivo | Responsabilidade | Fase |
|---|---|---|
| `.github/workflows/ramon-publish.yml` | build + publish da imagem do fork no GHCR | 0 |
| `docs/FORK-PONTOS-DE-REGISTRO.md` | esta lista | 0 |
| `app/javascript/dashboard/assets/scss/_ramon-brand.scss` | tokens de cor bronze (dark) e creme/bronze (light) | 1A |
| `app/javascript/dashboard/routes/dashboard/ramon/ramon.routes.js` | rotas da seção Intranet (inclui `ramon_index` + `ramon_external_shortcuts`) | 1A/1B |
| `app/javascript/dashboard/routes/dashboard/ramon/pages/RamonOverview.vue` | Centro de Comando (shell placeholder) | 1A |
| `app/javascript/dashboard/routes/dashboard/ramon/pages/ExternalShortcuts.vue` | tela de gestão de atalhos externos (ui_settings) | 1B |
| `app/javascript/dashboard/routes/dashboard/ramon/externalShortcutsDefaults.js` | atalhos padrão (rail + tela) | 1B |
| `app/javascript/dashboard/routes/dashboard/ramon/components/WorldRail.vue` | rail externo 78px (mundos + externos + perfil) | 1B |
| `app/javascript/dashboard/routes/dashboard/ramon/components/IntranetSidebar.vue` | sidebar secundária do mundo Intranet | 1B |
| `app/javascript/dashboard/i18n/locale/en/ramon.json` | textos das telas ramon (inglês) — blocos OVERVIEW, NAV, RAIL, SHORTCUTS | 1A/1B |
| `app/javascript/dashboard/i18n/locale/pt_BR/ramon.json` | textos das telas ramon (português) — blocos OVERVIEW, NAV, RAIL, SHORTCUTS | 1A/1B |
| `public/brand-assets/ramon-logo.jpeg` | logo do escritório (apontar via Super Admin) | 1A |
| `public/brand-assets/ramon-monogram.png` | monograma/favicon (apontar via Super Admin) | 1A |
| `app/javascript/dashboard/routes/dashboard/conversation/KanbanView.vue` | arquivo NOVO dentro de diretório core (não em `ramon/`) — wrapper que monta o `KanbanBoard` no mundo Conversas | 2A |
| `db/migrate/20260628000002_add_auto_create_lead_to_inboxes.rb` | migration: coluna `auto_create_lead` (boolean, default false) em `inboxes` | flag de auto-criação de lead por inbox | 2B |
| `app/listeners/ramon_lead_listener.rb` | listener de auto-criação de lead em `conversation_created`; dedup por contato | funil de leads automático | 2B |
| `spec/listeners/ramon_lead_listener_spec.rb` | specs: cria / inbox-off / dedup-relink | cobertura do RamonLeadListener | 2B |
| `db/migrate/20260701000001_create_lead_activities.rb` | migration: tabela `lead_activities` (account_id, lead_id, user_id opcional, kind, from_value, to_value, created_at; sem updated_at) | timeline de atividades do lead | 1b-i |
| `app/models/lead_activity.rb` | model `LeadActivity` — validação de `kind`, `default_scope` por `created_at` asc | timeline de atividades do lead | 1b-i |
| `spec/models/lead_activity_spec.rb` | specs: válido sem user, exige kind, belongs_to user opcional | cobertura do LeadActivity | 1b-i |
| `app/controllers/api/v1/accounts/lead_activities_controller.rb` | controller read-only `index` (fetch_lead + authorize via LeadPolicy#show?) | endpoint de timeline de atividades do lead | 1b-i |
| `app/policies/lead_activity_policy.rb` | policy com `index?` (evita `Pundit::NotDefinedError`) | autorização do endpoint de atividades | 1b-i |
| `app/views/api/v1/accounts/lead_activities/index.json.jbuilder` e `_lead_activity.json.jbuilder` | serialização `{ payload: [...] }` da timeline | resposta JSON do endpoint de atividades | 1b-i |
| `spec/controllers/api/v1/accounts/lead_activities_controller_spec.rb` | request spec: lista atividades em ordem cronológica, autor e valores | cobertura do endpoint de atividades | 1b-i |
| `db/migrate/20260701000003_create_lead_notes.rb` | migration: tabela `lead_notes` (account_id, lead_id, user_id opcional, body:text, timestamps) + índice `[lead_id, created_at]` | notas discretas do lead | 1b-ii |
| `app/models/lead_note.rb` | model `LeadNote` — validação de `body`, `default_scope` por `created_at` asc | notas discretas do lead | 1b-ii |
| `spec/models/lead_note_spec.rb` | specs: válido com lead+body, exige body, belongs_to user opcional | cobertura do LeadNote | 1b-ii |
| `config/routes.rb` | `resources :notes, only: [:index, :create], controller: 'lead_notes'` dentro do bloco `resources :leads` (após `resources :activities`) | endpoints index/create de notas discretas do lead | 1b-ii |
| `app/controllers/api/v1/accounts/lead_notes_controller.rb` | controller `index`/`create` (fetch_lead + authorize via LeadPolicy#show? em cada action, sem `check_authorization`) | endpoints de notas discretas do lead | 1b-ii |
| `app/policies/lead_note_policy.rb` | policy com `index?`/`create?` (defensiva, mesmo sem `check_authorization` declarado) | autorização do endpoint de notas | 1b-ii |
| `app/views/api/v1/accounts/lead_notes/index.json.jbuilder`, `_lead_note.json.jbuilder` e `create.json.jbuilder` | serialização `{ payload: [...] }` da listagem e da nota criada (render implícito) | resposta JSON do endpoint de notas | 1b-ii |
| `spec/controllers/api/v1/accounts/lead_notes_controller_spec.rb` | request spec: lista notas em ordem cronológica com autor; cria nota autorada pelo usuário atual | cobertura do endpoint de notas | 1b-ii |
| `db/migrate/20260701000004_backfill_lead_notes_from_blob.rb` | migration idempotente: copia `leads.notes` (blob) → 1 `LeadNote` por lead (user nil, `created_at = lead.created_at`); `down` no-op | migração do blob para notas discretas | 1b-ii |
| `db/migrate/20260701000005_remove_notes_from_leads.rb` | migration: `remove_column :leads, :notes, :text` | remoção definitiva do blob `leads.notes` | 1b-ii |
| `app/controllers/public/api/v1/ramon_leads_controller.rb` | endpoint público de captação: honeypot, token ENV (`RAMON_LEAD_CAPTURE_TOKEN` + `RAMON_LEAD_CAPTURE_ACCOUNT_ID`), contact find-or-create por telefone, dedup de lead aberto → nota | leads das LPs nascem no funil | A-leads |
| `spec/requests/public/api/v1/ramon_leads_controller_spec.rb` | request spec do endpoint (criação, honeypot, 401, 422, dedup, won/lost) | cobertura CI | A-leads |
| `db/migrate/20260703000001_create_ramon_theses.rb` | migration: tabelas `theses` (account_id, name, description, area, active, position) e `thesis_items` (thesis_id FK cascade, section, title, content, position) + `leads.thesis_id` (FK `on_delete: :nullify`) + backfill de seed via `Account.find_each` | teses (playbooks de venda) e itens | F2.1a |
| `app/models/thesis.rb` | `belongs_to :account`, `has_many :thesis_items` (ordenado, destroy) e `:leads` (nullify); name único por conta; default_scope por position | tese/playbook | F2.1a |
| `app/models/thesis_item.rb` | `belongs_to :thesis`; `SECTIONS = abertura/apresentacao/qualificacao/objecao/documento` (inclusion); content obrigatório; default_scope por position | item de playbook | F2.1a |
| `app/policies/thesis_policy.rb` | leitura (`index?`/`show?`) admin+agent; escrita (`create?`/`update?`/`destroy?`/`reorder?`) só administrator | autorização de teses | F2.1a |
| `app/policies/thesis_item_policy.rb` | escrita só administrator (leitura simbólica p/ simetria; itens só existem no show da tese) | autorização de itens | F2.1a |
| `app/controllers/api/v1/accounts/theses_controller.rb` | CRUD + `reorder` (transação, `ids` ordenados); index leve, show com `items`; escopo `Current.account.theses` | API de teses | F2.1a |
| `app/controllers/api/v1/accounts/thesis_items_controller.rb` | `create`/`update`/`destroy` + `reorder`, aninhado e escopado pela tese | API de itens | F2.1a |
| `app/views/api/v1/accounts/theses/{index,show}.json.jbuilder` | index: id/name/description/area/active/position (SEM items); show: idem + `items` (id/section/title/content/position) | JSON de teses | F2.1a |
| `app/views/api/v1/accounts/thesis_items/{index,show}.json.jbuilder` | show do item (id/section/title/content/position/thesis_id) | JSON de itens | F2.1a |
| `app/javascript/dashboard/api/theses.js` | client HTTP account-scoped: CRUD/reorder de teses + `createItem/updateItem/deleteItem/reorderItems` aninhados | API client frontend | F2.1a |
| `app/javascript/dashboard/store/modules/theses.js` | módulo Vuex (molde leadConfig): `SET_THESES` faz MERGE por id (payload leve do reorder/index não trunca description/items enriquecidos pelo show) | estado de teses | F2.1a |
| `app/javascript/dashboard/routes/dashboard/ramon/pages/Playbooks.vue` | tela mestre-detalhe (Intranet, admin): lista de teses (add/remover/mover) + detalhe com campos e itens por seção, CRUD inline sem modais | UI de gestão de playbooks | F2.1a |
| `app/javascript/dashboard/routes/dashboard/ramon/components/conversation/LeadPlaybook.vue` | aba "Playbook" do painel do lead: consulta das seções qualificacao/objecao/documento da tese do lead, botão copiar por item | consulta na conversa | F2.1a |
| `db/seeds/ramon/theses_seed.yml` | seed idempotente: 5 teses de incapacidade / 67 itens (B31, B32, auxílio-acidente, BPC/LOAS deficiência, 25%) | dados default | F2.1a |
| `spec/factories/{theses,thesis_items}.rb` + specs (models, requests, store, páginas) | cobertura CI da fatia | specs | F2.1a |
| `spec/models/thesis_spec.rb` | specs do model `Thesis` (validações, associações, posição default, dedup name) | cobertura do model Thesis | F2.1a |
| `spec/models/thesis_item_spec.rb` | specs do model `ThesisItem` (validações, belongs_to, posição, content sanitizado) | cobertura do model ThesisItem | F2.1a |
| `spec/controllers/api/v1/accounts/theses_controller_spec.rb` | request specs: index, show, create, update, destroy, reorder; autorização | cobertura do controller de teses | F2.1a |
| `spec/controllers/api/v1/accounts/thesis_items_controller_spec.rb` | request specs: create, update, destroy, reorder dentro de tese; autorização | cobertura do controller de itens | F2.1a |
| `app/javascript/dashboard/store/modules/specs/theses/actions.spec.js` | specs: fetch teses, criar, editar, deletar, reorder; sync realtime | cobertura de actions | F2.1a |
| `app/javascript/dashboard/store/modules/specs/theses/getters.spec.js` | specs: getters (list, by id, count, etc.) | cobertura de getters | F2.1a |
| `app/javascript/dashboard/store/modules/specs/theses/mutations.spec.js` | specs de mutations (SET_THESES, ADD_THESIS, EDIT_THESIS, DELETE_THESIS, UI_FLAG) | cobertura de mutations | F2.1a |
| `app/javascript/dashboard/routes/dashboard/ramon/pages/specs/Playbooks.spec.js` | component specs: render listagem, criar/editar modals, reorder interação | cobertura de Playbooks.vue | F2.1a |
| `app/javascript/dashboard/ramon/components/conversation/specs/LeadPlaybook.spec.js` | component specs: seletor de tese, preview playbook expand-collapse, integração com lead | cobertura de LeadPlaybook.vue | F2.1a |
| `app/javascript/dashboard/routes/dashboard/ramon/components/specs/IntranetSidebar.spec.js` (linha de changes) | — já existia; 6 linhas de contexto p/ novo menu item "Playbooks" | sidebar item novo | F2.1a |
| `spec/controllers/api/v1/accounts/leads_controller_spec.rb` (linha de changes) | — já existia; 29 linhas p/ novo atributo `thesis_id` em lead | cobertura do novo campo | F2.1a |
| `spec/models/lead_spec.rb` (linha de changes) | — já existia; lines para `belongs_to :thesis`, validação, activity record | cobertura do model | F2.1a |
| `app/javascript/dashboard/routes/dashboard/conversation/specs/LeadConversationPanel.spec.js` (linha de changes) | — já existia; 29 linhas p/ novo componente `LeadPlaybook` na lista | cobertura de integração | F2.1a |
| `app/javascript/dashboard/routes/dashboard/lead/specs/LeadFields.spec.js` (linha de changes) | — já existia; 19 linhas p/ novo campo `thesis_id` (dropdown) | cobertura do campo | F2.1a |
| `app/javascript/dashboard/components/kanban/specs/LeadDrawer.spec.js` (linha de changes) | — já existia; 4 linhas de contexto | drawer: sem mudança funcional | F2.1a |
| `spec/factories/leads.rb` (não listado no diff?) | — possivelmente ya existía; confirmar se tem `thesis: association` | factory de lead com tese | F2.1a |
| `spec/services/leads/seed_default_config_service_spec.rb` (linha de changes) | — já existia; 18 linhas p/ cobertura de seed de teses | cobertura de seed | F2.1a |
| `app/controllers/api/v1/accounts/lead_tasks_controller.rb` | controller CRUD + `complete` (fetch_lead condicional, fetch_task, `authorize(LeadTask)`); index escopado ao lead ou à conta (`account_scope` com `includes(:lead)` + filtros open/overdue/today) | API de tarefas do lead | PR-A t2 |
| `app/policies/lead_task_policy.rb` | policy `index?/create?/update?/complete?/destroy?` = admin+agent (molde `lead_note_policy`) | autorização das tarefas | PR-A t2 |
| `app/views/api/v1/accounts/lead_tasks/{index,create,update}.json.jbuilder` + `_lead_task.json.jbuilder` | serialização `{ payload: [...] }` / task única; partial com `id lead_id user_id title kind due_at completed_at created_at` + `lead_name` (via `task.lead.name`) | resposta JSON das tarefas | PR-A t2 |
| `spec/controllers/api/v1/accounts/lead_tasks_controller_spec.rb` | request spec: lista ordenada, cria (autor), atualiza, completa (`completed_at`), remove, nega estranho (401/404), coleção da conta `scope=overdue` | cobertura da API de tarefas | PR-A t2 |

## Checklist de rebase (a cada nova release upstream)
1. `git fetch upstream --tags`
2. `git switch ramon && git rebase vX.Y.Z`
3. Resolver conflitos **apenas** nos arquivos da tabela "core editados".
4. Atualizar a versão fixada acima + a tag da imagem no workflow.
5. Push → Actions builda → smoke test na VPS (Task 0.5).
