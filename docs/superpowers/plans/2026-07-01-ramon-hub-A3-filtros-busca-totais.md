# A3 — Filtros, busca e totais por coluna — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Filtrar/buscar leads no Kanban (server-side, filtro persistido) e mostrar contagem + soma em R$ por coluna.

**Architecture:** `leads#index` passa a aceitar params de filtro/busca; `lead_config#show` expõe as origens distintas. No front, uma barra `KanbanFilters` controla o estado `filters` na store `leads`, que re-busca no servidor a cada mudança e persiste em localStorage; cada `KanbanColumn` soma o `value` dos leads recebidos.

**Tech Stack:** Rails 7 (Chatwoot v4.15.1 fork), RSpec; Vue 3 `<script setup>`, Vuex, vitest, Tailwind.

## Global Constraints

- Branch: `feat/ramon-hub-a3-filtros` (a partir de `ramon`).
- **Sem ambiente local** (sem Ruby/pnpm): verificação = branch → PR → CI `run_foss_spec` (rspec + vitest + rubocop + eslint). NÃO rodar testes localmente; só `npx prettier`.
- **Sem migração** (só leitura filtrada). Deploy = `docker compose pull chatwoot-web chatwoot-worker && up -d` (sem `db:migrate`).
- Filtragem **server-side**; **dono** = filtro único casando `sdr_id` OU `closer_id`; **soma R$** reflete só os leads filtrados; **origem** vem do backend (lista distinta); filtro **persistido** em localStorage.
- Evento custom Vue em **camelCase** no `defineEmits` (listener kebab no template); sem `:value=""`.
- Componente dentro de slot de `<Draggable>` só é testável com `mount` (não `shallowMount`).
- Specs de controller que criam config/leads limpam a tabela semeada com **`destroy_all`** (não `delete_all`); `create(:account)` semeia via `after_create`.
- rubocop do fork pega `Rails/SkipsModelValidations` (evitar `update_all`/`update_column`) e `Metrics/*` (métodos enxutos, extrair privados).
- `git add <paths>` específico (nunca `git add -A`).
- Commits `feat:`/`test:`/`chore:`, terminando com `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.

---

## File Structure

**Backend (modificados):**
- `app/controllers/api/v1/accounts/leads_controller.rb` — `index` aplica filtros (método privado `filtered_leads`).
- `app/controllers/api/v1/accounts/lead_config_controller.rb` — `show` carrega `@sources`.
- `app/views/api/v1/accounts/lead_config/show.json.jbuilder` — expõe `sources`.
- specs: `spec/controllers/api/v1/accounts/leads_controller_spec.rb` (novo ou adicionar), `.../lead_config_controller_spec.rb`.

**Frontend (novos):**
- `app/javascript/dashboard/routes/dashboard/ramon/components/kanban/KanbanFilters.vue`
- specs `.spec.js` correspondentes.

**Frontend (modificados):**
- `app/javascript/dashboard/api/leads.js` — override `get(params)`.
- `app/javascript/dashboard/store/mutation-types.js` — `SET_LEAD_FILTERS`.
- `app/javascript/dashboard/store/modules/leads.js` — estado `filters`, getter `getFilters`, actions `setFilters`/`loadFilters`, params no `get`.
- `app/javascript/dashboard/store/modules/leadConfig.js` — estado/getter `sources` (do `SET_LEAD_CONFIG`).
- `app/javascript/dashboard/routes/dashboard/ramon/components/kanban/KanbanColumn.vue` — soma R$ no cabeçalho.
- `.../kanban/KanbanBoard.vue` — monta `KanbanFilters`; `loadFilters` no mount.
- `i18n/locale/{en,pt_BR}/ramon.json` — rótulos dos filtros.

---

## Task 1: Backend — filtros no `leads#index`

**Files:**
- Modify: `app/controllers/api/v1/accounts/leads_controller.rb`
- Test: `spec/controllers/api/v1/accounts/leads_controller_spec.rb`

**Interfaces:**
- Produces: `GET /api/v1/accounts/:id/leads` aceita params opcionais `benefit_type_id`, `lead_priority_id`, `agent_id` (casa sdr_id OU closer_id), `source`, `q` (ILIKE em leads.name / contacts.name / contacts.phone_number via left join). Ausência de um param = sem aquele filtro.

- [ ] **Step 1: Write the failing test**

```ruby
# spec/controllers/api/v1/accounts/leads_controller_spec.rb
require 'rails_helper'

RSpec.describe 'Leads API (filtros)', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:stage) { account.lead_stages.first || account.lead_stages.create!(name: 'Novo') }
  let(:bpc) { account.benefit_types.create!(name: 'BPC-teste') }
  let(:alta) { account.lead_priorities.create!(name: 'Alta-teste', weight: 9) }

  def ids(response)
    response.parsed_body['payload'].map { |l| l['id'] }
  end

  it 'filtra por benefit_type_id' do
    a = account.leads.create!(name: 'A', lead_stage: stage, benefit_type: bpc)
    account.leads.create!(name: 'B', lead_stage: stage)
    get "/api/v1/accounts/#{account.id}/leads", params: { benefit_type_id: bpc.id },
        headers: admin.create_new_auth_token
    expect(ids(response)).to eq([a.id])
  end

  it 'filtra por agent_id casando sdr OU closer' do
    agent = create(:user, account: account, role: :agent)
    as_sdr = account.leads.create!(name: 'S', lead_stage: stage, sdr_id: agent.id)
    as_closer = account.leads.create!(name: 'C', lead_stage: stage, closer_id: agent.id)
    account.leads.create!(name: 'N', lead_stage: stage)
    get "/api/v1/accounts/#{account.id}/leads", params: { agent_id: agent.id },
        headers: admin.create_new_auth_token
    expect(ids(response)).to contain_exactly(as_sdr.id, as_closer.id)
  end

  it 'busca q por nome do lead mesmo sem contato' do
    hit = account.leads.create!(name: 'Joana Silva', lead_stage: stage)
    account.leads.create!(name: 'Outro', lead_stage: stage)
    get "/api/v1/accounts/#{account.id}/leads", params: { q: 'joana' },
        headers: admin.create_new_auth_token
    expect(ids(response)).to eq([hit.id])
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

CI run: `bundle exec rspec spec/controllers/api/v1/accounts/leads_controller_spec.rb`
Expected: FAIL (filtros ainda não aplicados — retorna todos).

- [ ] **Step 3: Write minimal implementation**

Substituir o `index` e adicionar o método privado (manter o resto do controller intacto):

```ruby
  def index
    @leads = filtered_leads
  end
```

E, na seção `private` (junto de `fetch_lead`/`permitted_params`):

```ruby
  def filtered_leads
    leads = policy_scope(Current.account.leads)
    leads = leads.where(benefit_type_id: params[:benefit_type_id]) if params[:benefit_type_id].present?
    leads = leads.where(lead_priority_id: params[:lead_priority_id]) if params[:lead_priority_id].present?
    leads = leads.where('sdr_id = :a OR closer_id = :a', a: params[:agent_id]) if params[:agent_id].present?
    leads = leads.where(source: params[:source]) if params[:source].present?
    leads = search_leads(leads, params[:q]) if params[:q].present?
    leads
  end

  def search_leads(leads, query)
    like = "%#{query}%"
    leads.left_joins(:contact)
         .where('leads.name ILIKE :q OR contacts.name ILIKE :q OR contacts.phone_number ILIKE :q', q: like)
  end
```

- [ ] **Step 4: Run test to verify it passes**

CI run: `bundle exec rspec spec/controllers/api/v1/accounts/leads_controller_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/api/v1/accounts/leads_controller.rb spec/controllers/api/v1/accounts/leads_controller_spec.rb
git commit -m "feat: leads#index — filtros benefit/priority/agent/source + busca q"
```

---

## Task 2: Backend — `lead_config#show` expõe `sources`

**Files:**
- Modify: `app/controllers/api/v1/accounts/lead_config_controller.rb`
- Modify: `app/views/api/v1/accounts/lead_config/show.json.jbuilder`
- Test: `spec/controllers/api/v1/accounts/lead_config_controller_spec.rb` (adicionar exemplo)

**Interfaces:**
- Produces: `lead_config#show` retorna `sources` = origens distintas não-vazias, ordenadas.

- [ ] **Step 1: Write the failing test**

```ruby
# adicionar em spec/controllers/api/v1/accounts/lead_config_controller_spec.rb
# (se o arquivo não existir, criar com o require + describe padrão)
  it 'retorna as origens distintas ordenadas' do
    stage = account.lead_stages.first
    account.leads.create!(name: 'A', lead_stage: stage, source: 'Meta Ads')
    account.leads.create!(name: 'B', lead_stage: stage, source: 'Indicação')
    account.leads.create!(name: 'C', lead_stage: stage, source: 'Meta Ads')
    account.leads.create!(name: 'D', lead_stage: stage, source: nil)
    get "/api/v1/accounts/#{account.id}/lead_config", headers: admin.create_new_auth_token
    expect(response.parsed_body['sources']).to eq(['Indicação', 'Meta Ads'])
  end
```

(O topo do spec deve ter `let(:account) { create(:account) }` e `let(:admin) { create(:user, account: account, role: :administrator) }`.)

- [ ] **Step 2: Run test to verify it fails**

CI run: `bundle exec rspec spec/controllers/api/v1/accounts/lead_config_controller_spec.rb`
Expected: FAIL (`sources` ausente/nil).

- [ ] **Step 3: Write minimal implementation**

Controller:

```ruby
  def show
    @stages = Current.account.lead_stages
    @benefit_types = Current.account.benefit_types
    @priorities = Current.account.lead_priorities
    @sources = Current.account.leads.where.not(source: [nil, '']).distinct.pluck(:source).sort
  end
```

View (adicionar ao fim de `show.json.jbuilder`):

```ruby
json.sources @sources
```

- [ ] **Step 4: Run test to verify it passes**

CI run: `bundle exec rspec spec/controllers/api/v1/accounts/lead_config_controller_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/api/v1/accounts/lead_config_controller.rb app/views/api/v1/accounts/lead_config/show.json.jbuilder spec/controllers/api/v1/accounts/lead_config_controller_spec.rb
git commit -m "feat: lead_config#show expõe origens distintas (sources)"
```

---

## Task 3: Front — `LeadsAPI.get(params)` + store `leads` (filtros + persistência)

**Files:**
- Modify: `app/javascript/dashboard/api/leads.js`
- Modify: `app/javascript/dashboard/store/mutation-types.js` (após `MERGE_LEAD`)
- Modify: `app/javascript/dashboard/store/modules/leads.js`
- Test: `app/javascript/dashboard/store/modules/specs/leads/filters.spec.js`

**Interfaces:**
- Consumes: `SET_LEAD_FILTERS` mutation-type.
- Produces: `LeadsAPI.get(params)` (envia query params); store `leads` com `state.filters` (`{ benefitTypeId, leadPriorityId, agentId, source, q }`), getter `getFilters`, actions `setFilters(partial)` (merge + persiste localStorage `ramon_lead_filters` + re-`get`) e `loadFilters()` (lê localStorage + `get`); `get` monta os params snake_case a partir de `state.filters` (omitindo vazios).

- [ ] **Step 1: Write the failing test**

```javascript
// app/javascript/dashboard/store/modules/specs/leads/filters.spec.js
import axios from 'axios';
import { actions } from '../../leads';
import types from '../../../mutation-types';

global.axios = axios;
vi.mock('axios');

describe('leads filters', () => {
  const commit = vi.fn();
  const dispatch = vi.fn();
  beforeEach(() => {
    vi.clearAllMocks();
    localStorage.clear();
  });

  it('setFilters comita, persiste e re-busca', async () => {
    await actions.setFilters({ commit, dispatch }, { benefitTypeId: 5 });
    expect(commit).toHaveBeenCalledWith(types.SET_LEAD_FILTERS, { benefitTypeId: 5 });
    expect(JSON.parse(localStorage.getItem('ramon_lead_filters'))).toEqual({ benefitTypeId: 5 });
    expect(dispatch).toHaveBeenCalledWith('get');
  });

  it('get envia os filtros como params snake_case, omitindo vazios', async () => {
    axios.get.mockResolvedValue({ data: { payload: [] } });
    const state = { filters: { benefitTypeId: 5, agentId: null, source: '', q: 'ana' } };
    await actions.get({ commit, state });
    expect(axios.get).toHaveBeenCalledWith(
      expect.any(String),
      { params: { benefit_type_id: 5, q: 'ana' } }
    );
  });

  it('loadFilters lê do localStorage e busca', async () => {
    localStorage.setItem('ramon_lead_filters', JSON.stringify({ q: 'x' }));
    await actions.loadFilters({ commit, dispatch });
    expect(commit).toHaveBeenCalledWith(types.SET_LEAD_FILTERS, { q: 'x' });
    expect(dispatch).toHaveBeenCalledWith('get');
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

CI run: `pnpm test app/javascript/dashboard/store/modules/specs/leads/filters.spec.js`
Expected: FAIL (`setFilters is not a function`).

- [ ] **Step 3: Write minimal implementation**

`api/leads.js` — override `get` para aceitar params:

```javascript
import ApiClient from './ApiClient';

class LeadsAPI extends ApiClient {
  constructor() {
    super('leads', { accountScoped: true });
  }

  get(params = {}) {
    return axios.get(this.url, { params });
  }
}

export default new LeadsAPI();
```

Adicionar `/* global axios */` no topo do arquivo (o ApiClient usa axios global; a regra no-undef exige a diretiva).

`store/mutation-types.js` — após `MERGE_LEAD: 'MERGE_LEAD',`:

```javascript
  SET_LEAD_FILTERS: 'SET_LEAD_FILTERS',
```

`store/modules/leads.js` — adicionar ao `state`:

```javascript
  filters: {
    benefitTypeId: null,
    leadPriorityId: null,
    agentId: null,
    source: '',
    q: '',
  },
```

Adicionar getter:

```javascript
  getFilters(_state) {
    return _state.filters;
  },
```

Helpers no topo do módulo (após os imports):

```javascript
const FILTERS_KEY = 'ramon_lead_filters';

const toParams = filters => {
  const map = {
    benefit_type_id: filters.benefitTypeId,
    lead_priority_id: filters.leadPriorityId,
    agent_id: filters.agentId,
    source: filters.source,
    q: filters.q,
  };
  return Object.fromEntries(
    Object.entries(map).filter(([, v]) => v !== null && v !== undefined && v !== '')
  );
};
```

Substituir a action `get` e adicionar `setFilters`/`loadFilters`:

```javascript
  get: async ({ commit, state }) => {
    commit(types.SET_LEAD_UI_FLAG, { isFetching: true });
    try {
      const response = await LeadsAPI.get(toParams(state.filters));
      commit(types.SET_LEADS, response.data.payload);
    } finally {
      commit(types.SET_LEAD_UI_FLAG, { isFetching: false });
    }
  },
  setFilters: async ({ commit, dispatch }, partial) => {
    commit(types.SET_LEAD_FILTERS, partial);
    try {
      const merged = JSON.parse(localStorage.getItem(FILTERS_KEY) || '{}');
      localStorage.setItem(FILTERS_KEY, JSON.stringify({ ...merged, ...partial }));
    } catch (e) {
      // localStorage indisponível: seguimos sem persistir
    }
    await dispatch('get');
  },
  loadFilters: async ({ commit, dispatch }) => {
    try {
      const saved = JSON.parse(localStorage.getItem(FILTERS_KEY) || '{}');
      if (Object.keys(saved).length) commit(types.SET_LEAD_FILTERS, saved);
    } catch (e) {
      // localStorage indisponível/corrompido: ignora
    }
    await dispatch('get');
  },
```

Adicionar mutation:

```javascript
  [types.SET_LEAD_FILTERS](_state, partial) {
    _state.filters = { ..._state.filters, ...partial };
  },
```

> Nota: em `get` o teste chama sem `state.filters` definido? Não — o teste passa `state`. Em runtime `state.filters` sempre existe (default acima).

- [ ] **Step 4: Run test to verify it passes**

CI run: `pnpm test app/javascript/dashboard/store/modules/specs/leads/filters.spec.js`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/javascript/dashboard/api/leads.js app/javascript/dashboard/store/mutation-types.js app/javascript/dashboard/store/modules/leads.js app/javascript/dashboard/store/modules/specs/leads/filters.spec.js
git commit -m "feat: store leads — filtros server-side + persistência (localStorage)"
```

---

## Task 4: Front — `KanbanFilters.vue` + `sources` no leadConfig + i18n

**Files:**
- Create: `app/javascript/dashboard/routes/dashboard/ramon/components/kanban/KanbanFilters.vue`
- Modify: `app/javascript/dashboard/store/modules/leadConfig.js` (state/getter `sources` + mapping no `SET_LEAD_CONFIG`)
- Modify: `i18n/locale/en/ramon.json`, `i18n/locale/pt_BR/ramon.json`
- Test: `.../kanban/specs/KanbanFilters.spec.js`

**Interfaces:**
- Consumes: getters `leadConfig/getBenefitTypes`, `leadConfig/getPriorities`, `leadConfig/getSources`, `agents/getAgents`; prop `filters`.
- Produces: `KanbanFilters` emite `update` (camelCase) com um objeto parcial de filtros (ex.: `{ benefitTypeId: 5 }`); a busca por texto é **debounced ~300ms**.

- [ ] **Step 1: Write the failing test**

```javascript
// app/javascript/dashboard/routes/dashboard/ramon/components/kanban/specs/KanbanFilters.spec.js
import { mount } from '@vue/test-utils';
import KanbanFilters from '../KanbanFilters.vue';

const stubStore = {
  getters: {
    'leadConfig/getBenefitTypes': [{ id: 1, name: 'BPC' }],
    'leadConfig/getPriorities': [{ id: 2, name: 'Alta' }],
    'leadConfig/getSources': ['Meta Ads'],
    'agents/getAgents': [{ id: 3, name: 'Eduardo' }],
  },
};

const mountFilters = () =>
  mount(KanbanFilters, {
    props: { filters: { benefitTypeId: null, leadPriorityId: null, agentId: null, source: '', q: '' } },
    global: {
      mocks: { $t: k => k },
      plugins: [{ install: app => { app.config.globalProperties.$store = stubStore; } }],
    },
  });

describe('KanbanFilters', () => {
  it('emite update ao escolher um benefício', async () => {
    const wrapper = mountFilters();
    await wrapper.find('[data-testid="filter-benefit"]').setValue('1');
    expect(wrapper.emitted().update[0][0]).toEqual({ benefitTypeId: '1' });
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

CI run: `pnpm test .../kanban/specs/KanbanFilters.spec.js`
Expected: FAIL (componente não existe).

- [ ] **Step 3: Write minimal implementation**

`leadConfig.js` — adicionar `sources: []` ao state, getter e mapping:

```javascript
// state: adicionar
  sources: [],
// getters: adicionar
  getSources: _state => _state.sources,
// mutation SET_LEAD_CONFIG: adicionar a linha
    _state.sources = data.sources || [];
```

`KanbanFilters.vue`:

```vue
<script setup>
import { ref, computed, watch } from 'vue';
import { useStoreGetters } from 'dashboard/composables/store';

const props = defineProps({
  filters: { type: Object, required: true },
});
const emit = defineEmits(['update']);

const getters = useStoreGetters();
const benefitTypes = computed(() => getters['leadConfig/getBenefitTypes'].value);
const priorities = computed(() => getters['leadConfig/getPriorities'].value);
const sources = computed(() => getters['leadConfig/getSources'].value);
const agents = computed(() => getters['agents/getAgents'].value);

const emitUpdate = partial => emit('update', partial);

// Busca com debounce ~300ms para não disparar um request por tecla.
const search = ref(props.filters.q);
let timer = null;
watch(search, value => {
  clearTimeout(timer);
  timer = setTimeout(() => emitUpdate({ q: value }), 300);
});
</script>

<template>
  <div class="flex flex-wrap items-center gap-2 px-4 py-2">
    <input
      v-model="search"
      data-testid="filter-search"
      class="px-3 py-1.5 text-sm rounded-lg bg-n-alpha-2 text-n-slate-12"
      :placeholder="$t('RAMON.FUNIL.FILTERS.SEARCH')"
    />
    <select
      data-testid="filter-benefit"
      class="px-2 py-1.5 text-sm rounded-lg bg-n-alpha-2 text-n-slate-12"
      :value="filters.benefitTypeId || ''"
      @change="emitUpdate({ benefitTypeId: $event.target.value || null })"
    >
      <option value="">{{ $t('RAMON.FUNIL.FILTERS.BENEFIT') }}</option>
      <option v-for="b in benefitTypes" :key="b.id" :value="b.id">{{ b.name }}</option>
    </select>
    <select
      data-testid="filter-priority"
      class="px-2 py-1.5 text-sm rounded-lg bg-n-alpha-2 text-n-slate-12"
      :value="filters.leadPriorityId || ''"
      @change="emitUpdate({ leadPriorityId: $event.target.value || null })"
    >
      <option value="">{{ $t('RAMON.FUNIL.FILTERS.PRIORITY') }}</option>
      <option v-for="p in priorities" :key="p.id" :value="p.id">{{ p.name }}</option>
    </select>
    <select
      data-testid="filter-agent"
      class="px-2 py-1.5 text-sm rounded-lg bg-n-alpha-2 text-n-slate-12"
      :value="filters.agentId || ''"
      @change="emitUpdate({ agentId: $event.target.value || null })"
    >
      <option value="">{{ $t('RAMON.FUNIL.FILTERS.AGENT') }}</option>
      <option v-for="a in agents" :key="a.id" :value="a.id">{{ a.name }}</option>
    </select>
    <select
      data-testid="filter-source"
      class="px-2 py-1.5 text-sm rounded-lg bg-n-alpha-2 text-n-slate-12"
      :value="filters.source || ''"
      @change="emitUpdate({ source: $event.target.value || '' })"
    >
      <option value="">{{ $t('RAMON.FUNIL.FILTERS.SOURCE') }}</option>
      <option v-for="s in sources" :key="s" :value="s">{{ s }}</option>
    </select>
    <button
      data-testid="filter-clear"
      class="px-3 py-1.5 text-sm rounded-lg text-n-slate-11 hover:text-n-slate-12"
      @click="emitUpdate({ benefitTypeId: null, leadPriorityId: null, agentId: null, source: '', q: '' }); search = ''"
    >
      {{ $t('RAMON.FUNIL.FILTERS.CLEAR') }}
    </button>
  </div>
</template>
```

i18n — adicionar ao bloco `FUNIL` de `pt_BR/ramon.json` (MERGEAR, não duplicar `FUNIL`):

```json
    "FILTERS": {
      "SEARCH": "Buscar nome ou contato…",
      "BENEFIT": "Benefício",
      "PRIORITY": "Prioridade",
      "AGENT": "Responsável",
      "SOURCE": "Origem",
      "CLEAR": "Limpar"
    }
```

E o equivalente traduzido em `en/ramon.json` (Search name or contact… / Benefit / Priority / Owner / Source / Clear).

- [ ] **Step 4: Run test to verify it passes**

CI run: `pnpm test .../kanban/specs/KanbanFilters.spec.js`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/javascript/dashboard/routes/dashboard/ramon/components/kanban/KanbanFilters.vue app/javascript/dashboard/routes/dashboard/ramon/components/kanban/specs/KanbanFilters.spec.js app/javascript/dashboard/store/modules/leadConfig.js app/javascript/dashboard/i18n/locale/en/ramon.json app/javascript/dashboard/i18n/locale/pt_BR/ramon.json
git commit -m "feat: KanbanFilters (benefício/prioridade/dono/origem/busca) + sources no leadConfig + i18n"
```

---

## Task 5: Front — total R$ na coluna + montar filtros no board

**Files:**
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/components/kanban/KanbanColumn.vue`
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/components/kanban/KanbanBoard.vue`
- Test: `.../kanban/specs/KanbanColumn.spec.js` (adicionar), `.../kanban/specs/KanbanBoard.spec.js` (adicionar)

**Interfaces:**
- Consumes: `leads/getFilters`, actions `leads/setFilters`/`leads/loadFilters`; `KanbanFilters` (Task 4).
- Produces: `KanbanColumn` mostra soma de `value` em BRL no cabeçalho; `KanbanBoard` monta `<KanbanFilters :filters @update="leads/setFilters">` e chama `leads/loadFilters` no mount (no lugar do `leads/get`).

- [ ] **Step 1: Write the failing test**

```javascript
// adicionar em .../kanban/specs/KanbanColumn.spec.js
it('mostra a soma dos valores em BRL', () => {
  const wrapper = mount(KanbanColumn, {
    props: {
      stage: { id: 1, name: 'Novo', color: '#fff' },
      leads: [
        { id: 1, lead_stage_id: 1, value: 1500 },
        { id: 2, lead_stage_id: 1, value: null },
        { id: 3, lead_stage_id: 1, value: 500.5 },
      ],
    },
    global: { mocks: { $t: k => k } },
  });
  // 2000,50 formatado em pt-BR
  expect(wrapper.find('[data-testid="stage-total"]').text()).toContain('2.000,50');
});
```

```javascript
// adicionar em .../kanban/specs/KanbanBoard.spec.js
it('carrega filtros no mount e reage ao update dos filtros', () => {
  const wrapper = mountBoard(); // helper existente
  expect(dispatch).toHaveBeenCalledWith('leads/loadFilters');
  wrapper.findComponent({ name: 'KanbanFilters' }).vm.$emit('update', { q: 'ana' });
  expect(dispatch).toHaveBeenCalledWith('leads/setFilters', { q: 'ana' });
});
```

> Ajuste o mock do store do `KanbanBoard.spec` para incluir os getters que `KanbanFilters` consome (`leadConfig/getBenefitTypes|getPriorities|getSources`, `agents/getAgents`) e `leads/getFilters`, seguindo o padrão de store real (`createStore`) já usado no arquivo.

- [ ] **Step 2: Run test to verify it fails**

CI run: `pnpm test .../kanban/specs/KanbanColumn.spec.js .../kanban/specs/KanbanBoard.spec.js`
Expected: FAIL (sem `stage-total`; sem `loadFilters`).

- [ ] **Step 3: Write minimal implementation**

`KanbanColumn.vue` — no `<script setup>`, adicionar o cálculo:

```javascript
import { computed } from 'vue';
// ...
const totalValue = computed(() =>
  props.leads.reduce((sum, lead) => sum + (Number(lead.value) || 0), 0)
);
const brl = value =>
  new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(value);
```

E no cabeçalho, ao lado da contagem, adicionar o total (dentro do `<span class="flex items-center gap-2">`, antes do contador ou logo após):

```vue
        <span data-testid="stage-total" class="text-xs text-n-slate-9">
          {{ brl(totalValue) }}
        </span>
        <span class="text-xs text-n-slate-9">{{ localLeads.length }}</span>
```

`KanbanBoard.vue`:
- importar e montar `KanbanFilters` acima do bloco de colunas;
- ligar `:filters="filters"` (de `leads/getFilters`) e `@update="onFilterUpdate"`;
- `onFilterUpdate(partial)` → `store.dispatch('leads/setFilters', partial)`;
- no `onMounted`, trocar `store.dispatch('leads/get')` por `store.dispatch('leads/loadFilters')` (que já dispara o `get`); manter `leadConfig/get` e `agents/get`.

```javascript
import KanbanFilters from './KanbanFilters.vue';
// ...
const filters = computed(() => getters['leads/getFilters'].value);
const onFilterUpdate = partial => store.dispatch('leads/setFilters', partial);
// onMounted:
//   store.dispatch('leadConfig/get');
//   store.dispatch('leads/loadFilters');   // <- no lugar de leads/get
//   store.dispatch('agents/get');
```

```vue
    <KanbanFilters :filters="filters" @update="onFilterUpdate" />
```
(logo abaixo do cabeçalho do board, antes do `<div class="flex flex-1 ...">` das colunas.)

- [ ] **Step 4: Run test to verify it passes**

CI run: `pnpm test .../kanban/specs/KanbanColumn.spec.js .../kanban/specs/KanbanBoard.spec.js`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/javascript/dashboard/routes/dashboard/ramon/components/kanban/KanbanColumn.vue app/javascript/dashboard/routes/dashboard/ramon/components/kanban/KanbanBoard.vue app/javascript/dashboard/routes/dashboard/ramon/components/kanban/specs/KanbanColumn.spec.js app/javascript/dashboard/routes/dashboard/ramon/components/kanban/specs/KanbanBoard.spec.js
git commit -m "feat: total R$ por coluna + monta KanbanFilters e loadFilters no board"
```

---

## Task 6: Lint, PR, CI e deploy

**Files:** nenhum novo (ajustes de lint se o CI apontar).

- [ ] **Step 1: Prettier nos arquivos JS/Vue tocados**

```bash
cd app/javascript && npx prettier@3.3.3 --write \
  dashboard/routes/dashboard/ramon/components/kanban \
  dashboard/store/modules/leads.js dashboard/store/modules/leadConfig.js \
  dashboard/store/modules/specs/leads \
  dashboard/api/leads.js
cd ..
git add -A app/javascript && git commit -m "chore: prettier nos arquivos da A3" || true
```

> Se o prettier tocar arquivos fora da A3 (de fatias anteriores), reverter esses (`git checkout -- <path>`) e commitar só os da A3.

- [ ] **Step 2: Abrir o PR**

```bash
git push -u origin feat/ramon-hub-a3-filtros
gh pr create --base ramon --title "feat: A3 — filtros, busca e totais por coluna" \
  --body "Barra de filtros (benefício/prioridade/dono/origem) + busca (nome do lead e contato) server-side, filtro persistido em localStorage, e total (contagem + R$) por coluna. Sem migração."
```

- [ ] **Step 3: Acompanhar o CI e corrigir**

```bash
gh run list --workflow=run_foss_spec.yml -L 1
gh run watch <run-id> --exit-status
```

Lições de CI a vigiar: rubocop `Metrics/AbcSize` no `index`/`filtered_leads` (extrair `search_leads` já ajuda; disable inline se preciso); eslint `vue/custom-event-name-casing` (emit `update` é ok, minúsculo simples), `no-undef` do `axios` em `leads.js` (diretiva `/* global axios */`); specs de controller que criam leads podem colidir com o seed → usar `destroy_all` se necessário (aqui os testes criam leads próprios, sem depender de tabela vazia); mock do store no `KanbanBoard.spec` precisa dos getters novos.

- [ ] **Step 4: Merge (após CI verde)** — quem faz o merge é o Eduardo (OK explícito).

- [ ] **Step 5: Deploy na VPS** (Claude via SSH, com OK do Eduardo). **Sem `db:migrate`**:

```bash
ssh root@185.194.216.67 'cd /opt/intranet-ramon && docker compose pull chatwoot-web chatwoot-worker && docker compose up -d chatwoot-web chatwoot-worker'
```

Smoke: HTTP 200; abrir o Kanban → barra de filtros aparece; filtrar por benefício/prioridade/dono/origem recorta as colunas; buscar por nome/contato funciona; total (contagem + R$) por coluna reflete o filtrado; recarregar a página mantém o filtro. Smoke visual final = Eduardo.

---

## Self-Review

**Spec coverage:**
- Filtros benefício/prioridade/dono/origem (server-side) → Task 1 (backend) + Task 4 (UI). ✅
- Busca nome+contato (left join) → Task 1 + Task 4. ✅
- Dono = sdr OU closer → Task 1. ✅
- Origem via backend (sources) → Task 2 + Task 4. ✅
- Persistência localStorage → Task 3. ✅
- Totais contagem + R$ (filtrado) → Task 5. ✅
- Sem migração / CI / deploy → Global Constraints + Task 6. ✅

**Placeholder scan:** sem TBD/TODO; todo passo com código. ✅

**Type consistency:** `filters` keys (`benefitTypeId/leadPriorityId/agentId/source/q`) idênticas entre store (Task 3), `toParams`, `KanbanFilters` emits (Task 4) e board (Task 5). `SET_LEAD_FILTERS` usado em Task 3 e definido lá. `getSources` definido em Task 4 e consumido por `KanbanFilters`. `leads/loadFilters`/`setFilters` consistentes entre Tasks 3 e 5. ✅
</content>
