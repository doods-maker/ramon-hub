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
| `app/javascript/dashboard/assets/scss/_woot.scss` | +1 `@import 'ramon-brand'` após `next-colors` | rebrand fork-safe | 1 |
| `app/javascript/dashboard/helper/themeHelper.js` | default `'auto'` → `'dark'` (linha 6) | marca é dark por padrão | 1 |
| `tailwind.config.js` | +chave `cormorant` em `theme.fontFamily` | fonte de títulos | 1 |
| `app/javascript/dashboard/routes/dashboard/dashboard.routes.js` | import `ramonRoutes` + `...ramonRoutes` no array children | seção Intranet | 1 |
| `app/javascript/dashboard/components-next/sidebar/Sidebar.vue` | item Ramon no topo do `menuItems` computed | entrada na sidebar | 1 |
| `app/javascript/dashboard/i18n/locale/en/settings.json` | +`"RAMON": "Intranet"` dentro de `"SIDEBAR"` | i18n sidebar | 1 |
| `app/javascript/dashboard/i18n/locale/pt_BR/settings.json` | +`"RAMON": "Intranet"` dentro de `"SIDEBAR"` | i18n sidebar | 1 |

## Arquivos NOVOS (namespace `ramon/` — não conflitam no rebase)
| Arquivo | Responsabilidade | Fase |
|---|---|---|
| `.github/workflows/ramon-publish.yml` | build + publish da imagem do fork no GHCR | 0 |
| `docs/FORK-PONTOS-DE-REGISTRO.md` | esta lista | 0 |
| `app/javascript/dashboard/assets/scss/_ramon-brand.scss` | tokens de cor bronze (dark) e creme/bronze (light) | 1 |
| `app/javascript/dashboard/routes/dashboard/ramon/ramon.routes.js` | rotas da seção Intranet | 1 |
| `app/javascript/dashboard/routes/dashboard/ramon/pages/RamonOverview.vue` | Centro de Comando (shell placeholder) | 1 |
| `app/javascript/dashboard/i18n/locale/en/ramon.json` | textos das telas ramon (inglês) | 1 |
| `app/javascript/dashboard/i18n/locale/pt_BR/ramon.json` | textos das telas ramon (português) | 1 |

## Checklist de rebase (a cada nova release upstream)
1. `git fetch upstream --tags`
2. `git switch ramon && git rebase vX.Y.Z`
3. Resolver conflitos **apenas** nos arquivos da tabela "core editados".
4. Atualizar a versão fixada acima + a tag da imagem no workflow.
5. Push → Actions builda → smoke test na VPS (Task 0.5).
