# Fatia 2 — Conversa em dock flutuante Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Abrir a conversa de um lead num **dock flutuante** (canto inferior direito, ~440×560) reusando a `ConversationBox` nativa, sem sair do Kanban; trocar o gatilho do card (ícone do canto → botão rotulado no rodapé) e fazer o "abrir conversa" (card/gaveta) abrir o dock em vez de navegar pra aba Conversas.

**Architecture:** Um `ConversationDock.vue` novo é montado no `KanbanBoard` como irmão do `LeadDrawer`. Estado mínimo `leads.dockConversationId` guarda a conversa aberta. O dock observa esse id, garante a conversa carregada no store (`conversations/getConversation`) e a torna ativa (`conversations/setActiveChat`), então renderiza a `ConversationBox` nativa (que lê `getSelectedChat`). O board passa a tratar `open-conversation` internamente (abrir dock) em vez de deixar `Funil.vue`/`KanbanView.vue` navegarem.

**Tech Stack:** Vue 3 (`<script setup>` novo; `ConversationBox` é Options API), Vuex, Vitest, Tailwind. Fork do Chatwoot v4.15.1, branch `ramon`. **Só frontend — sem migração.**

## Global Constraints

- Fork merge-safe: código novo sob `routes/dashboard/ramon/components/kanban/`; edições de arquivos `ramon/`-owned não precisam de FORK-PONTOS (não são upstream). Nenhum arquivo core (upstream) é editado nesta fatia (todos os alvos já são fork-owned: LeadCard/KanbanColumn/KanbanBoard/LeadDrawer/Funil/KanbanView/leads store; `ConversationBox` é só **consumida**, não editada).
- **Sem ambiente de teste local.** Verificação = feature branch → PR → CI (`run_foss_spec`). Só `npx prettier@3.3.3 --write` roda local. Specs TDD-first, raciocinar RED/GREEN, marcar "CI-deferred".
- **Sem migração.** `db/schema.rb` não muda. Deploy = pull + up (sem `db:migrate`).
- **MANTER o nome de evento `open-conversation` (kebab) verbatim** — é o que a A1 shipou e passa no CI; NÃO renomear pra `openConversation`. Não introduzir eventos custom novos nesta fatia (o dock fecha via `dispatch`, não via emit). `openLead` (camelCase) permanece como está.
- eslint: sem `:value=""`; **`mount` (não `shallowMount`)** pra componente dentro de slot de `<Draggable>`; specs de container stubam filhos pesados (`stubs: { ConversationBox: true, LeadDrawer: true }`); `useStore()` lê `vm.proxy.$store` → spec usa `plugins:[store]`. Mockar `vue-i18n` (`vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }))`) em componentes que usam `useI18n`.
- Regra de ouro: nada no ar sem OK do Eduardo; merge/deploy dele.

---

### Task 1: Estado do dock no módulo `leads`

**Files:**
- Modify: `app/javascript/dashboard/store/modules/leads.js`
- Modify: `app/javascript/dashboard/store/mutation-types.js`
- Test: `app/javascript/dashboard/store/modules/specs/leads/actions.spec.js` (+ getters/mutations specs conforme o layout existente)

**Interfaces:**
- Produces:
  - state `dockConversationId: null`
  - getter `leads/getDockConversationId` → id | null
  - action `leads/openDock(_ctx, conversationId)` → commit `SET_DOCK_CONVERSATION` com o id
  - action `leads/closeDock({ commit })` → commit `SET_DOCK_CONVERSATION` com `null`
  - mutation `SET_DOCK_CONVERSATION` seta `state.dockConversationId`

- [ ] **Step 1: teste que falha (getter + actions)**

```js
// actions.spec.js
describe('leads/openDock & closeDock', () => {
  it('openDock commits SET_DOCK_CONVERSATION with the id', () => {
    const commit = vi.fn();
    actions.openDock({ commit }, 42);
    expect(commit).toHaveBeenCalledWith('SET_DOCK_CONVERSATION', 42);
  });
  it('closeDock commits SET_DOCK_CONVERSATION with null', () => {
    const commit = vi.fn();
    actions.closeDock({ commit });
    expect(commit).toHaveBeenCalledWith('SET_DOCK_CONVERSATION', null);
  });
});
// getters.spec.js
it('getDockConversationId returns the dock id', () => {
  expect(getters.getDockConversationId({ dockConversationId: 7 })).toBe(7);
});
```
(Use as MESMAS constantes de mutation-type já usadas no módulo — confirme o import `types` no topo do `leads.js` e siga; nos specs, o valor literal `'SET_DOCK_CONVERSATION'` bate com o valor da constante.)

- [ ] **Step 2: rodar (CI) e ver falhar.**

- [ ] **Step 3: mutation-type** — em `store/mutation-types.js`, junto de `SET_SELECTED_LEAD`:
```js
SET_DOCK_CONVERSATION: 'SET_DOCK_CONVERSATION',
```

- [ ] **Step 4: state + getter + actions + mutation** — em `store/modules/leads.js`:
```js
// state: adicionar
dockConversationId: null,
// getters: adicionar
getDockConversationId: _state => _state.dockConversationId,
// actions: adicionar
openDock: ({ commit }, conversationId) => commit(types.SET_DOCK_CONVERSATION, conversationId),
closeDock: ({ commit }) => commit(types.SET_DOCK_CONVERSATION, null),
// mutations: adicionar
[types.SET_DOCK_CONVERSATION](_state, id) { _state.dockConversationId = id; },
```

- [ ] **Step 5: rodar (CI) e ver passar.**

- [ ] **Step 6: Prettier + Commit**
```bash
npx prettier@3.3.3 --write app/javascript/dashboard/store/modules/leads.js app/javascript/dashboard/store/mutation-types.js
git add app/javascript/dashboard/store/modules/leads.js app/javascript/dashboard/store/mutation-types.js \
        app/javascript/dashboard/store/modules/specs/leads
git commit -m "feat: add dockConversationId state to leads store"
```

---

### Task 2: `ConversationDock.vue` — o dock flutuante

**Files:**
- Create: `app/javascript/dashboard/routes/dashboard/ramon/components/kanban/ConversationDock.vue`
- Create: `app/javascript/dashboard/routes/dashboard/ramon/components/kanban/specs/ConversationDock.spec.js`

**Interfaces:**
- Consumes: `leads/getDockConversationId`, `leads/getSelectedLead`, `leads/closeDock` (Task 1); `conversations/getConversationById`, `conversations/getConversation`, `conversations/setActiveChat`; `ConversationBox` (`components/widgets/conversation/ConversationBox.vue`).
- Produces: componente que renderiza a conversa ativa num dock fixo quando `dockConversationId` != null.

Notas de integração (confirmadas no código real):
- `ConversationBox` (Options API) NÃO recebe a conversa por prop — lê `getSelectedChat`. Props úteis: `:inbox-id`, `:is-inbox-view="false"`. Então o dock só precisa **tornar a conversa ativa** e renderizar `<ConversationBox>`.
- `conversations/getConversation(id)` carrega a conversa no store (`ConversationApi.show`). `conversations/setActiveChat({ data: conversation })` — **payload é `{ data: <objeto conversa> }`**, não id. `getConversationById(id)` acha no store.

- [ ] **Step 1: spec que falha**

```js
import { mount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import ConversationDock from '../ConversationDock.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));

const chat = { id: 42, inbox_id: 3, meta: { sender: { name: 'Zé' } } };
const build = ({ dockId = 42, hasChat = true, lead = null } = {}) => {
  const getConversation = vi.fn().mockResolvedValue();
  const setActiveChat = vi.fn();
  const closeDock = vi.fn();
  const store = createStore({
    modules: {
      leads: { namespaced: true, getters: {
        getDockConversationId: () => dockId, getSelectedLead: () => lead },
        actions: { closeDock } },
      conversations: { namespaced: true, getters: {
        getConversationById: () => id => (hasChat ? chat : undefined) },
        actions: { getConversation, setActiveChat } },
    },
  });
  return { store, getConversation, setActiveChat, closeDock };
};
const mountDock = ctx => {
  const { store, ...spies } = build(ctx);
  const wrapper = mount(ConversationDock, {
    global: { plugins: [store], mocks: { $t: k => k }, stubs: { ConversationBox: true } },
  });
  return { wrapper, ...spies };
};

it('fetches the conversation when absent, then activates it', async () => {
  const { getConversation, setActiveChat } = mountDock({ hasChat: false });
  await flushPromises();
  expect(getConversation).toHaveBeenCalledWith(expect.anything(), 42);
  expect(setActiveChat).toHaveBeenCalledWith(expect.anything(), { data: expect.any(Object) });
});

it('does not refetch when the conversation is already in the store', async () => {
  const { getConversation, setActiveChat } = mountDock({ hasChat: true });
  await flushPromises();
  expect(getConversation).not.toHaveBeenCalled();
  expect(setActiveChat).toHaveBeenCalledWith(expect.anything(), { data: chat });
});

it('closes via the X button', async () => {
  const { wrapper, closeDock } = mountDock({});
  await flushPromises();
  await wrapper.find('[data-testid="dock-close"]').trigger('click');
  expect(closeDock).toHaveBeenCalled();
});

it('shifts left when the lead drawer is open', async () => {
  const { wrapper } = mountDock({ lead: { id: 1 } });
  await flushPromises();
  expect(wrapper.find('[data-testid="conversation-dock"]').classes().join(' ')).toContain('right-[25rem]');
});
```

- [ ] **Step 2: rodar (CI) e ver falhar.**

- [ ] **Step 3: implementar `ConversationDock.vue`**

```vue
<script setup>
import { computed, watch } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import ConversationBox from 'dashboard/components/widgets/conversation/ConversationBox.vue';

defineOptions({ name: 'ConversationDock' });

const store = useStore();
const dockId = useMapGetter('leads/getDockConversationId');
const selectedLead = useMapGetter('leads/getSelectedLead');

const chat = computed(() =>
  store.getters['conversations/getConversationById'](dockId.value)
);
const isOpen = computed(() => !!dockId.value);
const drawerOpen = computed(() => !!selectedLead.value);
const contactName = computed(() => chat.value?.meta?.sender?.name || '');

const activate = async id => {
  if (!id) return;
  if (!store.getters['conversations/getConversationById'](id)) {
    await store.dispatch('conversations/getConversation', id);
  }
  const conversation = store.getters['conversations/getConversationById'](id);
  if (conversation) {
    store.dispatch('conversations/setActiveChat', { data: conversation });
  }
};
watch(dockId, activate, { immediate: true });

const close = () => store.dispatch('leads/closeDock');
</script>

<template>
  <div
    v-if="isOpen"
    data-testid="conversation-dock"
    class="fixed z-50 inset-0 flex flex-col overflow-hidden bg-n-solid-1 border-n-weak shadow-lg md:inset-auto md:bottom-4 md:h-[560px] md:w-[440px] md:rounded-lg md:border"
    :class="drawerOpen ? 'md:right-[25rem]' : 'md:right-4'"
  >
    <header class="flex items-center gap-2 px-3 py-2 border-b border-n-weak">
      <span class="flex-1 text-sm font-medium text-n-slate-12 truncate">{{ contactName }}</span>
      <button
        data-testid="dock-close"
        class="text-n-slate-10 hover:text-n-slate-12"
        @click="close"
      >
        <span class="i-lucide-x size-4" />
      </button>
    </header>
    <div class="flex-1 min-h-0">
      <ConversationBox :inbox-id="chat?.inbox_id" :is-inbox-view="false" />
    </div>
  </div>
</template>
```

Confirme antes de codar: (a) o composable `useMapGetter`/`useStore` (mesmo dos outros `ramon/`); (b) que `ConversationBox` renderiza ok dentro de um container `flex-1 min-h-0` (ela assume altura — se ficar sem altura, o container precisa de altura definida; o `md:h-[560px]` no pai + `flex-1` resolve; calibrar pós-deploy). (c) `i-lucide-x` existe no fork (mesmo esquema dos outros ícones `i-lucide-*`).

- [ ] **Step 4: rodar (CI) e ver passar.**

- [ ] **Step 5: Prettier + Commit**
```bash
npx prettier@3.3.3 --write app/javascript/dashboard/routes/dashboard/ramon/components/kanban
git add app/javascript/dashboard/routes/dashboard/ramon/components/kanban/ConversationDock.vue \
        app/javascript/dashboard/routes/dashboard/ramon/components/kanban/specs/ConversationDock.spec.js
git commit -m "feat: add ConversationDock floating conversation panel"
```

---

### Task 3: `LeadCard` — botão no rodapé (remove o ícone do canto)

**Files:**
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/components/kanban/LeadCard.vue`
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/components/kanban/specs/LeadCard.spec.js`

**Interfaces:**
- Mantém o emit **`open-conversation`** (kebab, verbatim — NÃO renomear) com `lead.conversation_id`; mantém `openLead` no corpo.

- [ ] **Step 1: atualizar o spec (falha)**

```js
it('shows a labeled "open conversation" button in the footer only with conversation_id', () => {
  const wrapper = mountCard({ lead: { ...leadBase, conversation_id: 99 } });
  const btn = wrapper.find('[data-testid="open-conversation"]');
  expect(btn.exists()).toBe(true);
  expect(btn.text()).toContain('RAMON.FUNIL.OPEN_CONVERSATION'); // rótulo via $t (mock = key)
});
it('emits open-conversation with the id and does not open the lead', async () => {
  const wrapper = mountCard({ lead: { ...leadBase, conversation_id: 99 } });
  await wrapper.find('[data-testid="open-conversation"]').trigger('click');
  expect(wrapper.emitted('open-conversation')[0]).toEqual([99]);
  expect(wrapper.emitted('openLead')).toBeFalsy();
});
it('hides the button without conversation_id', () => {
  const wrapper = mountCard({ lead: { ...leadBase, conversation_id: null } });
  expect(wrapper.find('[data-testid="open-conversation"]').exists()).toBe(false);
});
```
(Remova a asserção antiga que esperava o ícone no canto; mantenha o teste do clique no corpo → `openLead`.)

- [ ] **Step 2: rodar (CI) e ver falhar.**

- [ ] **Step 3: editar `LeadCard.vue`**

Remover o `<button data-testid="open-conversation">` do canto (o ícone `i-lucide-message-square` `@click.stop`). Adicionar no **rodapé** do card um botão rotulado:
```html
<button
  v-if="lead.conversation_id"
  data-testid="open-conversation"
  class="flex items-center justify-center gap-1.5 w-full mt-2 px-2 py-1.5 text-xs rounded-lg border border-n-weak text-n-slate-11 hover:text-n-iris-11 hover:border-n-iris-8"
  @click.stop="emit('open-conversation', lead.conversation_id)"
>
  <span class="i-lucide-message-square size-3.5" />{{ $t('RAMON.FUNIL.OPEN_CONVERSATION') }}
</button>
```
Mantém `@click.stop` (não dispara `openLead` do corpo). O clique no corpo do card segue emitindo `openLead`. Reusa classes já presentes no card (ajuste finos de estilo são calibração).

- [ ] **Step 4: rodar (CI) e ver passar.**

- [ ] **Step 5: Prettier + Commit**
```bash
npx prettier@3.3.3 --write app/javascript/dashboard/routes/dashboard/ramon/components/kanban
git add app/javascript/dashboard/routes/dashboard/ramon/components/kanban/LeadCard.vue \
        app/javascript/dashboard/routes/dashboard/ramon/components/kanban/specs/LeadCard.spec.js
git commit -m "feat: labeled open-conversation button in LeadCard footer"
```

---

### Task 4: `KanbanBoard` — abrir o dock internamente + montar `ConversationDock`

**Files:**
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/components/kanban/KanbanBoard.vue`
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/components/kanban/specs/KanbanBoard.spec.js`

**Interfaces:**
- Consumes: `leads/openDock` (Task 1), `ConversationDock` (Task 2), o evento `open-conversation` das colunas e do `LeadDrawer`.
- **Muda o contrato:** o board deixa de **emitir** `open-conversation` pra cima; passa a **tratar** internamente (`leads/openDock`). Remover `'open-conversation'` do `defineEmits`.

- [ ] **Step 1: atualizar o spec (falha)**

```js
it('opens the dock (dispatch leads/openDock) when a column emits open-conversation', async () => {
  const wrapper = mountBoard(); // helper existente, store.dispatch = dispatch spy
  wrapper.findComponent(KanbanColumn).vm.$emit('open-conversation', 55);
  await wrapper.vm.$nextTick();
  expect(dispatch).toHaveBeenCalledWith('leads/openDock', 55);
});
it('mounts the ConversationDock', () => {
  const wrapper = mountBoard();
  expect(wrapper.findComponent({ name: 'ConversationDock' }).exists()).toBe(true);
});
```
(No `mountBoard`, adicione `ConversationDock: true` e `LeadDrawer: true` aos `stubs`.)

- [ ] **Step 2: rodar (CI) e ver falhar.**

- [ ] **Step 3: editar `KanbanBoard.vue`**

- Importar `ConversationDock` e adicionar `<ConversationDock />` como irmão do `<LeadDrawer />` (mesma div raiz).
- Adicionar handler:
```js
const onOpenConversation = id => store.dispatch('leads/openDock', id);
```
- Trocar a re-emissão da coluna de `@open-conversation="id => emit('open-conversation', id)"` para `@open-conversation="onOpenConversation"`.
- Trocar o `<LeadDrawer @open-conversation="id => emit('open-conversation', id)" />` para `<LeadDrawer @open-conversation="onOpenConversation" />`.
- Remover `'open-conversation'` do `defineEmits` do board (mantém `'new-lead'`). (Confirme se algo mais depende desse emit — as páginas Funil/KanbanView param de escutar na Task 5.)

- [ ] **Step 4: rodar (CI) e ver passar.**

- [ ] **Step 5: Prettier + Commit**
```bash
npx prettier@3.3.3 --write app/javascript/dashboard/routes/dashboard/ramon/components/kanban
git add app/javascript/dashboard/routes/dashboard/ramon/components/kanban/KanbanBoard.vue \
        app/javascript/dashboard/routes/dashboard/ramon/components/kanban/specs/KanbanBoard.spec.js
git commit -m "feat: KanbanBoard opens conversation dock instead of bubbling up"
```

---

### Task 5: `Funil.vue` + `KanbanView.vue` param de navegar

**Files:**
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/pages/Funil.vue`
- Modify: `app/javascript/dashboard/routes/dashboard/conversation/KanbanView.vue`

**Interfaces:**
- Consome: o board agora trata `open-conversation` sozinho (Task 4). Estas páginas removem a navegação pra `inbox_conversation`.

- [ ] **Step 1: editar `Funil.vue`**

Remover o handler `openConversation` (o `router.push({ name: 'inbox_conversation', ... })`) e a ligação `@open-conversation="openConversation"` no `<KanbanBoard>`. Se `router`/`route` ficarem sem uso após isso, remover os imports órfãos (evita eslint `no-unused-vars`). Manter o resto (`@new-lead`, modal).

- [ ] **Step 2: editar `KanbanView.vue`**

Idêntico: remover o `openConversation` (router.push) e o `@open-conversation` do `<KanbanBoard>`; limpar imports órfãos (`useRouter`/`useRoute`) se ficarem sem uso.

- [ ] **Step 3: (sem spec dedicada — são páginas finas; a mudança é remoção)** Rodar o raciocínio: nada mais chama `openConversation` nessas páginas; o board absorve. Se houver spec de Funil/KanbanView que asserta navegação, atualizar. (Provavelmente não há.)

- [ ] **Step 4: Prettier + Commit**
```bash
npx prettier@3.3.3 --write app/javascript/dashboard/routes/dashboard/ramon/pages/Funil.vue \
        app/javascript/dashboard/routes/dashboard/conversation/KanbanView.vue
git add app/javascript/dashboard/routes/dashboard/ramon/pages/Funil.vue \
        app/javascript/dashboard/routes/dashboard/conversation/KanbanView.vue
git commit -m "feat: stop navigating to inbox on open-conversation (dock handles it)"
```

---

### Task 6: PR, CI, deploy (sem migração), smoke

**Files:** nenhum de app.

- [ ] **Step 1: Push + PR** contra `ramon`, título `feat: conversa em dock flutuante sobre o Kanban`. Sem migração.

- [ ] **Step 2: CI `run_foss_spec` verde** — aplicar lições: prettier em TODO `ramon/` tocado antes do push; sem bare strings; `mount` p/ componentes em slot de Draggable; `useStore` precisa `plugins:[store]`; evento `open-conversation` mantido verbatim.

- [ ] **Step 3: Merge (OK do Eduardo).**

- [ ] **Step 4: Deploy VPS (OK explícito do Eduardo) — SEM migração:** `docker compose pull chatwoot-web chatwoot-worker && docker compose up -d chatwoot-web chatwoot-worker`. Smoke: no Kanban, clicar "Abrir conversa" no rodapé de um card com conversa → dock aparece no canto com a thread; responder; abrir a gaveta do mesmo lead → dock desloca pra esquerda e coexiste; X fecha o dock; a gaveta abre o dock também.

---

## Self-Review

**Spec coverage (contra `2026-06-30-ramon-hub-conversa-dock-botao-card-design.md`):**
- Dock flutuante canto inf. direito ~440×560, `ConversationBox` nativa → Task 2. ✅
- Convive com a gaveta, desloca à esquerda quando aberta → Task 2 (drawerOpen → `md:right-[25rem]`). ✅
- Botão rotulado no rodapé do card, remove ícone do canto → Task 3. ✅
- Gaveta abre o dock (não navega) → Task 4 (LeadDrawer `@open-conversation` → onOpenConversation). ✅
- Board trata internamente; Funil/KanbanView param de navegar → Tasks 4-5. ✅
- Estado `dockConversationId` no módulo leads → Task 1. ✅
- Fluxo getConversation→setActiveChat({data}) → Task 2. ✅
- Mobile full-screen abaixo de md → Task 2 (`inset-0 md:inset-auto`). ✅
- **Layering (overlay da gaveta vs dock):** dock `z-50` acima do overlay `z-40` da gaveta → Task 2. Risco honesto: o overlay escuro `bg-black/40` da gaveta continua atrás; se atrapalhar visualmente, calibração pós-deploy (baixar o overlay ou z-index) — anotado, não bloqueia.

**Placeholder scan:** sem TBD; cada passo tem código. "Confirme no código real" (composable, altura da ConversationBox, ícone lucide) são verificações do executor.

**Type consistency:** `dockConversationId`/`getDockConversationId`/`openDock`/`closeDock`/`SET_DOCK_CONVERSATION`; evento `open-conversation` (kebab) preservado ponta-a-ponta (LeadCard→KanbanColumn→KanbanBoard); `setActiveChat({ data })`; `getConversationById(id)`. Consistentes Tasks 1→5.

**Riscos abertos (calibração, não bloqueiam):** (1) `ConversationBox` em ~440px fica compacta (spec §80); (2) `setActiveChat` marca a conversa como selecionada global (spec §79) — efeito colateral aceito; (3) overlay da gaveta atrás do dock (acima).
