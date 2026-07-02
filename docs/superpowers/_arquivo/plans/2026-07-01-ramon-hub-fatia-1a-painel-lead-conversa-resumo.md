# Fatia 1a — Painel do Lead na conversa (aba Resumo) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Substituir o iframe `/embed/kit` legado na conversa por um Painel do Lead nativo em Vue, com a aba **Resumo** (dados do lead editáveis + ações nativas da conversa embutidas), criando/achando o Lead pela conversa e permitindo descartar.

**Architecture:** Backend ganha um endpoint idempotente "acha-ou-cria lead por conversa" (sem migração — usa colunas existentes). Frontend extrai o miolo de campos do `LeadDrawer` para um componente compartilhado `LeadFields.vue`, e monta um `LeadConversationPanel.vue` (contêiner de abas; só Resumo nesta fatia) que o `ConversationSidebar.vue` renderiza no lugar do `ContactPanel` nativo. O painel carrega o lead da conversa via store e embute os componentes nativos de ação.

**Tech Stack:** Ruby on Rails (API), Vue 3 `<script setup>` + Vuex, RSpec (request specs), Vitest (`@vue/test-utils` + `vuex createStore`), Tailwind. Fork do Chatwoot v4.15.1, branch `ramon`.

## Global Constraints

- Fork merge-safe: código novo **sob `app/javascript/dashboard/routes/dashboard/ramon/`** ou backend fork-owned; **toda edição de arquivo core (upstream) deve ser registrada** em `docs/FORK-PONTOS-DE-REGISTRO.md` (file, trecho/linhas, motivo, fase).
- **Sem ambiente de teste local** (máquina do Eduardo não roda Ruby/pnpm/Postgres). Verificação = feature branch → PR → CI (`run_foss_spec` roda rspec+vitest+rubocop+eslint no `pull_request`; NÃO dispara em push pra `ramon`).
- CI do fork **carrega schema via `db:schema:load`**, não roda migrations. **Esta fatia 1a NÃO tem migração** → `db/schema.rb` fica intacto.
- **Prettier obrigatório** em todo `ramon/` (`npx prettier@3.3.3 --write`); eslint do fork só falha em *error* (não `--max-warnings 0`).
- **Evento custom Vue = camelCase** na emissão (`vue/custom-event-name-casing`) e listener em **kebab** no template (`vue/v-on-event-hyphenation`).
- **Componente dentro de slot de `<Draggable>` só é encontrável com `mount`**, não `shallowMount` (não se aplica aqui, mas vale pra specs que tocem o board).
- Rubocop: `Rails/SkipsModelValidations` pega `update_all`/`update_column` (usar `update!` ou inline disable); métodos com muitos `&.` estouram `CyclomaticComplexity` (inline disable pontual).
- Regra de ouro: **nada vai pro ar sem OK explícito do Eduardo**; deploy (pull + restart) é feito pelo Claude via SSH só com autorização dele.
- i18n: textos em `app/javascript/dashboard/i18n/locale/{en,pt_BR}/ramon.json`, **registrados** em `i18n/locale/{en,pt_BR}/index.js` (import + spread) — senão vêm crus.

---

### Task 1: Endpoint "acha-ou-cria lead por conversa" (backend)

Adiciona `POST /api/v1/accounts/:account_id/leads/for_conversation` que recebe `conversation_id`, devolve o Lead existente da conversa OU cria um novo na etapa padrão ("Novo"), dedupando por `conversation_id`. Sem migração.

**Files:**
- Modify: `config/routes.rb` (bloco `resources :leads`, ~linha 286)
- Modify: `app/controllers/api/v1/accounts/leads_controller.rb`
- Test: `spec/controllers/api/v1/accounts/leads_controller_spec.rb` (criar se não existir; senão adicionar contexto)
- Modify: `docs/FORK-PONTOS-DE-REGISTRO.md`

**Interfaces:**
- Produces: `POST .../leads/for_conversation` body `{ conversation_id: <int> }` → 200 com o JSON do lead (mesmo shape do `_lead.json.jbuilder`). Idempotente: mesma conversa devolve o mesmo lead.
- Consumes: `Current.account.leads`, `Current.account.lead_stages`, resolução da etapa padrão idêntica à do `app/listeners/ramon_lead_listener.rb`.

- [ ] **Step 1: Ler o listener pra reusar a resolução da etapa "Novo"**

Leia `app/listeners/ramon_lead_listener.rb` e identifique como ele resolve a etapa inicial e monta o nome do lead (name = `contact.name || phone_number || identifier`). Reuse a MESMA lógica no controller (DRY). Se o listener usar um método/serviço, chame-o; se for inline, replique exatamente o mesmo critério (etapa padrão = a etapa "Novo" — pela seed é a de menor `position`).

- [ ] **Step 2: Escrever o request spec que falha**

```ruby
# spec/controllers/api/v1/accounts/leads_controller_spec.rb  (contexto novo)
RSpec.describe 'Leads for_conversation API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }

  describe 'POST /api/v1/accounts/{account}/leads/for_conversation' do
    it 'creates a lead in the default stage when none exists' do
      expect do
        post "/api/v1/accounts/#{account.id}/leads/for_conversation",
             params: { conversation_id: conversation.id },
             headers: admin.create_new_auth_token, as: :json
      end.to change(account.leads, :count).by(1)
      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['conversation_id']).to eq(conversation.id)
      expect(body['stage_name']).to be_present
    end

    it 'returns the existing lead without creating a duplicate' do
      existing = account.leads.create!(conversation: conversation, contact: contact,
                                       lead_stage: account.lead_stages.order(:position).first,
                                       name: 'X')
      expect do
        post "/api/v1/accounts/#{account.id}/leads/for_conversation",
             params: { conversation_id: conversation.id },
             headers: admin.create_new_auth_token, as: :json
      end.not_to(change(account.leads, :count))
      expect(response.parsed_body['id']).to eq(existing.id)
    end
  end
end
```

- [ ] **Step 3: Rodar o spec e ver falhar**

Este passo roda no CI (sem env local). Localmente só confirme que o arquivo existe. Esperado no CI: FAIL (rota inexistente → `ActionController::RoutingError`).

- [ ] **Step 4: Adicionar a rota**

Em `config/routes.rb`, transforme a linha `resources :leads, only: [...]` no bloco:

```ruby
resources :leads, only: [:index, :show, :create, :update, :destroy] do
  collection do
    post :for_conversation
  end
end
```

- [ ] **Step 5: Implementar a action no controller**

Em `app/controllers/api/v1/accounts/leads_controller.rb`, adicione (usando a resolução de etapa/nome lida no Step 1):

```ruby
def for_conversation
  conversation = Current.account.conversations.find(params[:conversation_id])
  @lead = Current.account.leads.find_by(conversation_id: conversation.id)
  @lead ||= create_lead_for(conversation)
  authorize(@lead)
  render 'api/v1/accounts/leads/show'
end

private

def create_lead_for(conversation)
  Current.account.leads.create!(
    conversation: conversation,
    contact: conversation.contact,
    lead_stage: default_lead_stage,
    name: lead_name_for(conversation)
  )
end

def default_lead_stage
  Current.account.lead_stages.order(:position).first
end

def lead_name_for(conversation)
  contact = conversation.contact
  contact&.name.presence || contact&.phone_number.presence || contact&.identifier.presence || "Lead ##{conversation.display_id}"
end
```

Confirme que existe a view `app/views/api/v1/accounts/leads/show.json.jbuilder` (renderiza `_lead`); se o padrão do controller for outro (ex.: `render json:`), siga o padrão já usado em `show`/`create` deste mesmo controller.

- [ ] **Step 6: Garantir autorização (Pundit)**

Confirme na `LeadPolicy` que admin e agent podem `create?`/`show?`. Se `authorize(@lead)` exigir uma action mapeada, use `authorize(@lead, :show?)`. Rode o raciocínio: o controller usa `check_authorization` — a nova action precisa de `authorize`.

- [ ] **Step 7: Registrar no FORK-PONTOS**

Adicione linha em `docs/FORK-PONTOS-DE-REGISTRO.md`: `config/routes.rb` — collection route `for_conversation` em `leads` — motivo: painel do lead na conversa acha-ou-cria — fase 1a.

- [ ] **Step 8: Commit**

```bash
git add config/routes.rb app/controllers/api/v1/accounts/leads_controller.rb \
        spec/controllers/api/v1/accounts/leads_controller_spec.rb docs/FORK-PONTOS-DE-REGISTRO.md
git commit -m "feat: add leads#for_conversation find-or-create endpoint"
```

---

### Task 2: Store — achar/garantir lead da conversa

Adiciona ao módulo Vuex `leads` um getter pra achar lead por `conversation_id` e uma action que garante o lead via o endpoint da Task 1, faz upsert e seleciona.

**Files:**
- Modify: `app/javascript/dashboard/api/leads.js`
- Modify: `app/javascript/dashboard/store/modules/leads.js`
- Test: `app/javascript/dashboard/store/modules/specs/leads.spec.js` (criar se não existir; senão adicionar)

**Interfaces:**
- Consumes: endpoint `POST leads/for_conversation` (Task 1).
- Produces:
  - getter `leads/getLeadByConversationId` → `conversationId => lead | undefined`
  - action `leads/ensureForConversation({ conversationId })` → resolve com o lead; faz `MERGE_LEAD` e `SET_SELECTED_LEAD`.

- [ ] **Step 1: Escrever o teste que falha (store)**

```js
// leads.spec.js — usa o mesmo padrão de mock de axios do resto do fork
import axios from 'axios';
import { actions, getters } from '../leads';
global.axios = axios;
vi.mock('axios');

describe('leads/ensureForConversation', () => {
  it('posts to for_conversation, merges and selects the lead', async () => {
    const lead = { id: 7, conversation_id: 99 };
    axios.post.mockResolvedValue({ data: lead });
    const commit = vi.fn();
    const result = await actions.ensureForConversation({ commit }, { conversationId: 99 });
    expect(result).toEqual(lead);
    expect(commit).toHaveBeenCalledWith('MERGE_LEAD', lead);
    expect(commit).toHaveBeenCalledWith('SET_SELECTED_LEAD', 7);
  });
});

describe('leads/getLeadByConversationId', () => {
  it('finds a record by conversation_id', () => {
    const state = { records: [{ id: 1, conversation_id: 5 }, { id: 2, conversation_id: 9 }] };
    expect(getters.getLeadByConversationId(state)(9)).toEqual({ id: 2, conversation_id: 9 });
  });
});
```

- [ ] **Step 2: Rodar e ver falhar (CI)**

Esperado: FAIL — `ensureForConversation`/`getLeadByConversationId` não existem.

- [ ] **Step 3: Adicionar o método na API client**

Em `app/javascript/dashboard/api/leads.js`, dentro da classe:

```js
forConversation(conversationId) {
  return axios.post(`${this.url}/for_conversation`, { conversation_id: conversationId });
}
```

(`this.url` já é account-scoped `.../leads`. Confirme o nome do getter de URL usado na classe — no ApiClient do Chatwoot é `this.url`.)

- [ ] **Step 4: Adicionar getter e action no módulo**

Em `store/modules/leads.js`:

```js
// getters
getLeadByConversationId: state => conversationId =>
  state.records.find(l => l.conversation_id === conversationId),

// actions
async ensureForConversation({ commit }, { conversationId }) {
  const response = await LeadsAPI.forConversation(conversationId);
  const lead = response.data;
  commit(types.MERGE_LEAD, lead);
  commit(types.SET_SELECTED_LEAD, lead.id);
  return lead;
},
```

Use as MESMAS constantes de mutation-type já usadas no arquivo (`MERGE_LEAD`, `SET_SELECTED_LEAD`) — confira o import no topo do módulo (`import types from ...` ou strings literais) e siga o padrão existente.

- [ ] **Step 5: Rodar e ver passar (CI)**

Esperado: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/javascript/dashboard/api/leads.js app/javascript/dashboard/store/modules/leads.js \
        app/javascript/dashboard/store/modules/specs/leads.spec.js
git commit -m "feat: add ensureForConversation action and getLeadByConversationId getter"
```

---

### Task 3: Extrair `LeadFields.vue` compartilhado do `LeadDrawer`

O miolo editável de campos (nome, etapa, benefício, prioridade, sdr, closer, valor, origem, notas + contato só-leitura) sai do `LeadDrawer` para um componente reusável que recebe o lead por **prop** e salva por id. O `LeadDrawer` passa a consumi-lo. Isso evita duplicar a lógica no painel da conversa.

**Files:**
- Create: `app/javascript/dashboard/routes/dashboard/ramon/components/lead/LeadFields.vue`
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/components/kanban/LeadDrawer.vue`
- Test: `app/javascript/dashboard/routes/dashboard/ramon/components/lead/specs/LeadFields.spec.js`

**Interfaces:**
- Produces: `LeadFields.vue` — **props:** `lead: { type: Object, required: true }`. Salva via `store.dispatch('leads/update', { id: lead.id, <campo> })` (on-blur pra texto se mudou, on-change pra selects — mesma regra do LeadDrawer atual). Lê config de `leadConfig` (`getStages/getBenefitTypes/getPriorities`) e `agents/getAgents`. Emite nada (salva direto no store). Contato read-only via `lead.contact_name/contact_phone/contact_email`.
- Consumes: nada de tasks anteriores.

- [ ] **Step 1: Escrever o teste que falha (LeadFields)**

```js
import { shallowMount } from '@vue/test-utils';
import { createStore } from 'vuex';
import LeadFields from '../LeadFields.vue';

const lead = { id: 3, name: 'Ana', lead_stage_id: 1, value: 100, source: 'ig', notes: 'x',
  benefit_type_id: null, lead_priority_id: null, sdr_id: null, closer_id: null,
  contact_name: 'Ana', contact_phone: '+55', contact_email: null };

const build = (updateSpy = vi.fn()) => createStore({
  modules: {
    leads: { namespaced: true, actions: { update: updateSpy } },
    leadConfig: { namespaced: true, getters: {
      getStages: () => [{ id: 1, name: 'Novo' }],
      getBenefitTypes: () => [], getPriorities: () => [] } },
    agents: { namespaced: true, getters: { getAgents: () => [] } },
  },
});

const mountFields = (updateSpy = vi.fn()) => shallowMount(LeadFields, {
  props: { lead },
  global: { plugins: [build(updateSpy)], mocks: { $t: k => k } },
});

it('saves a text field on blur when changed', async () => {
  const update = vi.fn();
  const wrapper = mountFields(update);
  const input = wrapper.find('[data-testid="field-name"]');
  await input.setValue('Ana Maria');
  await input.trigger('blur');
  expect(update).toHaveBeenCalledWith(expect.anything(), { id: 3, name: 'Ana Maria' });
});

it('does not save a text field on blur when unchanged', async () => {
  const update = vi.fn();
  const wrapper = mountFields(update);
  await wrapper.find('[data-testid="field-name"]').trigger('blur');
  expect(update).not.toHaveBeenCalled();
});
```

- [ ] **Step 2: Rodar e ver falhar (CI)**

Esperado: FAIL — `LeadFields.vue` não existe.

- [ ] **Step 3: Criar `LeadFields.vue`**

Mova o `<template>` de campos e a lógica de `saveText`/`saveSelect` do `LeadDrawer` atual para cá, trocando a fonte do lead de `getters['leads/getSelectedLead']` para a **prop `lead`**. Estrutura:

```vue
<script setup>
import { ref, watch } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';

const props = defineProps({ lead: { type: Object, required: true } });
const store = useStore();
const stages = useMapGetter('leadConfig/getStages');
const benefitTypes = useMapGetter('leadConfig/getBenefitTypes');
const priorities = useMapGetter('leadConfig/getPriorities');
const agents = useMapGetter('agents/getAgents');

const name = ref(''); const value = ref(null); const source = ref(''); const notes = ref('');
watch(() => props.lead, l => {
  name.value = l?.name ?? ''; value.value = l?.value ?? null;
  source.value = l?.source ?? ''; notes.value = l?.notes ?? '';
}, { immediate: true });

const saveText = (field, current) => {
  if ((props.lead?.[field] ?? '') === (current ?? '')) return;
  store.dispatch('leads/update', { id: props.lead.id, [field]: current });
};
const saveSelect = (field, val) =>
  store.dispatch('leads/update', { id: props.lead.id, [field]: val });
</script>
```

O `<template>` deve replicar os campos e `data-testid` atuais do LeadDrawer (`field-name`, `field-stage`, `field-value`, etc.), chamando `@blur="saveText('name', name)"` e `@change="saveSelect('lead_stage_id', $event...)"`. **Confirme os nomes reais dos composables** (`useStore`, `useMapGetter`) lendo como o LeadDrawer importa hoje; use exatamente o mesmo mecanismo (o LeadDrawer usa `store.getters` + `store.dispatch` — replique idêntico se não houver composable).

- [ ] **Step 4: Refatorar `LeadDrawer.vue` pra usar `LeadFields`**

No `LeadDrawer.vue`, substitua o bloco de campos internos por `<LeadFields :lead="lead" />` (onde `lead = getters['leads/getSelectedLead']`), mantendo a casca de overlay (`fixed inset-0`), o header, o botão de fechar (`leads/select` null), o Esc listener e o botão "abrir conversa" (emite `open-conversation`). Importe `LeadFields`.

- [ ] **Step 5: Rodar specs (CI): LeadFields novo + LeadDrawer existente**

Esperado: PASS nos dois. Se `LeadDrawer.spec.js` quebrar por os campos agora estarem no filho, ajuste-o para `mount` (não `shallowMount`) OU para asserir a presença de `LeadFields` (`findComponent(LeadFields)`), preservando o teste do fechar/Esc/emit.

- [ ] **Step 6: Prettier + commit**

```bash
npx prettier@3.3.3 --write app/javascript/dashboard/routes/dashboard/ramon/components/lead
git add app/javascript/dashboard/routes/dashboard/ramon/components/lead \
        app/javascript/dashboard/routes/dashboard/ramon/components/kanban/LeadDrawer.vue
git commit -m "refactor: extract shared LeadFields from LeadDrawer"
```

---

### Task 4: `LeadConversationPanel.vue` — casca de abas + aba Resumo

Componente que o `ConversationSidebar` vai montar. Recebe `conversationId`/`inboxId`, garante o lead (Task 2), e mostra a aba **Resumo** = `LeadFields` + ações nativas embutidas + botão "Não é lead / Descartar". Casca de abas já preparada para receber Histórico (1b), mas só Resumo agora.

**Files:**
- Create: `app/javascript/dashboard/routes/dashboard/ramon/components/conversation/LeadConversationPanel.vue`
- Test: `app/javascript/dashboard/routes/dashboard/ramon/components/conversation/specs/LeadConversationPanel.spec.js`
- Modify: `app/javascript/dashboard/i18n/locale/en/ramon.json`
- Modify: `app/javascript/dashboard/i18n/locale/pt_BR/ramon.json`

**Interfaces:**
- Consumes: `leads/ensureForConversation` + `leads/getLeadByConversationId` (Task 2); `LeadFields.vue` (Task 3); componentes nativos `ConversationAction` (`routes/dashboard/conversation/ConversationAction.vue`), `MacrosList` (`routes/dashboard/conversation/Macros/List.vue`), `ResolveAction` (`components/buttons/ResolveAction.vue`).
- **props:** `conversationId: { type: [Number, String], required: true }`, `inboxId: { type: Number, default: undefined }`.
- Produces: emite `discarded` (camelCase) quando o lead é descartado, pra o pai voltar ao painel nativo.

- [ ] **Step 1: Escrever o teste que falha**

```js
import { shallowMount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import LeadConversationPanel from '../LeadConversationPanel.vue';

const lead = { id: 5, conversation_id: 42, name: 'Zé' };
const build = (ensureSpy, deleteSpy) => createStore({
  modules: {
    leads: { namespaced: true,
      getters: { getLeadByConversationId: () => () => lead },
      actions: { ensureForConversation: ensureSpy, delete: deleteSpy, select: vi.fn() } },
    leadConfig: { namespaced: true, getters: {
      getStages: () => [], getBenefitTypes: () => [], getPriorities: () => [] } },
    agents: { namespaced: true, getters: { getAgents: () => [] } },
  },
});
const mountPanel = (ensureSpy = vi.fn().mockResolvedValue(lead), deleteSpy = vi.fn()) =>
  shallowMount(LeadConversationPanel, {
    props: { conversationId: 42, inboxId: 1 },
    global: { plugins: [build(ensureSpy, deleteSpy)], mocks: { $t: k => k },
      stubs: { ConversationAction: true, MacrosList: true, ResolveAction: true, LeadFields: true } },
  });

it('ensures the lead on mount', async () => {
  const ensure = vi.fn().mockResolvedValue(lead);
  mountPanel(ensure);
  await flushPromises();
  expect(ensure).toHaveBeenCalledWith(expect.anything(), { conversationId: 42 });
});

it('discards the lead and emits discarded', async () => {
  const del = vi.fn();
  const wrapper = mountPanel(vi.fn().mockResolvedValue(lead), del);
  await flushPromises();
  await wrapper.find('[data-testid="lead-discard"]').trigger('click');
  expect(del).toHaveBeenCalledWith(expect.anything(), 5);
  expect(wrapper.emitted('discarded')).toBeTruthy();
});
```

- [ ] **Step 2: Rodar e ver falhar (CI)**

Esperado: FAIL — componente inexistente.

- [ ] **Step 3: Implementar `LeadConversationPanel.vue`**

```vue
<script setup>
import { ref, computed, watch } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import LeadFields from 'dashboard/routes/dashboard/ramon/components/lead/LeadFields.vue';
import ConversationAction from 'dashboard/routes/dashboard/conversation/ConversationAction.vue';
import MacrosList from 'dashboard/routes/dashboard/conversation/Macros/List.vue';
import ResolveAction from 'dashboard/components/buttons/ResolveAction.vue';

const props = defineProps({
  conversationId: { type: [Number, String], required: true },
  inboxId: { type: Number, default: undefined },
});
const emit = defineEmits(['discarded']);
const store = useStore();
const leadByConv = useMapGetter('leads/getLeadByConversationId');
const activeTab = ref('resumo');
const lead = computed(() => leadByConv.value(Number(props.conversationId)));

const ensure = async () => { await store.dispatch('leads/ensureForConversation', { conversationId: Number(props.conversationId) }); };
watch(() => props.conversationId, ensure, { immediate: true });

const discard = async () => {
  if (!lead.value) return;
  await store.dispatch('leads/delete', lead.value.id);
  emit('discarded');
};
</script>

<template>
  <div class="flex flex-col h-full" data-testid="lead-conversation-panel">
    <div class="flex items-center gap-2 border-b px-3 py-2">
      <button :class="{ 'font-semibold': activeTab === 'resumo' }" @click="activeTab = 'resumo'">
        {{ $t('RAMON.LEAD_PANEL.TABS.SUMMARY') }}
      </button>
      <button class="ml-auto text-xs" data-testid="lead-discard" @click="discard">
        {{ $t('RAMON.LEAD_PANEL.DISCARD') }}
      </button>
    </div>
    <div v-if="lead" class="flex-1 overflow-y-auto p-3">
      <div class="mb-4 flex flex-col gap-2">
        <ConversationAction :conversation-id="conversationId" :inbox-id="inboxId" />
        <MacrosList :conversation-id="conversationId" />
        <ResolveAction :conversation-id="conversationId" :inbox-id="inboxId" />
      </div>
      <LeadFields :lead="lead" />
    </div>
  </div>
</template>
```

**Confirme antes de codar:** (a) o mecanismo de composable (`useStore`/`useMapGetter`) usado no fork — se o LeadDrawer usa outro padrão, use o mesmo; (b) as **props reais** de `ConversationAction`, `MacrosList`, `ResolveAction` (o mapeamento indicou `conversationId`/`inboxId`, mas leia cada componente e passe exatamente o que ele exige; `ResolveAction` pode não aceitar `inboxId`). Ajuste os bindings ao que cada um declara.

- [ ] **Step 4: Adicionar i18n**

Em `en/ramon.json` e `pt_BR/ramon.json`, adicione sob a raiz `RAMON`:

```json
"LEAD_PANEL": {
  "TABS": { "SUMMARY": "Resumo" },
  "DISCARD": "Não é lead"
}
```

(en: `"SUMMARY": "Summary"`, `"DISCARD": "Not a lead"`.) Confirme que `ramon.json` já está registrado nos dois `i18n/locale/{en,pt_BR}/index.js` (import + spread — foi registrado na 1A).

- [ ] **Step 5: Rodar specs (CI) e ver passar**

Esperado: PASS.

- [ ] **Step 6: Prettier + commit**

```bash
npx prettier@3.3.3 --write app/javascript/dashboard/routes/dashboard/ramon/components/conversation \
        app/javascript/dashboard/i18n/locale/en/ramon.json app/javascript/dashboard/i18n/locale/pt_BR/ramon.json
git add app/javascript/dashboard/routes/dashboard/ramon/components/conversation \
        app/javascript/dashboard/i18n/locale/en/ramon.json app/javascript/dashboard/i18n/locale/pt_BR/ramon.json
git commit -m "feat: add LeadConversationPanel with Resumo tab"
```

---

### Task 5: Montar o painel no `ConversationSidebar` (troca do nativo)

Faz o `ConversationSidebar` renderizar o `LeadConversationPanel` no lugar do `ContactPanel` (a não ser que o lead tenha sido descartado nesta visita, quando volta ao nativo). Amplia a largura pra ~metade. Registra o core edit.

**Files:**
- Modify: `app/javascript/dashboard/components/widgets/conversation/ConversationSidebar.vue`
- Test: `app/javascript/dashboard/components/widgets/conversation/specs/ConversationSidebar.spec.js` (criar se não existir)
- Modify: `docs/FORK-PONTOS-DE-REGISTRO.md`

**Interfaces:**
- Consumes: `LeadConversationPanel` (Task 4), evento `discarded`.
- Produces: nada pra frente.

- [ ] **Step 1: Escrever o teste que falha**

```js
import { shallowMount } from '@vue/test-utils';
import { createStore } from 'vuex';
import ConversationSidebar from '../ConversationSidebar.vue';

const build = () => createStore({ modules: {
  // stubs mínimos que o ContactPanel/ConversationSidebar exigem podem ser mockados via stubs
} });

const mountSidebar = () => shallowMount(ConversationSidebar, {
  props: { currentChat: { id: 42, inbox_id: 1 } },
  global: { plugins: [build()], mocks: { $t: k => k },
    stubs: { ContactPanel: true, LeadConversationPanel: true } },
});

it('renders LeadConversationPanel instead of ContactPanel by default', () => {
  const wrapper = mountSidebar();
  expect(wrapper.findComponent({ name: 'LeadConversationPanel' }).exists()).toBe(true);
});

it('falls back to ContactPanel after discard', async () => {
  const wrapper = mountSidebar();
  wrapper.findComponent({ name: 'LeadConversationPanel' }).vm.$emit('discarded');
  await wrapper.vm.$nextTick();
  expect(wrapper.findComponent({ name: 'ContactPanel' }).exists()).toBe(true);
});
```

(Se `ConversationSidebar` depender de `useUISettings`/store real, mocke o que for necessário; o objetivo é asserir a troca condicional. Ajuste os stubs ao que o componente importa.)

- [ ] **Step 2: Rodar e ver falhar (CI)**

Esperado: FAIL — hoje só renderiza `ContactPanel`.

- [ ] **Step 3: Editar o `ConversationSidebar.vue`**

No `<script>`: importar `LeadConversationPanel`; adicionar `data`/`ref` `discardedConversations` (Set) ou um flag por conversationId. Computed `showLeadPanel = !discarded.has(currentChat.id)`.

No `<template>`, onde hoje está (linha ~63):

```html
<ContactPanel v-show="activeTab === 0" :conversation-id="currentChat.id" :inbox-id="currentChat.inbox_id" />
```

trocar por:

```html
<LeadConversationPanel
  v-if="showLeadPanel"
  v-show="activeTab === 0"
  :conversation-id="currentChat.id"
  :inbox-id="currentChat.inbox_id"
  @discarded="onDiscard(currentChat.id)"
/>
<ContactPanel
  v-else
  v-show="activeTab === 0"
  :conversation-id="currentChat.id"
  :inbox-id="currentChat.inbox_id"
/>
```

`onDiscard(id)` adiciona ao Set de descartados (volta ao nativo até o usuário navegar/re-selecionar). Registre o método `name: 'LeadConversationPanel'` no componente da Task 4 (adicione `defineOptions({ name: 'LeadConversationPanel' })` se usar `<script setup>`) pra o `findComponent({ name })` funcionar.

- [ ] **Step 4: Ampliar a largura (~metade)**

Na div wrapper do `ConversationSidebar` (linha ~54, hoje `md:w-[320px] md:min-w-[320px] 2xl:min-w-[360px] 2xl:w-[360px]`): quando `showLeadPanel`, aplicar largura maior (ex.: `md:w-[420px] 2xl:w-[480px]` ou `md:w-2/5`). Use classe condicional (`:class`) para não afetar o modo nativo. Calibração visual fina fica pós-deploy.

- [ ] **Step 5: Registrar no FORK-PONTOS**

Linha: `components/widgets/conversation/ConversationSidebar.vue` — renderiza LeadConversationPanel no lugar do ContactPanel quando não-descartado + largura ~metade — motivo: painel do lead na conversa — fase 1a.

- [ ] **Step 6: Rodar specs (CI) e ver passar**

Esperado: PASS.

- [ ] **Step 7: Prettier + commit**

```bash
npx prettier@3.3.3 --write app/javascript/dashboard/components/widgets/conversation/ConversationSidebar.vue
git add app/javascript/dashboard/components/widgets/conversation/ConversationSidebar.vue \
        app/javascript/dashboard/components/widgets/conversation/specs/ConversationSidebar.spec.js \
        docs/FORK-PONTOS-DE-REGISTRO.md
git commit -m "feat: mount LeadConversationPanel in conversation sidebar"
```

---

### Task 6: PR, CI verde, deploy e corte do iframe legado

**Files:** nenhum novo — fecha a fatia.

- [ ] **Step 1: Abrir PR contra `ramon`**

```bash
git push -u origin feat/fatia-1a-painel-lead-conversa
gh pr create --base ramon --title "feat: painel do lead na conversa (aba Resumo)" \
  --body "Fatia 1a: substitui o iframe /embed/kit por painel nativo com aba Resumo. Sem migração."
```

- [ ] **Step 2: Acompanhar o CI (`run_foss_spec`)**

Esperado: rspec + vitest + rubocop + eslint verdes. Se rubocop/eslint reclamar, aplicar os fixes do bloco Global Constraints (prettier, disables pontuais, camelCase/kebab de eventos) e repush.

- [ ] **Step 3: Merge (com OK do Eduardo)**

Após CI verde e revisão, o Eduardo autoriza o merge do PR em `ramon`.

- [ ] **Step 4: Deploy na VPS (com OK explícito do Eduardo)**

Sem migração nesta fatia. Build GHCR verde → na VPS: `docker compose pull chatwoot-web chatwoot-worker && docker compose up -d chatwoot-web chatwoot-worker` (Puma leva ~90s; 502 até subir). Smoke: HTTP 200; abrir uma conversa e ver o painel nativo do lead com a aba Resumo; testar salvar um campo, atribuir agente, e "Não é lead".

- [ ] **Step 5: Cortar o iframe `/embed/kit` legado (runtime, Eduardo)**

No Chatwoot (Configurações → Integrações → Dashboard Apps), **remover/desabilitar** o Dashboard App "Painel do Lead" que aponta pra intranet Next (`app.ramonantonio.adv.br/embed/kit`). Isso é config de runtime, feita pelo Eduardo (guiar com prints). Confirmar que a conversa agora mostra só o painel nativo.

---

## Self-Review

**Spec coverage (contra `2026-07-01-ramon-hub-fatia-1-painel-lead-na-conversa-design.md`):**
- Layout dividido + painel à direita ~metade → Task 5 (largura) + Task 4. ✅
- Substitui o nativo quando é lead → Task 5. ✅
- Ações nativas embutidas na aba Resumo → Task 4 (ConversationAction/MacrosList/ResolveAction). ✅
- Cria Lead em "Novo" ao abrir → Task 1 (endpoint) + Task 4 (ensure no mount). ✅
- Botão "Não é lead" = apaga → Task 4 (discard → `leads/delete`) + Task 5 (volta ao nativo). ✅
- Aba Resumo com dados do lead (reusa LeadDrawer) → Task 3 (LeadFields) + Task 4. ✅
- Corta o iframe legado assim que Resumo funciona → Task 6 Step 5. ✅
- **Histórico → NÃO neste plano** (Fatia 1b, tem migração). Documentado no cabeçalho. ✅ (fora de escopo consciente)
- Sem migração (Documentos→Drive, S3 descartado) → nenhuma task cria migração. ✅

**Placeholder scan:** sem TBD/TODO; cada passo de código tem código. Pontos marcados "confirme no código real" (composable de store, props exatas dos componentes nativos, view `show.json.jbuilder`) são verificações que o executor faz lendo o fork — não placeholders de conteúdo.

**Type consistency:** `ensureForConversation({ conversationId })`, `getLeadByConversationId(state)(conversationId)`, `MERGE_LEAD`/`SET_SELECTED_LEAD`, `leads/update { id, ... }`, `leads/delete <id>`, prop `lead` em `LeadFields`, evento `discarded` (camelCase emit / kebab listener) — consistentes entre Tasks 2→3→4→5.

**Risco aberto (calibração, não bloqueia):** ao substituir o `ContactPanel` inteiro, os acordeões nativos não-embutidos (participantes, conversas anteriores, arquivos compartilhados, atributos/notas do contato) saem de vista na v1. Se fizerem falta, adicionar como seções do Resumo ou um toggle "ver painel nativo" numa fatia de calibração. Sinalizar ao Eduardo no smoke.
