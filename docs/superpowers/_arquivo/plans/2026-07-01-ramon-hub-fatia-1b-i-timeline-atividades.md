# Fatia 1b-i — Timeline de atividades do lead Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Entregar a aba **Histórico** do Painel do Lead com uma timeline cronológica dos eventos do funil (criação, mudança de etapa, atribuição SDR/Closer, prioridade, valor) — cada um com o **autor** que fez a ação.

**Architecture:** Nova tabela `lead_activities` (log append-only). Um callback no `Lead` grava uma atividade por campo relevante que muda em cada update (e uma `created` no create), resolvendo rótulos legíveis e capturando `Current.user` como autor. API read-only aninhada lista as atividades; uma action de store as busca sob demanda; um componente Vue `LeadHistory.vue` (nova aba no `LeadConversationPanel`) renderiza a timeline.

**Tech Stack:** Ruby on Rails (migration + model + callback + API), Vue 3 `<script setup>` + Vuex, RSpec, Vitest, Tailwind. Fork do Chatwoot v4.15.1, branch `ramon`.

## Global Constraints

- Fork merge-safe: código novo sob `ramon/` (frontend) ou backend fork-owned; **toda edição de arquivo core registrada** em `docs/FORK-PONTOS-DE-REGISTRO.md` (file, trecho, motivo, fase). Core tocado nesta fatia: `config/routes.rb`, `app/models/lead.rb`, `app/models/account.rb`, `LeadConversationPanel.vue`.
- **Sem ambiente de teste local** (nem Ruby/Postgres nem pnpm). Verificação = feature branch → PR → CI (`run_foss_spec`: rspec+vitest+rubocop+eslint). Só `npx prettier@3.3.3 --write` roda local. Escrever specs TDD-first e raciocinar RED/GREEN; marcar "CI-deferred".
- **ESTA FATIA TEM MIGRAÇÃO.** CI carrega schema via `db:schema:load` → **`db/schema.rb` precisa ser regenerado** e commitado, MAS a máquina não roda migration. **O implementer NÃO edita `db/schema.rb`**; o controller regenera na VPS (scratch DB, padrão das fatias 2A/2B/2C) antes do merge (Task 8). Deploy desta fatia roda `db:migrate` (via `chatwoot-init`) + restart — não é só pull+up.
- Rubocop: `Rails/SkipsModelValidations` pega `update_all`/`update_column`/`insert_all` sem validação → usar `create!`/`update!` ou inline disable; métodos longos/complexos → extrair helper ou disable pontual. Migration grande viola Metrics → disable pontual.
- eslint: evento custom emitido **camelCase**, listener **kebab** no template; sem `:value=""`; `vue/define-macros-order` exige **defineProps antes de defineOptions**. Componente dentro de slot `<Draggable>` → `mount`, não `shallowMount` (não se aplica aqui).
- i18n: chaves em `i18n/locale/{en,pt_BR}/ramon.json`, já registrado (spread) nos dois `index.js`.
- Autor: `Current.user` está disponível no callback do model durante o request (setado em `ApplicationController#set_current_user`). Ações do sistema (auto-criação via listener, jobs) têm `Current.user` nil → `user_id` nulo. **Nunca falhar a operação do lead se o autor for nil.**
- Regra de ouro: nada no ar sem OK explícito do Eduardo; merge/deploy são dele.

---

### Task 1: Tabela `lead_activities` + model + associação

**Files:**
- Create: `db/migrate/<timestamp>_create_lead_activities.rb`
- Create: `app/models/lead_activity.rb`
- Modify: `app/models/account.rb` (bloco has_many de leads, ~linhas 85-88)
- Modify: `app/models/lead.rb` (associação `has_many :lead_activities`)
- Test: `spec/models/lead_activity_spec.rb`
- Modify: `docs/FORK-PONTOS-DE-REGISTRO.md`

**Interfaces:**
- Produces: model `LeadActivity` com colunas `account_id`, `lead_id`, `user_id` (nullable), `kind` (string), `from_value` (string, nullable), `to_value` (string, nullable), `created_at`; associações `belongs_to :account`, `belongs_to :lead`, `belongs_to :user, optional: true`; validação `validates :kind, presence: true`.

- [ ] **Step 1: Escrever o model spec que falha**

```ruby
# spec/models/lead_activity_spec.rb
require 'rails_helper'

RSpec.describe LeadActivity do
  let(:account) { create(:account) }
  let(:lead) { create(:lead, account: account) }

  it 'is valid with a lead, kind and no user (system)' do
    activity = described_class.new(account: account, lead: lead, kind: 'created')
    expect(activity).to be_valid
    expect(activity.user).to be_nil
  end

  it 'requires a kind' do
    activity = described_class.new(account: account, lead: lead, kind: nil)
    expect(activity).not_to be_valid
  end

  it 'belongs to an optional user (author)' do
    user = create(:user, account: account)
    activity = described_class.create!(account: account, lead: lead, user: user,
                                       kind: 'stage_changed', from_value: 'Novo', to_value: 'Qualificação')
    expect(activity.reload.user).to eq(user)
  end
end
```

- [ ] **Step 2: Rodar o spec (CI) e ver falhar** — Esperado: FAIL (`uninitialized constant LeadActivity`).

- [ ] **Step 3: Criar a migration**

```ruby
# db/migrate/<timestamp>_create_lead_activities.rb
class CreateLeadActivities < ActiveRecord::Migration[7.0]
  def change
    create_table :lead_activities do |t|
      t.references :account, null: false, foreign_key: true
      t.references :lead, null: false, foreign_key: true
      t.references :user, null: true, foreign_key: true
      t.string :kind, null: false
      t.string :from_value
      t.string :to_value
      t.datetime :created_at, null: false
    end
    add_index :lead_activities, [:lead_id, :created_at]
  end
end
```

Use o mesmo `ActiveRecord::Migration[X.Y]` das migrations vizinhas (confira a versão numa migration recente do fork, ex. as da fatia 2A). Só `created_at` (log append-only, sem `updated_at`).

- [ ] **Step 4: Criar o model**

```ruby
# app/models/lead_activity.rb
class LeadActivity < ApplicationRecord
  belongs_to :account
  belongs_to :lead
  belongs_to :user, optional: true

  validates :kind, presence: true

  default_scope { order(created_at: :asc) }
end
```

- [ ] **Step 5: Adicionar as associações**

Em `app/models/account.rb`, no bloco has_many (junto de `has_many :leads`):
```ruby
has_many :lead_activities, dependent: :destroy_async
```
Em `app/models/lead.rb`, junto das associações:
```ruby
has_many :lead_activities, dependent: :destroy_async
```

- [ ] **Step 6: Registrar no FORK-PONTOS**

Adicionar linhas: `app/models/account.rb` (has_many :lead_activities), `app/models/lead.rb` (has_many :lead_activities) — motivo: timeline de atividades do lead — fase 1b-i.

- [ ] **Step 7: Commit** (NÃO editar `db/schema.rb` — o controller regenera na VPS)

```bash
git add db/migrate app/models/lead_activity.rb app/models/account.rb app/models/lead.rb \
        spec/models/lead_activity_spec.rb docs/FORK-PONTOS-DE-REGISTRO.md
git commit -m "feat: add lead_activities table and model"
```

---

### Task 2: Callback no `Lead` grava as atividades (com autor)

**Files:**
- Modify: `app/models/lead.rb`
- Test: `spec/models/lead_spec.rb` (adicionar contexto)

**Interfaces:**
- Consumes: `LeadActivity` (Task 1), `Current.user`.
- Produces: ao criar um Lead → 1 `LeadActivity` `kind:'created'`; a cada update que muda `lead_stage_id`/`sdr_id`/`closer_id`/`lead_priority_id`/`value` → 1 `LeadActivity` por campo, `kind` ∈ {stage_changed, sdr_changed, closer_changed, priority_changed, value_changed}, com `from_value`/`to_value` resolvidos para rótulos e `user_id` = `Current.user&.id`.

- [ ] **Step 1: Escrever o spec que falha**

```ruby
# dentro de spec/models/lead_spec.rb
RSpec.describe Lead do
  let(:account) { create(:account) }
  before { Current.user = nil }
  after { Current.user = nil }

  it 'records a created activity on creation' do
    lead = create(:lead, account: account)
    activity = lead.lead_activities.find_by(kind: 'created')
    expect(activity).to be_present
    expect(activity.user).to be_nil
  end

  it 'records a stage_changed activity with labels and author on stage update' do
    agent = create(:user, account: account)
    novo = create(:lead_stage, account: account, name: 'Fase A')
    prox = create(:lead_stage, account: account, name: 'Fase B')
    lead = create(:lead, account: account, lead_stage: novo)
    Current.user = agent
    lead.update!(lead_stage: prox)
    act = lead.lead_activities.find_by(kind: 'stage_changed')
    expect(act.from_value).to eq('Fase A')
    expect(act.to_value).to eq('Fase B')
    expect(act.user).to eq(agent)
  end

  it 'records a value_changed activity' do
    lead = create(:lead, account: account, value: 100)
    lead.update!(value: 250)
    act = lead.lead_activities.find_by(kind: 'value_changed')
    expect(act.from_value).to eq('100.0')
    expect(act.to_value).to eq('250.0')
  end
end
```

- [ ] **Step 2: Rodar (CI) e ver falhar** — Esperado: FAIL (nenhuma atividade gravada).

- [ ] **Step 3: Implementar os callbacks**

Em `app/models/lead.rb`, adicionar (sem remover os `dispatch_*` existentes):

```ruby
after_create_commit :record_created_activity
after_update_commit :record_change_activities

private

def record_created_activity
  lead_activities.create!(account: account, user: Current.user, kind: 'created', to_value: source)
end

def record_change_activities
  record_change('lead_stage_id', 'stage_changed') { |id| LeadStage.find_by(id: id)&.name }
  record_change('sdr_id', 'sdr_changed') { |id| User.find_by(id: id)&.name }
  record_change('closer_id', 'closer_changed') { |id| User.find_by(id: id)&.name }
  record_change('lead_priority_id', 'priority_changed') { |id| LeadPriority.find_by(id: id)&.name }
  record_change('value', 'value_changed') { |v| v&.to_s }
end

def record_change(attribute, kind)
  return unless saved_changes.key?(attribute)

  old_raw, new_raw = saved_changes[attribute]
  lead_activities.create!(
    account: account, user: Current.user, kind: kind,
    from_value: yield(old_raw), to_value: yield(new_raw)
  )
end
```

Notas: `saved_changes` está disponível em `after_update_commit`; `lead_activities.create!` não dispara update no Lead (sem loop). `Current.user` pode ser nil (sistema) → `user` nil, ok. Se `record_change` estourar `Metrics/AbcSize` no rubocop, manter — cada helper é pequeno; se o cop reclamar do `record_change_activities`, `# rubocop:disable Metrics/MethodLength` pontual.

- [ ] **Step 4: Rodar (CI) e ver passar** — Esperado: PASS nos 3 casos.

- [ ] **Step 5: Registrar no FORK-PONTOS** — `app/models/lead.rb` (callbacks record_created_activity/record_change_activities) — motivo: timeline de atividades — fase 1b-i.

- [ ] **Step 6: Commit**

```bash
git add app/models/lead.rb spec/models/lead_spec.rb docs/FORK-PONTOS-DE-REGISTRO.md
git commit -m "feat: record lead activities on create and field changes"
```

---

### Task 3: API read-only de atividades (controller + rota + policy + views)

**Files:**
- Create: `app/controllers/api/v1/accounts/lead_activities_controller.rb`
- Create: `app/policies/lead_activity_policy.rb`
- Create: `app/views/api/v1/accounts/lead_activities/index.json.jbuilder`
- Create: `app/views/api/v1/accounts/lead_activities/_lead_activity.json.jbuilder`
- Modify: `config/routes.rb` (bloco `resources :leads`)
- Test: `spec/controllers/api/v1/accounts/lead_activities_controller_spec.rb`
- Modify: `docs/FORK-PONTOS-DE-REGISTRO.md`

**Interfaces:**
- Consumes: `LeadActivity` (Task 1/2).
- Produces: `GET /api/v1/accounts/:account_id/leads/:lead_id/activities` → `{ payload: [ {id, kind, from_value, to_value, author_name, created_at}, ... ] }`, ordem cronológica asc.

- [ ] **Step 1: Escrever o request spec que falha**

```ruby
# spec/controllers/api/v1/accounts/lead_activities_controller_spec.rb
require 'rails_helper'

RSpec.describe 'Lead Activities API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:lead) { create(:lead, account: account) }

  it 'lists the activities of a lead in chronological order' do
    lead.lead_activities.create!(account: account, kind: 'created', created_at: 2.days.ago)
    lead.lead_activities.create!(account: account, kind: 'stage_changed',
                                 from_value: 'Novo', to_value: 'Qualificação', user: admin, created_at: 1.hour.ago)

    get "/api/v1/accounts/#{account.id}/leads/#{lead.id}/activities",
        headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    payload = response.parsed_body['payload']
    expect(payload.map { |a| a['kind'] }).to eq(%w[created stage_changed])
    expect(payload.last['author_name']).to eq(admin.name)
    expect(payload.last['to_value']).to eq('Qualificação')
  end
end
```

- [ ] **Step 2: Rodar (CI) e ver falhar** — Esperado: FAIL (RoutingError).

- [ ] **Step 3: Rota aninhada**

Em `config/routes.rb`, no bloco `resources :leads ... do`:
```ruby
resources :activities, only: [:index], controller: 'lead_activities'
```
(dentro do mesmo `do...end` que já tem `collection { post :for_conversation }`).

- [ ] **Step 4: Controller**

```ruby
# app/controllers/api/v1/accounts/lead_activities_controller.rb
class Api::V1::Accounts::LeadActivitiesController < Api::V1::Accounts::BaseController
  before_action :fetch_lead

  def index
    authorize(@lead, :show?)
    @activities = @lead.lead_activities
  end

  private

  def fetch_lead
    @lead = Current.account.leads.find(params[:lead_id])
  end
end
```

Confirme o namespace/superclasse lendo o `leads_controller.rb` já existente e siga IGUAL (mesma superclasse `Api::V1::Accounts::BaseController`, mesmo estilo). O `authorize(@lead, :show?)` reusa a LeadPolicy (admin/agent) — **não** dependa do `check_authorization` default derivar `index?` da LeadActivityPolicy a menos que você a defina (ver Step 5).

- [ ] **Step 5: Policy**

O `BaseController` chama `check_authorization`, que faz `authorize(<Model>)` derivando a policy do controller (`LeadActivityPolicy#index?`). Crie a policy pra não dar `Pundit::NotDefinedError`:
```ruby
# app/policies/lead_activity_policy.rb
class LeadActivityPolicy < ApplicationPolicy
  def index?
    @account_user.administrator? || @account_user.agent?
  end
end
```
(Espelha `LeadPolicy`. **Lição da 1a:** toda action nova precisa do método correspondente na policy que o `check_authorization` deriva, senão Pundit levanta e vira 500/CI vermelho.)

- [ ] **Step 6: Views (jbuilder)**

```ruby
# app/views/api/v1/accounts/lead_activities/index.json.jbuilder
json.payload do
  json.array! @activities, partial: 'lead_activity', as: :activity
end
```
```ruby
# app/views/api/v1/accounts/lead_activities/_lead_activity.json.jbuilder
json.id activity.id
json.kind activity.kind
json.from_value activity.from_value
json.to_value activity.to_value
json.author_name activity.user&.name
json.created_at activity.created_at
```

- [ ] **Step 7: Rodar (CI) e ver passar** — Esperado: PASS.

- [ ] **Step 8: Registrar no FORK-PONTOS + Commit** — registrar `config/routes.rb` (activities nested). 

```bash
git add app/controllers/api/v1/accounts/lead_activities_controller.rb app/policies/lead_activity_policy.rb \
        app/views/api/v1/accounts/lead_activities config/routes.rb \
        spec/controllers/api/v1/accounts/lead_activities_controller_spec.rb docs/FORK-PONTOS-DE-REGISTRO.md
git commit -m "feat: add read-only lead activities index endpoint"
```

---

### Task 4: Store + API client — buscar atividades

**Files:**
- Modify: `app/javascript/dashboard/api/leads.js`
- Modify: `app/javascript/dashboard/store/modules/leads.js`
- Test: `app/javascript/dashboard/store/modules/specs/leads/actions.spec.js`

**Interfaces:**
- Consumes: endpoint da Task 3.
- Produces: `LeadsAPI.getActivities(leadId)` → axios GET; store action `leads/fetchActivities(_ctx, leadId)` → resolve com o array `payload` (NÃO armazena no store — leitura sob demanda).

- [ ] **Step 1: Escrever o teste que falha**

```js
// em specs/leads/actions.spec.js
describe('leads/fetchActivities', () => {
  it('gets activities for a lead and returns the payload array', async () => {
    const activities = [{ id: 1, kind: 'created' }];
    axios.get.mockResolvedValue({ data: { payload: activities } });
    const result = await actions.fetchActivities({}, 7);
    expect(result).toEqual(activities);
  });
});
```
(Confirme o import de `actions` e o `global.axios = axios` + `vi.mock('axios')` no topo do arquivo, como nas specs existentes.)

- [ ] **Step 2: Rodar (CI) e ver falhar.**

- [ ] **Step 3: API method** — em `app/javascript/dashboard/api/leads.js`:
```js
getActivities(leadId) {
  return axios.get(`${this.url}/${leadId}/activities`);
}
```

- [ ] **Step 4: Store action** — em `store/modules/leads.js` (actions):
```js
async fetchActivities(_ctx, leadId) {
  const response = await LeadsAPI.getActivities(leadId);
  return response.data.payload;
},
```

- [ ] **Step 5: Rodar (CI) e ver passar.**

- [ ] **Step 6: Prettier + Commit**
```bash
npx prettier@3.3.3 --write app/javascript/dashboard/api/leads.js app/javascript/dashboard/store/modules/leads.js
git add app/javascript/dashboard/api/leads.js app/javascript/dashboard/store/modules/leads.js \
        app/javascript/dashboard/store/modules/specs/leads/actions.spec.js
git commit -m "feat: add fetchActivities store action"
```

---

### Task 5: `LeadHistory.vue` — renderiza a timeline

**Files:**
- Create: `app/javascript/dashboard/routes/dashboard/ramon/components/conversation/LeadHistory.vue`
- Create: `app/javascript/dashboard/routes/dashboard/ramon/components/conversation/specs/LeadHistory.spec.js`
- Modify: `app/javascript/dashboard/i18n/locale/en/ramon.json`
- Modify: `app/javascript/dashboard/i18n/locale/pt_BR/ramon.json`

**Interfaces:**
- Consumes: `leads/fetchActivities` (Task 4).
- **props:** `leadId: { type: [Number, String], required: true }`.
- Produces: componente que, ao montar / quando `leadId` muda, busca as atividades e as lista (mais recente no topo), cada linha com rótulo por `kind` + autor + data.

- [ ] **Step 1: Escrever o teste que falha**

```js
import { shallowMount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import LeadHistory from '../LeadHistory.vue';

const activities = [
  { id: 1, kind: 'created', from_value: null, to_value: 'instagram', author_name: null, created_at: '2026-06-01T10:00:00Z' },
  { id: 2, kind: 'stage_changed', from_value: 'Novo', to_value: 'Qualificação', author_name: 'Ana', created_at: '2026-06-02T10:00:00Z' },
];
const build = fetchSpy => createStore({
  modules: { leads: { namespaced: true, actions: { fetchActivities: fetchSpy } } },
});
const mountHistory = (fetchSpy = vi.fn().mockResolvedValue(activities)) =>
  shallowMount(LeadHistory, {
    props: { leadId: 7 },
    global: { plugins: [build(fetchSpy)], mocks: { $t: k => k } },
  });

it('fetches activities on mount', async () => {
  const fetchSpy = vi.fn().mockResolvedValue(activities);
  mountHistory(fetchSpy);
  await flushPromises();
  expect(fetchSpy).toHaveBeenCalledWith(expect.anything(), 7);
});

it('renders one row per activity, most recent first', async () => {
  const wrapper = mountHistory();
  await flushPromises();
  const rows = wrapper.findAll('[data-testid="activity-row"]');
  expect(rows).toHaveLength(2);
  expect(rows[0].text()).toContain('Qualificação'); // ordem invertida = mais recente no topo
});
```

- [ ] **Step 2: Rodar (CI) e ver falhar.**

- [ ] **Step 3: Implementar `LeadHistory.vue`**

```vue
<script setup>
import { ref, watch, computed } from 'vue';
import { useStore } from 'dashboard/composables/store';

const props = defineProps({
  leadId: { type: [Number, String], required: true },
});
const store = useStore();
const activities = ref([]);

const load = async () => {
  activities.value = await store.dispatch('leads/fetchActivities', Number(props.leadId));
};
watch(() => props.leadId, load, { immediate: true });

// mais recente no topo
const ordered = computed(() => [...activities.value].reverse());

const labelKey = kind => `RAMON.LEAD_PANEL.HISTORY.KIND.${kind.toUpperCase()}`;
</script>

<template>
  <div class="flex flex-col gap-3 p-1">
    <div
      v-for="activity in ordered"
      :key="activity.id"
      data-testid="activity-row"
      class="flex flex-col gap-0.5 border-l-2 pl-3"
    >
      <span class="text-sm">
        <strong v-if="activity.author_name">{{ activity.author_name }}</strong>
        <span v-else>{{ $t('RAMON.LEAD_PANEL.HISTORY.SYSTEM') }}</span>
        · {{ $t(labelKey(activity.kind)) }}
        <template v-if="activity.to_value"> → {{ activity.to_value }}</template>
      </span>
      <span class="text-xs opacity-60">{{ activity.created_at }}</span>
    </div>
  </div>
</template>
```

Notas: confira o composable real (`useStore` de `dashboard/composables/store`), como no `LeadConversationPanel`. Formatação de data amigável ("há 2 dias") pode reusar um helper de tempo do fork se existir — se não achar rápido, deixar `created_at` cru (calibrar depois); NÃO inventar dependência.

- [ ] **Step 4: i18n**

Em `en/ramon.json` e `pt_BR/ramon.json`, sob `RAMON.LEAD_PANEL`, adicionar:
```json
"HISTORY": {
  "SYSTEM": "Sistema",
  "KIND": {
    "CREATED": "criou o lead",
    "STAGE_CHANGED": "moveu de etapa",
    "SDR_CHANGED": "mudou o SDR",
    "CLOSER_CHANGED": "mudou o Closer",
    "PRIORITY_CHANGED": "mudou a prioridade",
    "VALUE_CHANGED": "mudou o valor"
  }
}
```
(en: SYSTEM "System"; CREATED "created the lead"; STAGE_CHANGED "moved stage"; SDR_CHANGED "changed the SDR"; CLOSER_CHANGED "changed the Closer"; PRIORITY_CHANGED "changed the priority"; VALUE_CHANGED "changed the value".) JSON válido, sob a raiz `RAMON` já registrada.

- [ ] **Step 5: Rodar (CI) e ver passar.**

- [ ] **Step 6: Prettier + Commit**
```bash
npx prettier@3.3.3 --write app/javascript/dashboard/routes/dashboard/ramon/components/conversation \
        app/javascript/dashboard/i18n/locale/en/ramon.json app/javascript/dashboard/i18n/locale/pt_BR/ramon.json
git add app/javascript/dashboard/routes/dashboard/ramon/components/conversation/LeadHistory.vue \
        app/javascript/dashboard/routes/dashboard/ramon/components/conversation/specs/LeadHistory.spec.js \
        app/javascript/dashboard/i18n/locale/en/ramon.json app/javascript/dashboard/i18n/locale/pt_BR/ramon.json
git commit -m "feat: add LeadHistory timeline component"
```

---

### Task 6: Aba "Histórico" no `LeadConversationPanel`

**Files:**
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/components/conversation/LeadConversationPanel.vue`
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/components/conversation/specs/LeadConversationPanel.spec.js`
- Modify: `app/javascript/dashboard/i18n/locale/en/ramon.json`
- Modify: `app/javascript/dashboard/i18n/locale/pt_BR/ramon.json`

**Interfaces:**
- Consumes: `LeadHistory.vue` (Task 5).
- Produces: segunda aba "Histórico" que renderiza `<LeadHistory :lead-id="lead.id" />` quando ativa.

- [ ] **Step 1: Atualizar o spec (falha)**

Adicionar ao `LeadConversationPanel.spec.js` (stub de LeadHistory + LeadFields):
```js
it('switches to the Histórico tab and renders LeadHistory', async () => {
  const wrapper = mountPanel(); // helper existente; adicionar stub LeadHistory:true
  await flushPromises();
  await wrapper.find('[data-testid="tab-historico"]').trigger('click');
  expect(wrapper.findComponent({ name: 'LeadHistory' }).exists()).toBe(true);
});
```
(Adicionar `LeadHistory: true` aos `stubs` do helper `mountPanel` e `defineOptions({ name: 'LeadHistory' })` no componente da Task 5 — inclua esse `defineOptions` num ajuste da Task 5 se ainda não houver; aqui assuma que existe.)

- [ ] **Step 2: Rodar (CI) e ver falhar.**

- [ ] **Step 3: Editar o `LeadConversationPanel.vue`**

Importar `LeadHistory` (após os imports existentes):
```js
import LeadHistory from 'dashboard/routes/dashboard/ramon/components/conversation/LeadHistory.vue';
```
No tab bar, adicionar o botão da aba Histórico ANTES do botão `ml-auto` de descartar:
```html
<button
  :class="{ 'font-semibold': activeTab === 'historico' }"
  data-testid="tab-historico"
  @click="activeTab = 'historico'"
>
  {{ $t('RAMON.LEAD_PANEL.TABS.HISTORY') }}
</button>
```
Na região de conteúdo (`v-if="lead"`), envolver o Resumo atual em `v-if="activeTab === 'resumo'"` e adicionar o painel do Histórico:
```html
<div v-if="lead" class="flex-1 overflow-y-auto p-3">
  <template v-if="activeTab === 'resumo'">
    <!-- ConversationAction/MacrosList/ResolveAction + LeadFields (como está hoje) -->
  </template>
  <LeadHistory v-else-if="activeTab === 'historico'" :lead-id="lead.id" />
</div>
```

- [ ] **Step 4: i18n** — adicionar `RAMON.LEAD_PANEL.TABS.HISTORY` = "Histórico" (pt) / "History" (en) nos dois `ramon.json`.

- [ ] **Step 5: Rodar (CI) e ver passar.**

- [ ] **Step 6: Prettier + Commit**
```bash
npx prettier@3.3.3 --write app/javascript/dashboard/routes/dashboard/ramon/components/conversation \
        app/javascript/dashboard/i18n/locale/en/ramon.json app/javascript/dashboard/i18n/locale/pt_BR/ramon.json
git add app/javascript/dashboard/routes/dashboard/ramon/components/conversation/LeadConversationPanel.vue \
        app/javascript/dashboard/routes/dashboard/ramon/components/conversation/specs/LeadConversationPanel.spec.js \
        app/javascript/dashboard/i18n/locale/en/ramon.json app/javascript/dashboard/i18n/locale/pt_BR/ramon.json
git commit -m "feat: add Histórico tab to lead conversation panel"
```

---

### Task 7: Backfill — semear `created` para leads existentes

**Files:**
- Create: `db/migrate/<timestamp>_backfill_lead_created_activities.rb`

**Interfaces:**
- Consumes: `LeadActivity` (Task 1).
- Produces: para cada `Lead` sem atividade `created`, cria uma `LeadActivity` `kind:'created'` com `created_at = lead.created_at`, `user: nil`.

- [ ] **Step 1: Escrever a migration de dados**

```ruby
# db/migrate/<timestamp>_backfill_lead_created_activities.rb
class BackfillLeadCreatedActivities < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def up
    Lead.find_each do |lead|
      next if LeadActivity.exists?(lead_id: lead.id, kind: 'created')

      LeadActivity.create!(account_id: lead.account_id, lead_id: lead.id,
                           kind: 'created', to_value: lead.source, created_at: lead.created_at)
    end
  end

  def down
    LeadActivity.where(kind: 'created').delete_all
  end
end
```

Notas: idempotente (`next if exists?`). Se `LeadActivity.create!` disparar `Rails/SkipsModelValidations`? Não — é `create!` (valida). `delete_all` no `down` pode disparar o cop → `# rubocop:disable Rails/SkipsModelValidations` na linha do down. Semear só `created` (não reconstrói histórico de etapas passado — inexistente). Explícito no spec/design.

- [ ] **Step 2: (CI) a migration roda no `db:schema:load`? Não — backfill é migration de dados**, não altera schema. O CI carrega schema via `db:schema:load` e NÃO roda migrations → esta migration de dados **não roda no CI** e não afeta `schema.rb` (só a linha de versão). Confirmar que a única mudança em `schema.rb` será a versão (o controller regenera). Sem spec dedicado (é one-shot de deploy).

- [ ] **Step 3: Commit**
```bash
git add db/migrate
git commit -m "feat: backfill created activity for existing leads"
```

---

### Task 8: schema regen, PR, CI, deploy (com migração), smoke

**Files:** nenhum de app — fecha a fatia.

- [ ] **Step 1: Regenerar `db/schema.rb` (controller, na VPS — scratch DB)**

Como não há Ruby local, o controller regenera o schema num banco descartável na VPS (padrão 2A/2B/2C): subir um container com `POSTGRES_DATABASE=ramon_schema_scratchN` + `DISABLE_DATABASE_ENVIRONMENT_CHECK=1`, rodar `db:create db:schema:load db:migrate db:schema:dump`, copiar o `db/schema.rb` regenerado (diff aditivo: nova versão + tabela `lead_activities`), produção intacta, scratch dropado. Commitar `db/schema.rb`. **Obter o comando exato com o Eduardo/estado da VPS** (a imagem é slim, usar `sh`). Commit: `chore: regenerate schema.rb for lead_activities`.

- [ ] **Step 2: Push + PR**
```bash
git push -u origin feat/fatia-1b-i-timeline-atividades
gh pr create --base ramon --title "feat: timeline de atividades do lead (aba Histórico)" \
  --body "Fatia 1b-i: tabela lead_activities + captura por callback (com autor) + API read-only + aba Histórico no painel do lead. Tem migração (db:migrate no deploy)."
```

- [ ] **Step 3: CI `run_foss_spec` verde** — corrigir rubocop/eslint/prettier se apontar (ver Global Constraints); relembrar a lição da 1a (policy nova) e a `vue/define-macros-order`.

- [ ] **Step 4: Merge (OK do Eduardo).**

- [ ] **Step 5: Deploy na VPS (OK explícito do Eduardo) — COM migração**

Diferente da 1a: esta fatia TEM migração. Após build GHCR verde: `docker compose pull chatwoot-web chatwoot-worker` + rodar as migrations (`docker compose --profile init run --rm chatwoot-init` OU `db:chatwoot_prepare`, conforme o padrão do compose da VPS — **lição da 1a: a imagem pode subir antes das migrations rodarem; sempre rodar o init + restart**) + `docker compose up -d chatwoot-web chatwoot-worker` + verificar no banco que `lead_activities` existe. Smoke: abrir uma conversa → aba Histórico → ver "criou o lead" + mover a etapa e ver a linha nova com o autor.

---

## Self-Review

**Spec coverage (contra `2026-07-01-ramon-hub-fatia-1b-painel-lead-historico-design.md`, parte 1b-i):**
- `lead_activities` (tabela + model) → Task 1. ✅
- Captura de created + stage/sdr/closer/priority/value com autor → Task 2. ✅
- Autor = Current.user; sistema = nil → Task 2 (guard implícito: `user: Current.user`). ✅
- API read-only listar atividades → Task 3. ✅
- Store fetch → Task 4. ✅
- Aba Histórico + timeline intercalando (só atividades nesta parte; notas são 1b-ii) → Tasks 5-6. ✅
- Backfill `created` p/ timeline não nascer vazia → Task 7. ✅
- Migração/deploy com db:migrate + schema regen pelo controller → Task 8. ✅
- **Notas discretas → NÃO neste plano** (é o 1b-ii). Documentado no cabeçalho e no design. ✅

**Placeholder scan:** sem TBD/TODO; cada passo de código tem código. Pontos "confirme no código real" (composable de store, superclasse do controller, versão do `ActiveRecord::Migration`, helper de data) são verificações que o executor faz lendo o fork.

**Type consistency:** `LeadActivity(kind, from_value, to_value, user, account, lead)`; `record_change(attribute, kind)`; `fetchActivities(_ctx, leadId)` → `payload`; `getActivities(leadId)`; prop `leadId` em LeadHistory; evento/tab `historico`; i18n `RAMON.LEAD_PANEL.HISTORY.KIND.*` — consistentes entre Tasks 1→2→3→4→5→6.

**Risco aberto (não bloqueia):** o helper de data amigável (Task 5) — se não houver um trivial no fork, timeline mostra data crua; calibrar depois. E `record_change` pode gerar múltiplas linhas se vários campos mudam no mesmo update (esperado; calibrar agrupamento depois se incomodar).
