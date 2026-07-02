# Conversa em dock + botão no card (design)

> Fork `ramon-hub` (Chatwoot v4.15.1, Rails 7.1 + Vue 3/Vuex). Fatia de refinamento sobre a **A1** (já no ar, merge `73a869e92`). Aditivo. Surgiu do smoke visual da A1: o Eduardo aprovou o card rico/gaveta, mas pediu (1) abrir a conversa SEM sair do Kanban e (2) o gatilho como botão no card, não o ícone do canto.

## Objetivo

Abrir a conversa de um lead num **dock flutuante** no canto inferior direito do Kanban (reusando a thread nativa do Chatwoot — ler + responder), sem navegar pra aba Conversas. E trocar o gatilho: de ícone no canto do card → **botão rotulado no rodapé do card**. O dock convive com o painel do lead (gaveta) já existente.

## Decisões travadas (brainstorm 30/06, confirmadas pelo Eduardo)

- **Formato:** dock **flutuante no canto inferior direito** (~440×560 px), `position: fixed`, por cima do Kanban. NÃO é modal full-screen, NÃO é split, NÃO é dentro da gaveta.
- **Thread:** reutiliza **`ConversationBox`** nativo (mensagens + caixa de resposta) — não reimplementa thread.
- **Convivência com a gaveta do lead:** o dock e a gaveta (`LeadDrawer`, `leads.selectedId`) podem estar abertos ao mesmo tempo. Quando a gaveta está aberta, o dock **desloca pra esquerda** pela largura da gaveta (~384px), "grudando" à esquerda dela. Cada painel fecha no seu próprio X.
- **Gatilho no card:** remove o **ícone do canto** do `LeadCard`; adiciona **botão rotulado "💬 Abrir conversa"** no rodapé do card, visível só quando `lead.conversation_id` existe. O clique no **corpo** do card continua abrindo a gaveta.
- **Gatilho na gaveta:** o `LeadDrawer` mantém o botão "Abrir conversa", mas ele passa a abrir o **dock** (em vez de navegar pra `inbox_conversation`).
- **Mobile/telas estreitas:** o dock ocupa a tela toda (vira full-screen abaixo de um breakpoint).
- **Fora de escopo:** redimensionar/arrastar o dock, minimizar, múltiplos docks simultâneos.

## Arquitetura

Casca = Kanban (mundo Intranet e mundo Conversas, board compartilhado). O dock é um componente novo montado no board, irmão do `LeadDrawer`. A thread em si é 100% nativa (`ConversationBox`), que lê a conversa "ativa" do store global (`getSelectedChat`). Abrir o dock = tornar a conversa do lead a ativa e renderizar a `ConversationBox`.

### Componentes (namespace `ramon/`, pasta `routes/dashboard/ramon/components/kanban/`)

- **`ConversationDock.vue` (novo)** — responsabilidade única: exibir a conversa ativa num dock fixo.
  - `position: fixed`, canto inferior direito, ~440×560. `z-index` acima do board, compatível com a gaveta (`LeadDrawer` usa `z-40`; ver "Layering").
  - Cabeçalho próprio: nome do contato da conversa + botão **X** (fecha).
  - Corpo: `<ConversationBox :inbox-id="inboxId" :is-inbox-view="false" />` (a `ConversationBox` lê `currentChat = getSelectedChat` do store).
  - Lê `openConversationId` do store; quando muda, garante a conversa carregada e ativa (ver Fluxo).
  - `inboxId` = `conversa.inbox_id` (obtido do objeto da conversa após carregá-la).
  - Posição reativa: se a gaveta está aberta (`leads/getSelectedLead` != null), aplica `right` = largura-da-gaveta (≈ `24rem`/384px) em vez de `0`; senão encosta na borda. Transição suave.
  - Abaixo do breakpoint `md`: ocupa a viewport inteira (full-screen).

- **`LeadCard.vue` (editar)** — remove o `<button data-testid="open-conversation">` do canto. Adiciona no rodapé do card um botão rotulado `[💬 Abrir conversa]` (`data-testid="open-conversation"`), `v-if="lead.conversation_id"`, com `@click.stop="emit('openConversation', lead.conversation_id)"` (mantém `.stop` pra não abrir a gaveta junto). O clique no corpo segue emitindo `openLead`.

- **`KanbanColumn.vue` (editar)** — re-emite `openConversation` do `LeadCard` pra cima (já re-emite `openLead`/`open-conversation`; manter o repasse com o nome de evento camelCase exigido pelo eslint — ver "Convenções").

- **`KanbanBoard.vue` (editar)** — monta `<ConversationDock />` (irmão do `<LeadDrawer />`). No handler de `openConversation(conversationId)` (vindo da coluna OU da gaveta): dispatch da action que abre o dock (`conversationDock/open` ou `leads/openConversation`, casa definida no plano) com o `conversationId`. NÃO navega mais.

- **`LeadDrawer.vue` (editar)** — o botão "Abrir conversa" troca o emit/navegação por: dispatch da mesma action de abrir o dock com `lead.conversation_id`. (A gaveta continua aberta; o dock aparece grudado à esquerda dela.)

- **`Funil.vue` / `KanbanView.vue` (verificar/editar)** — hoje têm `openConversation` que faz `router.push({name:'inbox_conversation'})`. Esse comportamento de navegar **sai de cena**: o board passa a tratar `openConversation` internamente (abrir dock). Confirmar no plano que esses dois arquivos não precisam mais rotear (o board absorve, como fez com `openLead` na A1).

### Estado (Vuex)

Um identificador da conversa aberta no dock: `openConversationId` (id; `null` = dock fechado). Casa exata (módulo `conversations` novo campo vs. módulo `leads` vs. módulo `ramon` novo) decidida no plano — preferência: um pequeno estado no módulo `leads` (`dockConversationId`) ou um módulo `ramon/ui` dedicado, pra não inchar `conversations`. Getter `getDockConversationId`, actions `openConversation(id)` / `closeConversation()`.

### Fluxo de dados

**Abrir:** botão (card ou gaveta) → `dispatch('…/openConversation', conversationId)` → seta `dockConversationId`. O `ConversationDock` observa (`watch`) `dockConversationId`:
1. Se a conversa não está no store (`conversations/getConversationById(id)` vazio) → `dispatch('conversations/getConversation', id)` (API `ConversationApi.show` → carrega no store).
2. `dispatch('conversations/setActiveChat', { data: conversa })` → vira a conversa ativa global.
3. Renderiza `ConversationBox` com `inboxId = conversa.inbox_id`.

**Fechar:** X no dock → `dispatch('…/closeConversation')` → `dockConversationId = null` → dock desmonta. (Não limpamos o `selectedChatId` global — deixamos a seleção como está; baixo impacto.)

### Layering / posição

- `LeadDrawer` hoje: overlay `fixed inset-0 z-40` + `<aside>` à direita (largura ~`w-96` = 24rem). O dock deve conviver: dock `z-30` (abaixo do overlay da gaveta? — definir), OU a gaveta deixa de usar overlay full-screen pra permitir os dois lado a lado. **Decisão de design:** como os dois coexistem, a **gaveta não deve bloquear o dock**. No plano, ajustar o `LeadDrawer` pra que seu overlay clicável-fora não cubra o dock (ex.: remover o overlay full-screen escuro quando coexistindo, ou baixar z-index). Pinar no plano contra o CSS real.
- Dock: `fixed bottom-0 right-0` (com pequena margem), e `right` deslocado por `var(--lead-drawer-width, 24rem)` quando a gaveta está aberta.

## Convenções / lições da A1 (obrigatórias)

- **Evento custom Vue = camelCase** (`vue/custom-event-name-casing: ['error','camelCase']`): emitir `openConversation` (NÃO `open-conversation`). Listener no template fica **kebab** (`@open-conversation`) — o Vue 3 mapeia. (Mesma lição do `openLead` na A1.)
- **Sem `:value="''"`** literal (`vue/no-useless-v-bind`) — usar `value=""`.
- **prettier** roda local; **vitest/eslint/rubocop só no CI** (sem env local). Schema não muda (esta fatia é só front).
- **`mount` (não `shallowMount`)** pra testar componente dentro de slot de `Draggable`.

## Testes (vitest)

- **`ConversationDock`:** com `dockConversationId` setado e conversa ausente → dispara `conversations/getConversation` + `setActiveChat`; renderiza `ConversationBox` (stubado) com o `inboxId` certo; X → dispatch close; quando `getSelectedLead` != null → aplica o deslocamento à esquerda (classe/estilo). Conversa já no store → não refetcha (só setActiveChat).
- **`LeadCard`:** botão "Abrir conversa" só aparece com `conversation_id`; emite `openConversation` com o id; **não** existe mais ícone no canto; clique no corpo ainda emite `openLead`; `@click.stop` no botão não dispara `openLead`.
- **`KanbanBoard`:** `openConversation` de uma coluna/gaveta → dispatch da action de abrir dock (não navega). Monta o `ConversationDock`.
- **`LeadDrawer`:** botão "Abrir conversa" → dispatch de abrir dock com `lead.conversation_id` (não navega).
- Verificação real = feature branch → PR → CI (`run_foss_spec`).

## Riscos / notas (honestos)

1. **Acoplamento global:** `setActiveChat` define a conversa ativa GLOBAL (mesma da aba Conversas). Abrir pelo dock marca essa conversa como selecionada lá também — tolerável/esperado, mas é efeito colateral, não isolamento. Se incomodar, fatia futura isola.
2. **Largura:** `ConversationBox` é desenhada pra largura cheia; em ~440px fica compacta (estilo widget). Usável, calibração visual provável pós-deploy.
3. **Overlay da gaveta vs. dock:** precisa garantir que a gaveta não capture cliques do dock (ajuste de z-index/overlay no plano).
4. **`ConversationBox` dependências:** lê `getSelectedChat`; pode disparar fetch de labels/agents da conversa (efeitos nativos) — aceitável.

## Fora de escopo (fatias futuras)

- Redimensionar/arrastar/minimizar o dock; múltiplos docks; histórico de conversas do lead; isolar a conversa do dock da seleção global da aba Conversas.
