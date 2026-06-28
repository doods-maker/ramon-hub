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
| `app/javascript/dashboard/routes/dashboard/dashboard.routes.js` | import `ramonRoutes` + `...ramonRoutes` no array children | seção Intranet | 1A |
| `app/javascript/dashboard/components-next/sidebar/Sidebar.vue` | item Ramon do `menuItems` **revertido** na 1B (trilho substitui o item) | o WorldRail faz a troca de mundo agora | 1B |
| `app/javascript/dashboard/i18n/locale/en/settings.json` | +`"RAMON": "Intranet"` dentro de `"SIDEBAR"` | i18n sidebar (inofensivo, mantido) | 1A |
| `app/javascript/dashboard/i18n/locale/pt_BR/settings.json` | +`"RAMON": "Intranet"` dentro de `"SIDEBAR"` | i18n sidebar (inofensivo, mantido) | 1A |
| `app/javascript/dashboard/i18n/locale/en/index.js` | +import e spread de `ramon.json` | registra locale ramon | 1A |
| `app/javascript/dashboard/i18n/locale/pt_BR/index.js` | +import e spread de `ramon.json` | registra locale ramon | 1A |
| `app/javascript/dashboard/routes/dashboard/Dashboard.vue` | +imports `WorldRail`/`IntranetSidebar`; +computed `isIntranetWorld`; template: `WorldRail` antes de `NextSidebar` (v-if) + `IntranetSidebar` (v-else) | trilho de dois níveis | 1B |

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

## Checklist de rebase (a cada nova release upstream)
1. `git fetch upstream --tags`
2. `git switch ramon && git rebase vX.Y.Z`
3. Resolver conflitos **apenas** nos arquivos da tabela "core editados".
4. Atualizar a versão fixada acima + a tag da imagem no workflow.
5. Push → Actions builda → smoke test na VPS (Task 0.5).
