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
| _(nenhum ainda)_ | | | |

## Arquivos NOVOS (namespace `ramon/` — não conflitam no rebase)
| Arquivo | Responsabilidade | Fase |
|---|---|---|
| `.github/workflows/ramon-publish.yml` | build + publish da imagem do fork no GHCR | 0 |
| `docs/FORK-PONTOS-DE-REGISTRO.md` | esta lista | 0 |

## Checklist de rebase (a cada nova release upstream)
1. `git fetch upstream --tags`
2. `git switch ramon && git rebase vX.Y.Z`
3. Resolver conflitos **apenas** nos arquivos da tabela "core editados".
4. Atualizar a versão fixada acima + a tag da imagem no workflow.
5. Push → Actions builda → smoke test na VPS (Task 0.5).
