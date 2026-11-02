# Equipe com cara de WhatsApp + @ — Plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** dar à caixa Equipe bolhas, lista e caixa de escrever de WhatsApp, com marcação por @, responder citando, digitando, vistos e reações, sem mudar nada nas conversas com clientes.

**Architecture:** tudo ramifica em `inbox.equipe`. Regras de servidor ficam em `Ramon::Equipe`; regras puras de tela ficam em um helper testável (`ramon/helpers/equipe.js`) e o estado por conversa no store `stores/equipe.js`. Sem migração: reações em `content_attributes`, leitura em `conversation_participants.last_seen_at`.

**Tech Stack:** Rails 7.1 + Vue 3 (fork Chatwoot v4.15.1), Pinia + Vuex, ActionCable, RSpec (só no CI), Vitest.

**Spec:** `docs/superpowers/specs/2026-11-02-equipe-whatsapp-design.md`. Alvo visual: `comercial\docs\mockups\2026-11-02-equipe-whatsapp\equipe.html`.

## Global Constraints

- Prazo: os 8 objetivos no ar até **16/11/2026**. Item em risco → avisar o Eduardo antes.
- Nunca adicionar membro na caixa Equipe. O @ nunca adiciona participante.
- Hub surdo: nenhum listener novo; o guard do `AsyncDispatcher` segue como único ponto.
- Nada muda em caixa que não seja Equipe. Todo ramo novo em arquivo nativo leva `FORK(ramon)` e entra em `docs/FORK-PONTOS-DE-REGISTRO.md`.
- Sem migração nem mudança em `db/schema.rb`.
- Texto de tela em `i18n/locale/en/ramon.json` e `pt_BR/ramon.json`, seção `RAMON.EQUIPE`; texto de servidor em `config/locales/en.yml` e `pt_BR.yml`.
- Tailwind + tokens do hub; fundo colorido sempre translúcido; `--ramon-enviada`, `--ramon-nao-lida`, `n-slate-4`, azul `n-brand`/`n-iris`.
- Vue: `<script setup>` em componente novo; eventos custom em camelCase. Ruby: linha até 150; `rubocop-vps` antes do push.
- Emojis, exatos e nesta ordem: 👍 ❤️ 😂 😮 😢 🙏.
- Token de `@todos`, exato: `[@todos](mention://todos/0/todos)`.
- Ruby não roda local: spec Ruby é escrita junto e validada no CI do PR. Vitest roda local.
- Merge só depois de o Eduardo aprovar os prints do pacote. CI vermelho não mergeia. Antes de abrir PR, rebase em `origin/ramon`.

**Preparação do worktree (uma vez, antes da Task 1):**
Commitar spec e plano (`docs(equipe): desenho e plano do chat com cara de WhatsApp`). `cmd //c mklink /J node_modules ..\ramon-hub\node_modules`, copiar `.husky/_` de `../ramon-hub/.husky/_`, criar `tmp/vitest.local.config.ts` com `server.fs.strict=false` (junção do pnpm). Vitest: `npx vitest run --config tmp/vitest.local.config.ts <arquivo>`. `tmp/` não é versionado.

## Review Focus

1. **Id parecido:** `mention://user/1/` não pode casar com `mention://user/12/`, no JS e no `LIKE`. Teste na Task 3 (Ruby) e na Task 2 (JS).
2. **Autor que saiu do chat:** mensagem antiga, reação ou citação de quem não participa mais continua com nome e nada quebra; o ✓✓ conta só os participantes atuais. Testes nas Tasks 2 e 8.
3. **Participantes ainda não carregados:** sem lista, nenhum ✓✓ azul, @ vazio, sem erro. Teste na Task 2.
4. **"@todos" digitado à mão**, sem escolher na lista, e token forjado: texto puro não avisa ninguém; `mention://todos` em 1:1 e id de fora são ignorados. Testes na Task 3.
5. **Mensagem só com anexo** ou apagada na prévia e na citação: mostra rótulo do anexo, nunca vazio nem `mention://`. Testes nas Tasks 2 e 7.

---

## Pacote 1 — bolhas, caixa de escrever, apagar, @

### Task 1: Servidor — só leitura, apagar e dados da conversa

**Files:**
- Modify: `app/services/ramon/equipe.rb`, `app/controllers/api/v1/accounts/conversations/messages_controller.rb`, `app/controllers/api/v1/accounts/conversations_controller.rb` (`toggle_typing_status`), `app/views/api/v1/conversations/partials/_conversation.json.jbuilder`, `app/presenters/conversations/ramon_event_data.rb`
- Test: `spec/controllers/api/v1/accounts/ramon_equipe_controller_spec.rb`, `spec/services/ramon/equipe_spec.rb`

**Interfaces:**
- Produces, em `Ramon::Equipe`:
  - `participante?(conversation, user) -> Boolean`
  - `pode_escrever?(conversation, user) -> Boolean` (true fora da Equipe; na Equipe, só participante)
  - `pode_apagar?(message, user, account_user) -> Boolean` (true fora da Equipe; na Equipe, participante que é autor ou admin)
  - `tipo(conversation) -> 'grupo' | '1a1'` (pelo `source_id` `equipe-1a1-`)
  - `pessoas_1a1(conversation) -> [{ id:, name:, thumbnail: }]` (`[]` em grupo)
- Produces, no JSON da conversa (jbuilder **e** `push_data`, só na Equipe): `equipe_tipo`, `equipe_pessoas`.

- [ ] **Step 1: Specs de request**

```ruby
describe 'admin que não participa só lê' do
  it('não envia') { mandar(admin, ana_bia); expect(response).to have_http_status(:forbidden); expect(ana_bia.messages.count).to eq(0) }
  it 'não aparece digitando' do
    post "#{base}/conversations/#{ana_bia.display_id}/toggle_typing_status", params: { typing_status: 'on' }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
  end
  it('continua lendo') { expect(ids_na_caixa(admin)).to include(ana_bia.display_id) }
  it('admin que participa do Geral envia') { mandar(admin, geral); expect(response).to have_http_status(:ok) }
end

describe 'apagar' do
  it 'colega não apaga mensagem alheia' # bia apaga msg da ana no ana_bia → 403, conteúdo intacto
  it 'autor apaga a própria'            # ana → 200, content_attributes deleted
  it 'admin que participa apaga no Geral' # admin apaga msg da ana no geral → 200
  it 'admin de fora não apaga'          # admin no ana_bia → 403
end

it 'caixa de cliente não muda: agente apaga mensagem de outro numa caixa comum' # continua 200

it 'conversa expõe tipo e pessoas' # GET da 1:1 → equipe_tipo '1a1', equipe_pessoas com ana e bia; geral → 'grupo' e []
```


- [ ] **Step 2: Implementar os métodos em `Ramon::Equipe`**
- [ ] **Step 3: Guardas nos controllers**

`MessagesController`: `before_action :equipe_pode_escrever!, only: [:create, :retry]` e `before_action :equipe_pode_apagar!, only: :destroy`, respondendo `head :forbidden`. `toggle_typing_status`: `return head :forbidden unless Ramon::Equipe.pode_escrever?(@conversation, Current.user)`. Usar `Current.user || @resource` como no `create`.

- [ ] **Step 4: Expor `equipe_tipo` e `equipe_pessoas`** no jbuilder e em `RamonEventData#push_data`, só com `inbox&.equipe?`. São iguais para todos, então podem ir no broadcast.
- [ ] **Step 5: `rubocop-vps`** nos arquivos alterados. Esperado: sem ofensas.
- [ ] **Step 6: Commit** `feat(equipe): só leitura para admin de fora e apagar só a própria mensagem`

### Task 2: Helper puro da Equipe e store

**Files:**
- Create: `app/javascript/dashboard/routes/dashboard/ramon/helpers/equipe.js`
- Test: `app/javascript/dashboard/routes/dashboard/ramon/helpers/specs/equipe.spec.js`
- Modify: `app/javascript/dashboard/stores/equipe.js`, `stores/equipe.spec.js`, `app/javascript/dashboard/api/ramonEquipe.js`, `app/controllers/api/v1/accounts/ramon_equipe_controller.rb`, `config/routes.rb`
- Test Ruby: `spec/controllers/api/v1/accounts/ramon_equipe_controller_spec.rb`

**Interfaces:**
- Produces (`helpers/equipe.js`):
  - `EMOJIS_REACAO: string[]`
  - `marcaUsuario(content, userId) -> boolean`
  - `textoLimpo(content) -> string` (troca `[@Nome](mention://…)` por `@Nome`)
  - `listaMarcacao(participantes, meuId, tipo) -> [{ id, name, thumbnail, type }]` (`type: 'user'`; em grupo, primeiro `{ id: 0, name: 'todos', type: 'todos' }`)
  - `estadoVisto({ createdAt, senderId }, participantes, meuId) -> { todosLeram, leram: string[], faltam: string[], total }`
  - `identidadeConversa(chat, meuId) -> { nome, foto } | null` (a outra pessoa na 1:1 em que participo; senão `null`, e a tela usa o contato)
  - `resumoReacoes(reacoes, participantes, meuId) -> [{ emoji, total, nomes: string[], minha }]`, reações no formato `[{ userId, userName, emoji }]`
  - `rotuloDia(segundos, agoraMs) -> 'HOJE' | 'ONTEM' | 'dd/MM/yyyy'`
  - `prefixoPrevia(message, meuId, tipo) -> { voce: boolean, nome: string | null }`
- Produces (store): `participantes: { [conversationId]: [{ id, name, thumbnail, lastSeenAt }] }`, `carregarParticipantes(conversationId)`, `atualizarLeitura({ conversationId, userId, lastSeenAt })`.
- Produces (API): `GET /ramon_equipe/participantes?conversation_id=<display_id>` → `[{ id, name, thumbnail, last_seen_at }]` (segundos), com `authorize conversation, :show?` e 404 fora da Equipe.

- [ ] **Step 1: Testes do helper**

```js
it('marcaUsuario não confunde ids', () => {
  expect(marcaUsuario('[@Ana](mention://user/1/Ana) oi', 1)).toBe(true);
  expect(marcaUsuario('[@Ana](mention://user/12/Ana) oi', 1)).toBe(false);
  expect(marcaUsuario('[@todos](mention://todos/0/todos) oi', 1)).toBe(true);
  expect(marcaUsuario('@todos oi', 1)).toBe(false);
  expect(marcaUsuario(null, 1)).toBe(false);
});
it('textoLimpo tira o token', () => {
  expect(textoLimpo('[@Dr. Ramon Antonio](mention://user/3/Dr.%20Ramon%20Antonio) ok')).toBe('@Dr. Ramon Antonio ok');
});
it('listaMarcacao: grupo traz todos, 1:1 só a outra pessoa, nunca eu', () => {
  const p = [{ id: 1, name: 'Eu' }, { id: 2, name: 'Bia' }];
  expect(listaMarcacao(p, 1, 'grupo').map(i => i.name)).toEqual(['todos', 'Bia']);
  expect(listaMarcacao(p, 1, '1a1').map(i => i.name)).toEqual(['Bia']);
  expect(listaMarcacao([], 1, 'grupo').map(i => i.name)).toEqual(['todos']);
});
it('estadoVisto conta quem não é autor', () => {
  const p = [{ id: 1, name: 'Eu', lastSeenAt: 0 }, { id: 2, name: 'Ana', lastSeenAt: 100 }, { id: 3, name: 'Bia', lastSeenAt: 50 }];
  expect(estadoVisto({ createdAt: 80, senderId: 1 }, p, 1)).toEqual({ todosLeram: false, leram: ['Ana'], faltam: ['Bia'], total: 2 });
});
it('sem participantes nunca fica azul', () => {
  expect(estadoVisto({ createdAt: 80, senderId: 1 }, [], 1).todosLeram).toBe(false);
});
it('identidadeConversa: 1:1 mostra o outro; admin de fora e grupo usam o contato', () => {
  const chat = { equipe_tipo: '1a1', equipe_pessoas: [{ id: 1, name: 'Ana', thumbnail: 'a' }, { id: 2, name: 'Bia', thumbnail: 'b' }] };
  expect(identidadeConversa(chat, 1)).toEqual({ nome: 'Bia', foto: 'b' });
  expect(identidadeConversa(chat, 9)).toBeNull();
  expect(identidadeConversa({ equipe_tipo: 'grupo', equipe_pessoas: [] }, 1)).toBeNull();
});
it('resumoReacoes agrupa, marca a minha e usa o nome gravado de quem saiu do chat', () => {
  const r = [{ userId: 1, userName: 'Eu', emoji: '👍' }, { userId: 9, userName: 'Saiu', emoji: '👍' }];
  expect(resumoReacoes(r, [], 1)).toEqual([{ emoji: '👍', total: 2, nomes: ['Eu', 'Saiu'], minha: true }]);
});
it('prefixoPrevia', () => {
  expect(prefixoPrevia({ sender: { id: 1, name: 'Eu' } }, 1, 'grupo')).toEqual({ voce: true, nome: null });
  expect(prefixoPrevia({ sender: { id: 2, name: 'Ana' } }, 1, 'grupo')).toEqual({ voce: false, nome: 'Ana' });
  expect(prefixoPrevia({ sender: { id: 2, name: 'Ana' } }, 1, '1a1')).toEqual({ voce: false, nome: null });
});
```

`rotuloDia` testado com `agoraMs` fixo, em fuso de São Paulo (reusar `dataLocal.js` se servir).

- [ ] **Step 2: Rodar** `npx vitest run --config tmp/vitest.local.config.ts app/javascript/dashboard/routes/dashboard/ramon/helpers/specs/equipe.spec.js`. Esperado: FAIL (módulo não existe).
- [ ] **Step 3: Implementar o helper.** Regex de `marcaUsuario` com `mention://user/${id}/` incluindo a barra final.
- [ ] **Step 4: Rodar de novo.** Esperado: PASS.
- [ ] **Step 5: Endpoint de participantes + store + spec Ruby** (participante vê, colega de fora 403 ou 404, admin vê; `last_seen_at` em segundos). Em `stores/equipe.spec.js`: `atualizarLeitura` atualiza só a pessoa certa e ignora conversa não carregada.
- [ ] **Step 6: Commit** `feat(equipe): helper de regras do chat, participantes e store`

### Task 3: Marcação no servidor

**Files:**
- Modify: `app/services/messages/mention_service.rb`, `app/services/ramon/equipe.rb`, `app/models/notification.rb` (`push_message_title`), `app/views/api/v1/conversations/partials/_conversation.json.jbuilder`, `config/locales/en.yml`, `config/locales/pt_BR.yml`
- Test: `spec/services/messages/mention_service_spec.rb`, `spec/services/ramon/equipe_spec.rb`

**Interfaces:**
- Consumes: `Ramon::Equipe.tipo`.
- Produces: `Ramon::Equipe.marcado_nao_lido?(conversation, user) -> Boolean`; `equipe_marcado` no jbuilder (por pessoa, **nunca** no `push_data`); i18n `notifications.notification_title.equipe_mention` = "%{quem} te marcou em %{canal}".

- [ ] **Step 1: Specs**

```ruby
context 'na caixa Equipe' do
  it 'mensagem pública marca participante'             # conversation_mention para bia, 1 notificação só (não também participating_*)
  it 'id de quem não participa é ignorado'             # caio fora do setor → nenhuma notificação, continua fora dos participantes
  it 'admin de fora não é marcado'                     # admin não participante → ignorado
  it '@todos marca todos menos quem escreveu'          # token exato, geral → todos menos o autor
  it '"@todos" em texto puro não marca'                # só aviso comum
  it '@todos em 1:1 é ignorado'                        # conversa_1a1 + token → sem conversation_mention
  it 'não adiciona participante nem chama UserMentionJob'
end
it 'caixa de cliente: mensagem pública com token continua sem efeito' # não regressão
```

Em `equipe_spec.rb`: `marcado_nao_lido?` true com marcação não lida, false após `marcar_lida`, false com marcação de outro id (`user/12` para o usuário `1`), false depois de apagar a mensagem. Em `notification`: título da Equipe "Ana te marcou em Geral"; fora da Equipe o texto nativo.

- [ ] **Step 2: Ramo da Equipe no `MentionService`**

`valid_mention_message?` aceita pública se `message.inbox.equipe?`; `mentioned_ids` soma todos os participantes quando há `(mention://todos/0/todos)` e `Ramon::Equipe.tipo == 'grupo'`; `valid_mentionable_user_ids` usa participantes; `perform` pula `UserMentionJob` e `add_mentioned_users_as_participants` na Equipe (a tela "Menções" nativa não entra nesse fluxo).

- [ ] **Step 3: `marcado_nao_lido?`** extraindo de `nao_lidas` uma consulta comum de mensagens de colega não lidas; `LIKE` com `(mention://user/<id>/%` ou `(mention://todos/0/%`.
- [ ] **Step 4: `equipe_marcado` no jbuilder e título em `push_message_title`.**
- [ ] **Step 5: `rubocop-vps`.** Esperado: sem ofensas.
- [ ] **Step 6: Commit** `feat(equipe): marcação com @ entre participantes`

### Task 4: Bolhas e menu da mensagem

**Files:**
- Modify: `app/javascript/dashboard/components-next/message/Message.vue`, `MessageList.vue`, `MessageMeta.vue`, `bubbles/Base.vue`, `bubbles/Text/*` (destaque do @), `shared/helpers/markdownIt/link.js`, `helpers/specs` de `MessageFormatter`
- Create: `app/javascript/dashboard/routes/dashboard/ramon/pages/EquipeChat.story.vue` (harness dos prints)
- Test: `app/javascript/dashboard/components-next/message/specs/` (spec de orientação), spec do `MessageFormatter`

**Interfaces:**
- Consumes: `marcaUsuario`, `rotuloDia`, `inbox.equipe` (`Message.vue` já tem `inbox`), `chat.equipe_tipo`.
- Produces no contexto da mensagem (`provideMessageContext`): `isEquipe`, `mostrarAutor`; prop nova em `Message.vue`: `primeiroDoAutor`, calculada no `MessageList`.

- [ ] **Step 1: Testes**
  - Orientação na Equipe: `sender.id === currentUserId` → right + variante AGENT; colega → left + variante USER; admin de fora → todos left; `status: progress` → right.
  - Fora da Equipe: mensagem de agente continua right + AGENT (não regressão).
  - `MessageFormatter`: `[@todos](mention://todos/0/todos)` vira `<span class="prosemirror-mention-node">@todos</span>`.
- [ ] **Step 2: Rodar.** Esperado: FAIL.
- [ ] **Step 3: Implementar**
  - `isBotOrAgentMessage`: na Equipe, `senderId === currentUserId`, mantido o ramo de `PROGRESS`. `variant` usa `USER` para colega.
  - `shouldShowAvatar`/`gridTemplate`: na Equipe, em grupo e à esquerda, foto à esquerda só na última do bloco do autor; 1:1 sem foto.
  - `Base.vue`: nome do autor na primeira do bloco em grupo; marcação minha com fundo azul translúcido (classe via `marcaUsuario` e fileta azul na bolha, como `.marcado` do mockup).
  - `MessageList.vue`: `primeiroDoAutor` e separador de dia com `rotuloDia`, só na Equipe.
  - `MessageMeta.vue`: hora `HH:mm` na Equipe.
  - `contextMenuEnabledOptions` na Equipe: só `copy`, `replyTo` (Task 7) e `delete` quando autor ou admin participante; fora do chat, só `copy`.
  - `link.js`: regex com `user|team|todos`.
- [ ] **Step 4: Rodar.** Esperado: PASS.
- [ ] **Step 5: Commit** `feat(equipe): bolhas de WhatsApp na caixa Equipe`

### Task 5: Caixa de escrever, Enter, topo e só leitura

**Files:**
- Modify: `components/widgets/conversation/ReplyBox.vue`, `components/widgets/WootWriter/ReplyBottomPanel.vue`, `components/widgets/WootWriter/Editor.vue`, `components/widgets/conversation/TagAgents.vue`, `components/widgets/conversation/MessagesView.vue`, `components/widgets/conversation/ConversationHeader.vue`, `stores/equipe.js` (`avisar`)
- Test: `stores/equipe.spec.js`, spec de `TagAgents` (criar em `conversation/specs/`)

**Interfaces:**
- Consumes: `listaMarcacao`, `textoLimpo`, `identidadeConversa`, `carregarParticipantes`, store `participantes`.
- Produces: prop `equipe: Boolean` em `Editor.vue` e `ReplyBottomPanel.vue`; prop `itens: Array` opcional em `TagAgents.vue`.

- [ ] **Step 1: Testes**
  - `TagAgents` com `itens` mostra só eles, filtra por busca e emite o item escolhido; sem `itens`, comportamento nativo.
  - `avisar` com `conversation_mention`: título `"Ana te marcou · Geral"` e corpo com `@Nome`, sem `mention://`.
  - `avisar` com aviso comum: título `"Ana · Geral"` (como hoje), corpo sem `mention://`.
- [ ] **Step 2: Rodar.** Esperado: FAIL.
- [ ] **Step 3: `Editor.vue`** com `equipe`:
  - formato `PRIVATE_NOTE_FORMATTING` (único com o nó de marcação);
  - suggestion de @ ativa e `TagAgents` montado mesmo sem `isPrivate`, com `itens` de `listaMarcacao`;
  - `isEnterToSendEnabled()` true e `isCmdPlusEnterToSendEnabled()` false só aqui, sem gravar preferência;
  - suggestions de `/` e variáveis desligadas.
  Conferir que o rascunho salvo reabre o token de `todos` sem quebrar o parser do editor.
- [ ] **Step 4: `ReplyBox.vue` + `ReplyBottomPanel.vue`** com `equipe`: sem `ReplyTopPanel`, `ChaveManterIa`, assinatura, respostas prontas e copiloto; só emoji, anexo, áudio, campo e enviar em linha, como no mockup.
- [ ] **Step 5: `MessagesView.vue`:** carrega participantes ao trocar de conversa da Equipe; `ReplyBox` só com `participante`, senão faixa `RAMON.EQUIPE.SO_LEITURA` ("Você está lendo como administrador"); esconde o balão nativo de digitação na Equipe.
- [ ] **Step 6: `ConversationHeader.vue`** na Equipe: foto e nome (`identidadeConversa` ou contato); subtítulo "N participantes" em grupo e, no lugar dele, o texto de `getTypingUsersText` quando há alguém digitando. Sem `#id`, caixa, SLA, `LeadPanelToggle`, `IaDaConversa`, chamada e `MoreActions`.
- [ ] **Step 7: Rodar.** Esperado: PASS.
- [ ] **Step 8: Commit** `feat(equipe): caixa de escrever, Enter, topo e só leitura`

### Portão do Pacote 1

- [ ] **Step 1: Prints.** `EquipeChat.story.vue` no harness Vite + Chrome headless (`--virtual-time-budget=15000`), com os componentes reais, dados de exemplo, claro e escuro: grupo, 1:1, admin de fora, lista do @. Salvar `pacote1-*.png` e `comparar.html` em `comercial\docs\mockups\2026-11-02-equipe-whatsapp\`. Se `ReplyBox` não montar no harness, avisar o Eduardo em vez de pular.
- [ ] **Step 2: Mostrar ao Eduardo.** Abrir `comparar.html` no navegador. Reprovou → corrigir e repetir.
- [ ] **Step 3: PR.** eslint nos arquivos alterados, `rubocop-vps`, rebase, push, PR. Esperar `gh pr checks N` listar ao menos um check antes do `--watch`.
- [ ] **Step 4: Merge** com CI verde e print aprovado. Após o publish, conferir a label da imagem; se errada, `gh run rerun` do publish do último commit.
- [ ] **Step 5: Deploy e prova.** Comando pronto para o Eduardo rodar com `!`. Depois: `/app/login` 200 e prova `rails runner` só de leitura.

---

## Pacote 2 — lista, responder, digitando

### Task 6: Lista da esquerda

**Files:**
- Modify: `components/widgets/conversation/ConversationCard.vue`, `MessagePreview.vue`, `store/modules/conversations/actions.js`, `store/modules/conversations/index.js` (`ADD_MESSAGE`), `actions/messageReadActions.js`
- Test: `store/modules/specs/conversations/actions.spec.js`

**Interfaces:**
- Consumes: `identidadeConversa`, `prefixoPrevia`, `textoLimpo`, `marcaUsuario`, `chat.equipe_marcado`.

- [ ] **Step 1: Testes** em `naoLidaEquipe`/`addMessage`:
  - mensagem de colega que me marca → `equipe_marcado: true` na conversa;
  - mensagem sem marcação não apaga um `equipe_marcado` já true;
  - minha própria mensagem não acende;
  - ler (`markMessagesRead`) zera `equipe_marcado`;
  - `conversation.updated` sem o campo mantém o valor.
- [ ] **Step 2: Rodar.** Esperado: FAIL.
- [ ] **Step 3: Implementar** o campo junto de `naoLidaEquipe`, com `ADD_MESSAGE` copiando `equipe_marcado`.
- [ ] **Step 4: `ConversationCard.vue` na Equipe:** avatar 40, nome de `identidadeConversa`, sem `showMetaSection`, `LeadLinhaCard` e `CardLabels`, sem checkbox de seleção em lote; selo azul `@` antes do contador; hora verde quando há não lida. `MessagePreview.vue` recebe prop `equipe`: prefixo "Você:"/"Fulano:" e `textoLimpo`, sem o ícone de tipo de mensagem.
- [ ] **Step 5: Rodar.** Esperado: PASS.
- [ ] **Step 6: Commit** `feat(equipe): lista com cara de WhatsApp e selo de marcação`

### Task 7: Responder citando e digitando

**Files:**
- Modify: `components/widgets/conversation/MessagesView.vue` (`inboxSupportsReplyTo`), `ReplyBox.vue` (`shouldShowReplyToMessage`), `ReplyToMessage.vue`, `components-next/message/bubbles/Base.vue`
- Test: spec em `components-next/message/bubbles/specs/`

**Interfaces:**
- Consumes: `textoLimpo`; digitação já ligada ao topo na Task 5.

- [ ] **Step 1: Testes** da citação em `Base.vue`, na Equipe:
  - mostra nome do autor da mensagem citada ("Você" se minha);
  - citação só com anexo mostra o rótulo do anexo;
  - citação de mensagem apagada mostra o texto de apagada;
  - fora da Equipe, sem nome (nativo).
- [ ] **Step 2: Rodar.** Esperado: FAIL.
- [ ] **Step 3: Implementar.** Liberar os **dois** pontos só na Equipe; na resposta, enviar `in_reply_to` como no nativo; autor e fileta azul como no mockup; `ReplyToMessage.vue` com autor e `textoLimpo`.
- [ ] **Step 4: Rodar.** Esperado: PASS.
- [ ] **Step 5: Spec Ruby:** digitação de participante chega aos demais participantes e não ao autor, em `spec/listeners/action_cable_listener_spec.rb` (usa `typing_event_listener_tokens`).
- [ ] **Step 6: Commit** `feat(equipe): responder citando e digitando`

### Portão do Pacote 2

- [ ] Repetir o portão do Pacote 1 com `pacote2-*.png`: lista, selo @, citação, digitando.

---

## Pacote 3 — vistos

### Task 8: Vistos ✓✓

**Files:**
- Modify: `app/services/ramon/equipe.rb` (`marcar_lida`), `components/widgets/conversation/MessagesView.vue`, `helper/actionCable.js`, `components-next/message/MessageMeta.vue`, `MessageStatus.vue`
- Test: `spec/services/ramon/equipe_spec.rb`, `helper/specs/actionCable.spec.js`, spec de `MessageMeta`

**Interfaces:**
- Consumes: `estadoVisto`, `atualizarLeitura`.
- Produces: evento de cable `ramon.equipe.lida`, payload `{ conversation_id: <display_id>, user_id:, last_seen_at: <segundos>, account_id: }`, para participantes + admins da conta (`ActionCableBroadcastJob`).

- [ ] **Step 1: Specs Ruby**

```ruby
it 'transmite leitura quando havia mensagem de colega não lida' # have_enqueued_job(ActionCableBroadcastJob) com 'ramon.equipe.lida'
it 'não transmite sem nada novo'                                 # segunda chamada → nenhum job
it 'admin de fora não vira leitor'                               # marcar_lida(ana_bia, admin) sem efeito nem job
```

- [ ] **Step 2: Testes JS**
  - `onEquipeLida` chama `atualizarLeitura`;
  - `MessageMeta` na Equipe: minha mensagem com todos lendo → ✓✓ azul; faltando alguém → ✓✓ cinza e título "Visto por 1 de 2. Falta: Bia"; mensagem de colega → sem ✓✓;
  - quem saiu do chat não entra na conta.
- [ ] **Step 3: Rodar os JS.** Esperado: FAIL.
- [ ] **Step 4: Implementar `marcar_lida`:** calcula `nao_lidas` **antes** de gravar; transmite só se `> 0`.
- [ ] **Step 5: `MessagesView.vue`:** `makeMessagesRead` na Equipe só com `document.visibilityState === 'visible'`; listener de `visibilitychange` marca ao voltar, removido em `removeBusListeners`.
- [ ] **Step 6: Implementar `MessageMeta` e o evento em `actionCable.js`.**
- [ ] **Step 7: Rodar.** Esperado: PASS.
- [ ] **Step 8: Commit** `feat(equipe): vistos por pessoa`

### Portão do Pacote 3

- [ ] Repetir o portão com `pacote3-*.png`: ✓✓ cinza, azul e título de quem falta.

---

## Pacote 4 — reações e fechamento

### Task 9: Reações

**Files:**
- Modify: `app/services/ramon/equipe.rb`, `app/controllers/api/v1/accounts/ramon_equipe_controller.rb`, `config/routes.rb`, `app/javascript/dashboard/api/ramonEquipe.js`, `store/modules/conversations/actions.js` (`updateMessage`), `components-next/message/Message.vue`
- Create: `app/javascript/dashboard/routes/dashboard/ramon/components/equipe/EquipeReacoes.vue`
- Test: `spec/controllers/api/v1/accounts/ramon_equipe_controller_spec.rb`, `store/modules/specs/conversations/actions.spec.js`, spec de `EquipeReacoes`

**Interfaces:**
- Consumes: `EMOJIS_REACAO`, `resumoReacoes`, `participante?`.
- Produces:
  - `Ramon::Equipe.reagir(message, user, emoji) -> Message`, com `with_lock`, em `content_attributes['ramon_reacoes'] = [{ 'user_id', 'user_name', 'emoji' }]`;
  - `POST /ramon_equipe/reacao` com `{ conversation_id:, message_id:, emoji: }`;
  - `EquipeAPI.reagir(conversationId, messageId, emoji)`.

- [ ] **Step 1: Specs Ruby**

```ruby
it 'emoji novo soma, outro troca, o mesmo tira'  # 👍 → [👍]; ❤️ → [❤️]; ❤️ → []
it 'duas pessoas reagem sem se apagar'           # ana 👍 + bia 👍 → total 2
it 'emoji fora da lista: 422'
it 'quem não participa: 403, inclusive admin'
it 'mensagem apagada: 422'
it 'conversa fora da Equipe: 404'
it 'não gera notificação nem altera last_activity_at nem a não-lida'
```

- [ ] **Step 2: Testes JS**
  - `updateMessage` na Equipe ignora mensagem que não está carregada (não faz `ADD_MESSAGE`, não mexe no `timestamp` nem rola a tela);
  - `updateMessage` fora da Equipe segue igual;
  - `EquipeReacoes`: selo com total, nomes no título e estado `minha`; sem botões para quem não participa.
- [ ] **Step 3: Rodar os JS.** Esperado: FAIL.
- [ ] **Step 4: Implementar** serviço, controller e rota; `reagir` responde `head :ok`, e a tela atualiza pelo `message.updated`.
- [ ] **Step 5: Implementar** `updateMessage` e `EquipeReacoes.vue`, montado em `Message.vue` (barra ao passar o mouse com os 6 emojis e o botão responder; selos sob a bolha, como no mockup).
- [ ] **Step 6: Rodar.** Esperado: PASS.
- [ ] **Step 7: Commit** `feat(equipe): reações com emoji`

### Task 10: Documentos e smoke

**Files:**
- Modify: `docs/adr/0011-chat-da-equipe-como-caixa-do-chatwoot.md`, `docs/FORK-PONTOS-DE-REGISTRO.md`, `comercial\docs\2026-09-14-smoke-consolidado.md` (fora do repo)

- [ ] **Step 1: ADR 0011:** trocar o limite "Menção (@) não funciona" pela regra nova (só participantes, nunca adiciona, ramo próprio no `MentionService`); registrar admin de fora só leitura, apagar só autor ou admin participante, e-mail/push de menção só para quem ligou no perfil.
- [ ] **Step 2: `FORK-PONTOS-DE-REGISTRO.md`:** uma linha por ponto nativo novo: `mention_service.rb`, `notification.rb`, `messages_controller.rb`, `conversations_controller.rb`, `Message.vue`, `MessageList.vue`, `MessageMeta.vue`, `Base.vue`, `link.js`, `Editor.vue`, `ReplyBox.vue`, `ReplyBottomPanel.vue`, `TagAgents.vue`, `ReplyToMessage.vue`, `MessagesView.vue`, `ConversationHeader.vue`, `ConversationCard.vue`, `MessagePreview.vue`, `conversations/actions.js`, `conversations/index.js`, `actionCable.js`.
- [ ] **Step 3: Smoke:** reescrever a seção O em blocos para o Eduardo, cobrindo:
  - lados e nomes, Enter, áudio e anexo;
  - @ de pessoa e `@todos`, aviso "te marcou", selo que some ao ler;
  - admin de fora só leitura; colega sem poder apagar;
  - citação; digitando; ✓✓ em 1:1 e grupo; aba de fundo não marca como lida;
  - reação sem som; nada vira lead nem IA;
  - conversa com cliente igual a antes (bolhas, Enter, nota privada com @).
- [ ] **Step 4: Commit** `docs(equipe): ADR 0011, pontos do fork e roteiro de smoke`

### Portão do Pacote 4

- [ ] Repetir o portão com `pacote4-*.png`: barra de reações e selos. Depois do deploy, entregar a seção O ao Eduardo e atualizar a memória do projeto ([[equipe-chegada-chat-hub]], [[ramon-hub-plano-mestre-e-frentes]]).
