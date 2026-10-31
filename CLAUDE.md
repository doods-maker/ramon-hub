# ramon-hub — contexto da banca (permanente)

Fork pesado do **Chatwoot v4.15.1** operado pela **Ramon Antonio Advogados** —
o **sistema central do escritório**: CRM/funil de leads, atendimento WhatsApp
com IA, agenda, automações em fluxo, painel do cliente, cálculos, BI.
Repo: `doods-maker/ramon-hub`, branch principal `ramon`. Produção na VPS
(`ssh root@185.194.216.67`; deploy = `git pull` + `docker compose up --build`).

## ⚠️ Regras inegociáveis

- **Merge e deploy autônomos (desde 09/07/2026, ordem do Eduardo):** PR com CI
  100% verde pode ser mergeado e deployado sem OK caso a caso. Contrapartida:
  registrar o que subiu + roteiro de smoke em doc pro Eduardo revisar.
- **Sem ambiente local** (sem Ruby/Postgres na máquina) → quem valida é
  **PR + CI**. CI vermelho não mergeia.
- **ssh de escrita na VPS é barrado para o Claude** → comando que altera a VPS
  vai pronto para o Eduardo rodar com `!`.
- **Texto que fala com cliente é gate do Eduardo:** o código sobe, o texto só
  liga com aprovação explícita.

## Código (convenções do Chatwoot que valem aqui)

- **Lint antes do push:** Ruby → `rubocop-vps` (roda na VPS, ~10 s); JS/Vue →
  eslint via `node_modules`. RuboCop com linha de até 150 caracteres.
- **Vue:** Composition API com `<script setup>`; componentes PascalCase;
  **eventos custom SEMPRE camelCase** (kebab-case quebra o eslint);
  bolhas de mensagem em `components-next/`.
- **Estilo:** só classes Tailwind (cores em `tailwind.config.js`).
- **i18n:** sem string solta no template; editar só `en.yml` (backend) e
  `en.json` (frontend).
- **Enterprise:** mudança em núcleo → procurar o par em `enterprise/` e manter
  compatível.
- **Commits:** Conventional Commits (`type(scope): assunto`).

## Lições do fork (não reaprender do zero)

- **Migração nova → regenerar `db/schema.rb` via scratch DB na VPS.**
- **Componente nativo pesado só monta com estado pronto** — `v-if` de
  readiness (ex.: `ConversationBox` só quando ativo).
- **Action Vuex: não desestruturar `state` cru** (quebra no-shadow).

## Onde estão as coisas

- Planos e specs: `docs/superpowers/plans/` e `docs/superpowers/specs/`
  (histórico em `docs/superpowers/_arquivo/`). ADRs: `docs/adr/`.
- Pontos onde o fork toca o Chatwoot: `docs/FORK-PONTOS-DE-REGISTRO.md`.
- Agente do hub (Claude na VPS): `deploy/agente-hub/` — lê o espelho
  `/opt/sede` (skill `/sincronizar-sede`).
- Contexto comercial: `..\..\CLAUDE.md` e `..\..\business-context.md`.
