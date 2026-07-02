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
| `app/javascript/dashboard/i18n/locale/en/generalSettings.json` | +`"ramon_lead_created": "New lead (LP)"` no bloco `NOTIFICATION_SETTINGS.TYPE_LABEL` | rótulo do tipo de notificação (inglês) | A-notif |
| `app/javascript/dashboard/i18n/locale/pt_BR/generalSettings.json` | +`"ramon_lead_created": "Lead novo (LP)"` no bloco `NOTIFICATION_SETTINGS.TYPE_LABEL` | rótulo do tipo de notificação (português) | A-notif |

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

## Checklist de rebase (a cada nova release upstream)
1. `git fetch upstream --tags`
2. `git switch ramon && git rebase vX.Y.Z`
3. Resolver conflitos **apenas** nos arquivos da tabela "core editados".
4. Atualizar a versão fixada acima + a tag da imagem no workflow.
5. Push → Actions builda → smoke test na VPS (Task 0.5).
