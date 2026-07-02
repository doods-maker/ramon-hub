@AGENTS.md

# ramon-hub — contexto da banca (permanente)

Fork pesado do **Chatwoot v4.15.1** operado pela **Ramon Antônio Advogados**.
É o **pipeline/CRM comercial** da banca (decidido 02/07/2026): funil Kanban de
leads, painel do lead na conversa, captação das landing pages. Repo:
`doods-maker/ramon-hub`. Produção na VPS (`ssh root@185.194.216.67`;
deploy = `git pull` + `docker compose up --build`).

## ⚠️ Regras inegociáveis

- **Deploy em produção só com OK explícito do Eduardo.** Nada sobe pra VPS sem
  aprovação, mesmo que o merge já tenha acontecido.
- **Sem ambiente de teste local** → quem valida é **PR + CI**. Não mergear com
  CI vermelho.

## Lições de engenharia (aprendidas no fork — não reaprender do zero)

- **Evento custom Vue SEMPRE camelCase** — kebab-case (ex.: `open-conversation`)
  NÃO passa no eslint do projeto.
- **Migração nova → regenerar `db/schema.rb` via scratch DB na VPS** (não há
  Postgres local).
- **Componente nativo pesado só monta com estado pronto** — usar `v-if` de
  readiness (ex.: montar `ConversationBox` só quando ativo).
- **Action Vuex: não desestruturar `state` cru** (quebra a regra no-shadow).

## Onde estão as coisas

- Guidelines técnicas do código Chatwoot: `AGENTS.md` (importado no topo).
- Planos e specs do projeto: `docs/superpowers/plans/` e `docs/superpowers/specs/`
  (histórico arquivado em `docs/superpowers/_arquivo/`).
- Contexto do departamento comercial: `..\..\CLAUDE.md` e
  `..\..\business-context.md` (§10 = este projeto como pipeline).
