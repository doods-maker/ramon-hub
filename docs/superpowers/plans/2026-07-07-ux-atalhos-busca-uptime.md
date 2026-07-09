# UX 4b/4c — Atalhos no Kanban (13), Leads na busca global (15), Uptime (27) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Três itens da fila UX: navegar/agir no Kanban por teclado (j/k/e/c), leads aparecendo na busca global (Cmd+K) do Chatwoot, e guia pronto do monitor de uptime (config externa, gate Eduardo).

**Architecture:** Atalhos usam o composable nativo `useKeyboardEvents` (tinykeys) no KanbanBoard, com foco visual descendo por prop até o LeadCard. Busca global segue exatamente o pipeline nativo: `SearchService#filter_leads` → action `leads` no SearchController → `SearchAPI.leads` → módulo `conversationSearch` → tab + lista no SearchView. Uptime é doc (UptimeRobot free monitorando `/api`).

**Tech Stack:** Rails 7.1 (fork Chatwoot v4.15.1), Vue 3 `<script setup>`, Tailwind, RSpec.

**Branch:** independente, base `ramon` (sem migração; não conflita com as frentes honorário/linha-da-vida além de blocos distintos do ramon.json).

## Global Constraints

- Sem ambiente local: **PR + CI validam**. Não rodar bundle/rspec/pnpm test; `npx prettier --write` só nos arquivos tocados. Commits/push com `--no-verify`.
- SEM migração — schema.rb não muda.
- Rubocop 150 chars; RSpec máx 7 expectations; eventos Vue camelCase; Tailwind only.
- `Lead` tem default_scope — a busca usa `reorder('leads.created_at DESC')`; specs usam `find_by`/`reorder(:id)`.
- Atalhos NÃO disparam com foco em input (`useKeyboardEvents` já ignora elementos "typeable" por padrão — não passar `allowOnFocusedInput`).
- i18n: chaves do search vivem em `en/search.json` E `pt_BR/search.json` (arquivo próprio, não é o ramon.json); chaves do Kanban em `en/ramon.json` + `pt_BR/ramon.json`.
- Resultado de lead na busca navega pra CONVERSA do lead quando houver `conversation_id`; senão pro funil (`ramon_funil`). (Apontar pra Linha da Vida fica pra depois do merge da outra frente — anotar no PR.)

---

### Task 1: Atalhos de teclado no Kanban (j/k/e/c)

**Files:**
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/components/kanban/KanbanBoard.vue`
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/components/kanban/KanbanColumn.vue` (prop nova + repasse)
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/components/kanban/LeadCard.vue` (prop nova + ring + scroll)
- Modify: `app/javascript/dashboard/i18n/locale/en/ramon.json` + `pt_BR/ramon.json` (hint dos atalhos em `RAMON.FUNIL`)

**Interfaces:**
- Consumes: handlers existentes `onOpenLead`/`onOpenConversation` do KanbanBoard; `stageLeads(stage.id)`/`orderedStages`.
- Produces: prop `focusedLeadId` (Number|null) no KanbanColumn; prop `focused` (Boolean) no LeadCard.

- [ ] **Step 1: KanbanBoard — estado de foco + hotkeys**

No `<script setup>` do `KanbanBoard.vue`, adicionar import:

```js
import { useKeyboardEvents } from 'dashboard/composables/useKeyboardEvents';
```

Adicionar após a declaração de `filters` (~linha 46):

```js
// Atalhos (item 13 do 4b): j/k navegam entre cards, e abre a gaveta, c abre a
// conversa. Lista achatada na ordem visual das colunas.
const focusedLeadId = ref(null);

const flatLeads = () =>
  orderedStages.value.flatMap(s => stageLeads(s.id));

const moveFocus = delta => {
  const all = flatLeads();
  if (!all.length) return;
  const idx = all.findIndex(l => l.id === focusedLeadId.value);
  const next = idx === -1 ? (delta > 0 ? 0 : all.length - 1) : idx + delta;
  const clamped = Math.max(0, Math.min(all.length - 1, next));
  focusedLeadId.value = all[clamped].id;
};

const focusedLead = () =>
  flatLeads().find(l => l.id === focusedLeadId.value);

useKeyboardEvents({
  KeyJ: { action: () => moveFocus(1) },
  KeyK: { action: () => moveFocus(-1) },
  KeyE: {
    action: () => {
      const lead = focusedLead();
      if (lead) onOpenLead(lead);
    },
  },
  KeyC: {
    action: () => {
      const lead = focusedLead();
      if (lead?.conversation_id) onOpenConversation(lead.conversation_id);
    },
  },
});
```

(⚠️ `onOpenLead`/`onOpenConversation` são declarados mais abaixo no arquivo (~linha 126) — como são `const` arrow functions usadas dentro de callbacks (não na inicialização), a ordem funciona; se o eslint `no-use-before-define` reclamar no CI, mover o bloco de hotkeys para DEPOIS da declaração deles.)

No template, passar a prop ao `KanbanColumn` (~linha 220):

```html
          <KanbanColumn
            :stage="element"
            :leads="stageLeads(element.id)"
            :focused-lead-id="focusedLeadId"
            @move="onMove"
            ...
```

(Manter os binds/eventos existentes intactos; `:focused-lead-id` é kebab-case de PROP no template — permitido; a regra camelCase vale para EVENTOS custom.)

- [ ] **Step 2: KanbanColumn — repasse**

Em `KanbanColumn.vue`, adicionar à `defineProps` (~linha 7-10):

```js
  focusedLeadId: { type: Number, default: null },
```

No template, onde o `LeadCard` é renderizado (procurar `<LeadCard`), adicionar:

```html
            :focused="lead.id === focusedLeadId"
```

(`lead` = o nome da variável de iteração local do template — usar o nome real encontrado.)

- [ ] **Step 3: LeadCard — ring + scroll**

Em `LeadCard.vue`:

`defineProps` ganha:

```js
  focused: { type: Boolean, default: false },
```

Adicionar no `<script setup>`:

```js
const cardEl = ref(null);
watch(
  () => props.focused,
  isFocused => {
    if (isFocused)
      cardEl.value?.scrollIntoView({ block: 'nearest', inline: 'nearest' });
  }
);
```

(Adicionar `ref`/`watch` ao import de `vue` se ainda não estiverem.)

No elemento raiz do card (primeiro elemento do template), adicionar:

```html
    ref="cardEl"
    :class="{ 'ring-2 ring-n-iris-9': focused }"
```

(Se o elemento raiz já tiver `:class`, mesclar no objeto/array existente.)

- [ ] **Step 4: Hint discreto + i18n**

No cabeçalho do funil em `KanbanBoard.vue` (junto ao título, ~linha 187), adicionar:

```html
      <span class="hidden lg:inline text-xs text-n-slate-9">
        {{ $t('RAMON.FUNIL.HOTKEYS_HINT') }}
      </span>
```

`en/ramon.json`, bloco `RAMON.FUNIL` (junto de TITLE/NEW_LEAD):

```json
      "HOTKEYS_HINT": "j/k navigate · e edit · c conversation",
```

`pt_BR/ramon.json`, mesma posição:

```json
      "HOTKEYS_HINT": "j/k navegar · e editar · c conversa",
```

- [ ] **Step 5: Prettier + commit**

```bash
npx prettier --write app/javascript/dashboard/routes/dashboard/ramon/components/kanban/KanbanBoard.vue app/javascript/dashboard/routes/dashboard/ramon/components/kanban/KanbanColumn.vue app/javascript/dashboard/routes/dashboard/ramon/components/kanban/LeadCard.vue
git add app/javascript/dashboard/routes/dashboard/ramon/components/kanban/ app/javascript/dashboard/i18n/locale/en/ramon.json app/javascript/dashboard/i18n/locale/pt_BR/ramon.json
git commit --no-verify -m "feat(funil): atalhos de teclado no kanban (j/k/e/c)"
```

---

### Task 2: Busca global — backend (SearchService + controller + rota)

**Files:**
- Modify: `app/services/search_service.rb` (case do perform + `filter_leads`)
- Modify: `app/controllers/api/v1/accounts/search_controller.rb` (action `leads`)
- Modify: `config/routes.rb` (rota `search/leads` — achar o `resources :search, only: [:index]` na ~linha 172 e adicionar à collection)
- Create: `app/views/api/v1/accounts/search/leads.json.jbuilder` + `app/views/api/v1/accounts/search/_lead.json.jbuilder`
- Modify: `app/views/api/v1/accounts/search/index.json.jbuilder` (bloco leads no all)
- Test (create): `spec/services/search_service_leads_spec.rb`

**Interfaces:**
- Produces: `GET /api/v1/accounts/:id/search/leads?q=` → `{ payload: { leads: [{ id, name, stage_name, benefit_type_name, conversation_id, contact_name, contact_phone, created_at }] } }`; o `all` (index) inclui a chave `leads`. Task 3 consome.

- [ ] **Step 1: Escrever o teste que falha**

Criar `spec/services/search_service_leads_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe SearchService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :agent) }

  def search(query, type: 'Lead')
    described_class.new(current_user: user, current_account: account,
                        search_type: type, params: { q: query }).perform
  end

  it 'acha lead pelo nome do lead, do contato e telefone' do
    contact = create(:contact, account: account, name: 'Maria Oliveira', phone_number: '+5548988887777')
    stage = account.lead_stages.order(:position).first
    lead = create(:lead, account: account, contact: contact, lead_stage: stage, name: 'Auxílio Maria')

    expect(search('Auxílio Maria')[:leads]).to include(lead)
    expect(search('Oliveira')[:leads]).to include(lead)
    expect(search('48988887777')[:leads]).to include(lead)
  end

  it 'inclui leads no all e não vaza de outra conta' do
    outra = create(:account)
    create(:lead, account: outra, lead_stage: outra.lead_stages.order(:position).first, name: 'Segredo Alheio')

    result = search('Segredo', type: 'all')
    expect(result).to have_key(:leads)
    expect(result[:leads]).to be_empty
  end
end
```

- [ ] **Step 2: SearchService**

No `case search_type` do `perform`, adicionar antes do `else`:

```ruby
    when 'Lead'
      { leads: filter_leads }
```

E no `else` (busca all), acrescentar a chave:

```ruby
      { contacts: filter_contacts, messages: filter_messages, conversations: filter_conversations, articles: filter_articles, leads: filter_leads }
```

Adicionar o método privado (junto de `filter_contacts`):

```ruby
  def filter_leads
    return Lead.none unless account_user&.administrator? || account_user&.agent?

    @leads = current_account.leads.left_joins(:contact)
                            .where('leads.name ILIKE :search OR contacts.name ILIKE :search OR contacts.phone_number ILIKE :search',
                                   search: "%#{search_query}%")
                            .reorder('leads.created_at DESC')
                            .page(params[:page])
                            .per(15)
  end
```

- [ ] **Step 3: Controller + rota**

`search_controller.rb`, junto das outras actions:

```ruby
  def leads
    @result = search('Lead')
  end
```

`config/routes.rb`, no `resources :search, only: [:index]` (~linha 172), adicionar à collection existente (espelhar como `contacts`/`conversations` estão declarados ali):

```ruby
              get :leads
```

- [ ] **Step 4: Views**

Criar `app/views/api/v1/accounts/search/_lead.json.jbuilder`:

```ruby
json.id lead.id
json.name lead.name
json.stage_name lead.lead_stage&.name
json.stage_color lead.lead_stage&.color
json.benefit_type_name lead.benefit_type&.name
json.conversation_id lead.conversation_id
json.contact_name lead.contact&.name
json.contact_phone lead.contact&.phone_number
json.created_at lead.created_at
```

Criar `app/views/api/v1/accounts/search/leads.json.jbuilder`:

```ruby
json.payload do
  json.leads do
    json.array! @result[:leads] do |lead|
      json.partial! 'lead', formats: [:json], lead: lead
    end
  end
end
```

Em `index.json.jbuilder`, adicionar dentro do `json.payload do` (junto dos outros blocos):

```ruby
  json.leads do
    json.array! @result[:leads] do |lead|
      json.partial! 'lead', formats: [:json], lead: lead
    end
  end
```

- [ ] **Step 5: Commit**

```bash
git add app/services/search_service.rb app/controllers/api/v1/accounts/search_controller.rb config/routes.rb app/views/api/v1/accounts/search/ spec/services/search_service_leads_spec.rb
git commit --no-verify -m "feat(search): leads na busca global (backend)"
```

---

### Task 3: Busca global — frontend (store + tab + lista)

**Files:**
- Modify: `app/javascript/dashboard/api/search.js` (método `leads`)
- Modify: `app/javascript/dashboard/store/mutation-types.js` (2 tipos novos — procurar `LEAD_` ou os tipos `CONTACT_SEARCH_SET` para achar o bloco)
- Modify: `app/javascript/dashboard/store/modules/conversationSearch.js` (state, getter, action, mutations, clear)
- Create: `app/javascript/dashboard/modules/search/components/SearchResultLeadsList.vue`
- Modify: `app/javascript/dashboard/modules/search/components/SearchView.vue` (import, records, tab, section)
- Modify: `app/javascript/dashboard/i18n/locale/en/search.json` + `pt_BR/search.json` (TABS.LEADS + SECTION.LEADS)

**Interfaces:**
- Consumes: endpoint da Task 2. Records chegam camelCase na view (`useCamelCase`): `stageName`, `benefitTypeName`, `conversationId`, `contactName`, `contactPhone`.

- [ ] **Step 1: API client**

`api/search.js`, junto dos outros métodos:

```js
  leads({ q, page = 1, since, until }) {
    return axios.get(`${this.url}/leads`, {
      params: {
        q,
        page: page,
        since,
        until,
      },
    });
  }
```

- [ ] **Step 2: mutation-types**

Em `store/mutation-types.js`, junto de `CONTACT_SEARCH_SET`/`CONTACT_SEARCH_SET_UI_FLAG` (mesmo bloco):

```js
  LEAD_SEARCH_SET: 'LEAD_SEARCH_SET',
  LEAD_SEARCH_SET_UI_FLAG: 'LEAD_SEARCH_SET_UI_FLAG',
```

- [ ] **Step 3: Store module**

Em `conversationSearch.js`:

`initialState`: adicionar `leadRecords: []` (junto de `contactRecords`) e `lead: { isFetching: false }` dentro de `uiFlags`.

`getters`:

```js
  getLeadRecords(state) {
    return state.leadRecords;
  },
```

`fullSearch`: adicionar ao `Promise.all`:

```js
        dispatch('leadSearch', { q, ...filters }),
```

`actions` (junto de `contactSearch`):

```js
  async leadSearch({ commit }, payload) {
    const { page = 1, ...searchParams } = payload;
    commit(types.LEAD_SEARCH_SET_UI_FLAG, { isFetching: true });
    try {
      const { data } = await SearchAPI.leads({ ...searchParams, page });
      commit(types.LEAD_SEARCH_SET, data.payload.leads);
    } catch (error) {
      // Ignore error
    } finally {
      commit(types.LEAD_SEARCH_SET_UI_FLAG, { isFetching: false });
    }
  },
```

`mutations`:

```js
  [types.LEAD_SEARCH_SET](state, records) {
    state.leadRecords = [...state.leadRecords, ...records];
  },
  [types.LEAD_SEARCH_SET_UI_FLAG](state, uiFlags) {
    state.uiFlags.lead = { ...state.uiFlags.lead, ...uiFlags };
  },
```

`CLEAR_SEARCH_RESULTS`: adicionar `state.leadRecords = [];`.

- [ ] **Step 4: Componente da lista**

Criar `SearchResultLeadsList.vue`:

```html
<script setup>
import { useMapGetter } from 'dashboard/composables/store.js';
import { frontendURL } from '../../../helper/URLHelper';

import SearchResultSection from './SearchResultSection.vue';

defineProps({
  leads: {
    type: Array,
    default: () => [],
  },
  query: {
    type: String,
    default: '',
  },
  isFetching: {
    type: Boolean,
    default: false,
  },
  showTitle: {
    type: Boolean,
    default: true,
  },
});

const accountId = useMapGetter('getCurrentAccountId');

const leadUrl = lead =>
  lead.conversationId
    ? frontendURL(`accounts/${accountId.value}/conversations/${lead.conversationId}`)
    : frontendURL(`accounts/${accountId.value}/ramon/funil`);
</script>

<template>
  <SearchResultSection
    :title="$t('SEARCH.SECTION.LEADS')"
    :empty="!leads.length"
    :query="query"
    :show-title="showTitle"
    :is-fetching="isFetching"
  >
    <ul v-if="leads.length" class="space-y-3 list-none">
      <li v-for="lead in leads" :key="lead.id">
        <router-link
          :to="leadUrl(lead)"
          class="flex items-center justify-between gap-2 p-2 rounded-md hover:bg-n-alpha-1"
        >
          <div class="min-w-0">
            <p class="text-sm truncate text-n-slate-12">{{ lead.name }}</p>
            <p class="text-xs truncate text-n-slate-10">
              <span v-if="lead.contactName">{{ lead.contactName }} · </span>
              <span v-if="lead.contactPhone">{{ lead.contactPhone }} · </span>
              <span v-if="lead.benefitTypeName">{{ lead.benefitTypeName }}</span>
            </p>
          </div>
          <span
            v-if="lead.stageName"
            class="shrink-0 px-2 py-0.5 text-xs rounded-full text-n-slate-12"
            :style="{ backgroundColor: lead.stageColor || 'transparent' }"
          >
            {{ lead.stageName }}
          </span>
        </router-link>
      </li>
    </ul>
  </SearchResultSection>
</template>
```

- [ ] **Step 5: SearchView**

Em `SearchView.vue`:

- Import: `import SearchResultLeadsList from './SearchResultLeadsList.vue';`
- Records: `const leadRecords = useMapGetter('conversationSearch/getLeadRecords');`
- Mapped: `const mappedLeads = computed(() => addTypeToRecords(leadRecords, 'lead'));`
- Sliced: `const leads = computed(() => sliceRecordsIfAllTab(mappedLeads));`
- Filter: `const filterLeads = filterByTab('leads');`
- `pages` ref: adicionar `leads: 1,`.
- `TABS_CONFIG`: adicionar (depois de `contacts`):

```js
  leads: {
    permissions: [...ROLES],
    count: () => mappedLeads.value.length,
  },
```

- No template, adicionar a section (espelhar a section dos contacts — mesma estrutura de `v-if="filterLeads"` + `:class="searchResultSectionClass"`):

```html
      <div v-if="filterLeads" :class="searchResultSectionClass">
        <SearchResultLeadsList
          :leads="leads"
          :query="query"
          :is-fetching="uiFlags.lead.isFetching"
          :show-title="isSelectedTabAll"
        />
      </div>
```

(Localizar como a section de contacts está estruturada no template e espelhar exatamente — inclusive botão "view more" se existir por section; se o "view more" navegar por tab, usar `tab: 'leads'`.)

- [ ] **Step 6: i18n do search**

`en/search.json`: em `TABS` adicionar `"LEADS": "Leads",` e em `SECTION` adicionar `"LEADS": "Leads",`.

`pt_BR/search.json`: idem (`"LEADS": "Leads"` nos dois blocos).

- [ ] **Step 7: Prettier + commit**

```bash
npx prettier --write app/javascript/dashboard/api/search.js app/javascript/dashboard/store/modules/conversationSearch.js app/javascript/dashboard/modules/search/components/SearchResultLeadsList.vue app/javascript/dashboard/modules/search/components/SearchView.vue
git add app/javascript/dashboard/api/search.js app/javascript/dashboard/store/mutation-types.js app/javascript/dashboard/store/modules/conversationSearch.js app/javascript/dashboard/modules/search/components/ app/javascript/dashboard/i18n/locale/en/search.json app/javascript/dashboard/i18n/locale/pt_BR/search.json
git commit --no-verify -m "feat(search): leads na busca global (frontend: tab + lista)"
```

---

### Task 4: Guia do monitor de uptime (item 27 — doc, gate Eduardo)

**Files:**
- Create: `docs/uptime-monitor.md`

- [ ] **Step 1: Escrever o guia**

`docs/uptime-monitor.md`:

```markdown
# Monitor de uptime do hub (item 27 do plano mestre)

O hub (chat.ramonantonio.adv.br) não tem monitoramento: se cair num sábado,
ninguém fica sabendo. A solução escolhida é **UptimeRobot no plano free**
(50 monitores, checagem a cada 5 min) — é configuração externa, sem código.

## O que o Eduardo precisa fazer (~5 minutos)

1. Criar conta em https://uptimerobot.com (free).
2. **Add New Monitor**:
   - Monitor type: `HTTP(s) — Keyword`
   - Friendly name: `ramon-hub`
   - URL: `https://chat.ramonantonio.adv.br/api`
   - Keyword: `version` (o endpoint `/api` responde JSON com a versão; se a
     palavra sumir da resposta, o hub está fora ou quebrado)
   - Keyword type: `exists` (alerta quando NÃO encontrar)
   - Monitoring interval: 5 minutes
3. **Alert contacts**: e-mail do Eduardo (padrão). Opcional: adicionar o
   webhook do ntfy.sh como contato (`https://ntfy.sh/<tópico do hub>`) pra
   tocar no celular — o mesmo tópico do push de lead novo.
4. Testar: pausar o monitor → Resume → conferir que o status fica "Up".

## Por que `/api` e não a home

`/api` é público, leve, não exige login e responde JSON do Rails — se ele
responde com `version`, o app (e o banco por trás do boot) está de pé. A home
redireciona pra tela de login do Vue e pode mascarar problemas de backend.

## Quando evoluir

- Sentry self-host (erros de aplicação) quando houver equipe — item 27, parte 2.
- Se o free tier apertar (retenção de logs), o plano pago é barato; reavaliar só com dor real.
```

- [ ] **Step 2: Commit**

```bash
git add docs/uptime-monitor.md
git commit --no-verify -m "docs: guia do monitor de uptime (UptimeRobot) - item 27"
```

---

## Verificação final (whole-branch)

- Push, PR base `ramon`, título `feat: atalhos no kanban + leads na busca global + guia uptime`.
- CI: `gh pr view <N> --json statusCheckRollup` — N/N completed + zero não-success.
- Sem migração → deploy = imagem nova apenas.
- Anotar no PR: (a) resultado de lead sem conversa navega pro funil — apontar pra Linha da Vida quando a outra frente mergear; (b) item 27 tem gate do Eduardo (criar a conta UptimeRobot seguindo docs/uptime-monitor.md).
