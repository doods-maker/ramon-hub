# Equipe · chat interno como caixa do Chatwoot — plano

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans. Steps use checkbox (`- [ ]`).

**Goal:** o chat interno (Geral, setor, 1:1) vira a caixa **Equipe** dentro de Conversas; o hub fica surdo nela.

**Architecture:** `Channel::Api` sem webhook marcado por `inboxes.equipe`. Cada conversa tem um contato
sintético (`additional_attributes.equipe = true`, `contact_inbox.source_id = equipe-<chave>`). Quem vê =
participante (`conversation_participants`) ou admin. Não-lida por pessoa em `conversation_participants.last_seen_at`.
O hub surdo = um guard no `AsyncDispatcher` (só o `NotificationListener` ouve eventos da caixa Equipe).

**Tech Stack:** Rails 7.1, Vue 3 `<script setup>`, Vuex (conversas nativas), Pinia (badge), RSpec/Vitest.

**Spec:** `docs/superpowers/specs/2026-10-02-equipe-chegada-e-chat-design.md` (seção "31/10") + ADR 0011.

## Global Constraints

- Migrações `20261031100001` (drop `ramon_chat_*`) e `20261031100002` (`inboxes.equipe`, `conversation_participants.last_seen_at`); `db/schema.rb` à mão.
- Seed idempotente: `rails runner 'Ramon::Equipe.sincronizar(Account.find(2), criar: true)'`.
- Admin vê tudo (inclusive 1:1); aviso (som + Notification) só para quem participa.
- Cada ponto do core tocado vai para `docs/FORK-PONTOS-DE-REGISTRO.md`.
- Lint: `rubocop-vps`, `npx eslint`; specs no CI.

## Review Focus

- Agente fora da conversa (1:1 alheia) não lista, não abre, não manda mensagem, não recebe tempo real.
- Conversa da Equipe não aparece em "Todas"/"Participando" das caixas de cliente.
- Sair de um time tira o acesso ao canal do setor (sincronização no commit do `TeamMember`).
- Nenhum listener do hub (lead, fluxo, agente, webhook, automação, relatório, CSAT, Captain) roda para a Equipe — nem `contact_created`/`inbox_created`.
- Auto-resolver da conta não fecha Geral/setor/1:1.

---

### Task 1: dados + `Ramon::Equipe` (seed, 1:1, não-lida)

**Files:** Create `db/migrate/20261031100002_equipe_caixa.rb`, `app/services/ramon/equipe.rb`; Modify `db/schema.rb`,
`app/models/inbox.rb` (`assignable_agents` = todos na Equipe), `app/models/team_member.rb`, `app/models/account_user.rb`
(commit → `Ramon::Equipe.sincronizar(account)`). Test: `spec/services/ramon/equipe_spec.rb`.

**Produces:** `Ramon::Equipe.caixa(account) -> Inbox|nil`, `.sincronizar(account, criar: false) -> Inbox|nil`,
`.conversa_1a1(account, user, outro) -> Conversation`, `.nao_lidas(conversation, user) -> Integer`,
`.total_nao_lidas(account, user) -> Integer`, `.marcar_lida(conversation, user)`, `.evento?(data) -> Boolean`.

- [ ] Specs: seed cria caixa + Geral (todos) + 1 por time (membros), idempotente; sair do time remove participante;
  1:1 é a mesma conversa nos dois sentidos; não-lida conta só mensagem de colega depois do `last_seen_at`.
- [ ] Implementar; `rubocop-vps`; commit.

### Task 2: visibilidade + tempo real + leitura

**Files:** `app/services/conversations/permission_filter_service.rb`, `app/policies/conversation_policy.rb`,
`app/policies/inbox_policy.rb`, `app/finders/conversation_finder.rb` (Equipe só dentro da caixa),
`app/listeners/action_cable_listener.rb` (participantes), `app/controllers/api/v1/accounts/conversations_controller.rb`
(`update_last_seen`), `app/views/api/v1/conversations/partials/_conversation.json.jbuilder` (`unread_count` por pessoa),
`app/presenters/conversations/ramon_event_data.rb` (sem `unread_count` no cable), `app/views/api/v1/models/_inbox.json.jbuilder`.
Test: `spec/requests/ramon_equipe_visibilidade_spec.rb`.

- [ ] Request specs: agente lista Geral/setor/1:1 dele e não a 1:1 alheia; admin lista tudo; fora → 401/404 em
  mostrar e em criar mensagem; `update_last_seen` zera a não-lida só de quem leu.

### Task 3: hub surdo

**Files:** `app/dispatchers/async_dispatcher.rb`, `app/jobs/conversations/resolution_job.rb`. Test: `spec/dispatchers/async_dispatcher_equipe_spec.rb`.

- [ ] Spec: evento de mensagem/conversa/contato/caixa da Equipe chega só ao `NotificationListener`; de outra caixa chega a todos.

### Task 4: endpoint + front

**Files:** `app/controllers/api/v1/accounts/ramon_equipe_controller.rb`, `config/routes.rb`, `app/javascript/dashboard/api/ramonEquipe.js`,
`stores/equipe.js` (badge + aviso), `components/ChatList.vue` (botão 1:1, aba "Todas"), `ramon/components/equipe/EquipeNova1a1.vue`,
`store/modules/conversations/actions.js` (não-lida local), `routes/dashboard/conversation/ConversationView.vue` (sem painel do contato),
`components-next/sidebar/Sidebar.vue` (badge), `helper/actionCable.js` (aviso), `i18n en/pt_BR ramon.json`.

- [ ] Vitest do store `equipe` (aviso só de participante, fora da conversa à vista); eslint; commit.

### Task 5: docs + PR
ADR 0011, seção do spec, `FORK-PONTOS-DE-REGISTRO.md`, smoke "O" no consolidado, revisor, PR.
