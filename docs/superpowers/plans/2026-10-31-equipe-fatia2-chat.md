# Equipe · Fatia 2 — Chat da equipe Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** chat interno da equipe dentro do hub — canais Geral, um por setor (time) e 1:1 — só texto, aviso discreto, administradores leem tudo.

**Architecture:** três tabelas próprias (`ramon_chat_canais/membros/mensagens`), isoladas de inbox/conversation. `RamonChatController` + `ChatCanalPolicy`; mensagem nova transmite `ramon.chat.message` (ActionCable) para membros + administradores. Front: store pinia `chat`, página `Equipe.vue`, item "Equipe" no menu da Intranet com badge; som curto + Notification sem `requireInteraction`.

**Tech Stack:** Rails 7.1, Pundit, ActionCable; Vue 3 `<script setup>`, Pinia, Tailwind.

**Spec:** `docs/superpowers/specs/2026-10-02-equipe-chegada-e-chat-design.md` (Fatia 2, D1/D7/D8/D9)

## Global Constraints

- Não usar inbox/conversation do Chatwoot (D1). Só texto (D7). Aviso discreto: badge + `ding.mp3` + Notification sem `requireInteraction` (D8).
- Administrador lê qualquer canal e **não vira membro**; só participante escreve (D9). Aviso fixo na tela: "Administradores podem ler as conversas."
- Membros: `setor` = membros do time (fonte da verdade é o time); `geral` = usuários da conta; `direto` = 2 linhas em `ramon_chat_membros`.
- Migração `20261031000001_create_ramon_chat`; `db/schema.rb` editado à mão (versão `2026_10_31_000001`).
- Evento Vue camelCase; action pinia não desestrutura `state`; máx 7 expectations/exemplo; `rubocop-vps` antes do commit Ruby.

## Review Focus

- Admin abre 1:1 de outros e marca lido → NÃO pode criar linha de membro (viraria participante). Teste no controller.
- Mensagem em canal direto recém-criado chega a quem não tinha o canal na lista → front recarrega a lista. Teste no store.
- Mensagem do próprio autor não soma não-lida nem toca som. Teste no store.
- Time apagado → canal de setor some da lista (não quebra o `index`). Teste no model.
- Conteúdo em branco → 422, sem mensagem. Teste no controller.

---

### Task 1: Dados + regras de visibilidade

**Files:** Create `db/migrate/20261031000001_create_ramon_chat.rb`, `app/models/chat_canal.rb`, `app/models/chat_membro.rb`, `app/models/chat_mensagem.rb`; Modify `db/schema.rb`, `app/models/account.rb` (+`has_many :chat_canais`); Test `spec/models/chat_canal_spec.rb`.

**Interfaces (Produces):**
- `ChatCanal` (`tipo` ∈ `direto|setor|geral`, `team_id`, `chave` única por conta: `geral`, `setor:<team_id>`, `direto:<menor>-<maior>`).
- `ChatCanal.visiveis(account, user, admin:) -> Array<ChatCanal>` (garante geral + um setor por time; admin vê todos).
- `ChatCanal.direto!(account, a, b) -> ChatCanal` (idempotente, cria as 2 linhas de membro).
- `#membro_ids -> Array<Integer>`, `#participante?(user)`, `#nao_lidas(user) -> Integer` (0 se não participante; ignora as do próprio user), `#marcar_lido!(user)` (no-op se não participante), `#push_data(user)`.
- `ChatMensagem#push_event_data` = `{id, canal_id, account_id, autor:{id,name}, conteudo, created_at}`; `after_create_commit` transmite `ramon.chat.message` para `membro_ids | Ramon::Papeis.gestor_ids`.

- [ ] Specs: setor = membros do time; geral = usuários da conta; direto idempotente; não-lidas contam só depois de `lido_ate` e não as próprias; time apagado some de `visiveis`; transmissão para membros + admins.
- [ ] Implementar; `rubocop-vps`; commit.

### Task 2: API

**Files:** Create `app/controllers/api/v1/accounts/ramon_chat_controller.rb`, `app/policies/chat_canal_policy.rb`; Modify `config/routes.rb`; Test `spec/controllers/api/v1/accounts/ramon_chat_controller_spec.rb`.

Rotas (`resources :ramon_chat, only: [:index, :show]`): `GET index` → `{payload: canais, admin}`; `GET show?antes=<id>` → 50 mensagens anteriores, ordem crescente; `POST :id/enviar {conteudo}`; `POST :id/ler`; `POST direto {user_id}`.
Policy: `show?` = admin || participante; `enviar?`/`ler?` = participante; `index?`/`direto?` = qualquer agente da conta.

- [ ] Specs: participante lê/escreve; admin lê 1:1 alheio mas não escreve e `ler` não o torna membro; estranho 401; branco 422; direto idempotente; paginação `antes`.
- [ ] Implementar; `rubocop-vps`; commit.

### Task 3: Front

**Files:** Create `app/javascript/dashboard/api/ramonChat.js`, `app/javascript/dashboard/stores/chat.js` (+spec), `app/javascript/dashboard/routes/dashboard/ramon/pages/Equipe.vue`; Modify `helper/actionCable.js`, `ramon.routes.js` (`ramon_equipe`), `helpers/navIntranet.js` (grupo `equipe`), `components/IntranetSidebar.vue` (badge), `Dashboard.vue` (carregar + reconectar), `i18n/locale/{en,pt_BR}/ramon.json` (`RAMON.EQUIPE.*`, `RAMON.NAV.EQUIPE`), `docs/FORK-PONTOS-DE-REGISTRO.md`.

Store `chat`: `canais`, `mensagens{[canalId]: []}`, `abertoId`; getter `totalNaoLidas`; actions `carregar()`, `abrir(id)`, `anteriores(id)`, `enviar(conteudo)`, `direto(userId)`, `receber(msg, meuId) -> boolean` (true = avisar: não é minha, canal participante, e não está aberto com a aba visível).

- [ ] Spec do store: `receber` soma não-lida/avisa; ignora própria; canal desconhecido → `carregar`; canal aberto e visível → não avisa e marca lido.
- [ ] Implementar; `npx eslint`; prettier; commit.

### Task 4: Fechamento

- [ ] Revisor de código (subagente) sobre a branch; corrigir o que for real.
- [ ] `git merge origin/ramon`, resolver conflitos (schema `version` = maior).
- [ ] PR + CI verde; seção "## O. Equipe · Chat interno" no smoke consolidado.
