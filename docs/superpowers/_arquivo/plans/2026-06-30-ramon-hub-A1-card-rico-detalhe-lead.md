# A1 — Card rico + gaveta de detalhe do Lead — Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enriquecer o card do funil de leads e adicionar uma gaveta lateral de detalhe (drawer) onde o Eduardo vê/edita o lead sem sair do board — editar a etapa na gaveta reaproveita o espelho `fase-*` da 2C de graça.

**Architecture:** Três colunas nativas novas em `leads` (`value`/`source`/`notes`) e uma em `lead_stages` (`color`). O serializer `_lead` passa a **desnormalizar** nomes (etapa/benefício/prioridade/SDR/closer/contato) para o front não cruzar listas, e `push_event_data` carrega os mesmos campos para o realtime da 2B manter o card rico ao vivo. No front, o card vira clicável (emite `open-lead`) e abre um `LeadDrawer.vue` que salva **por campo (on-blur/on-change)** via `leads/update`. O lead selecionado vive no store Vuex (`leads.selectedId`), fonte única compartilhada pelos dois mundos (Funil + KanbanView).

**Tech Stack:** Rails 7.1 (jbuilder, RSpec, FactoryBot), Vue 3 `<script setup>` + Vuex (vitest, @vue/test-utils), Tailwind. Fork `ramon-hub` do Chatwoot v4.15.1, branch `ramon`.

## Global Constraints

- **Sem ambiente local de teste:** a máquina não tem Ruby/pnpm/Postgres. Verificação real = **feature branch → PR → CI** (`run_foss_spec`: rspec + vitest + rubocop + eslint). Só **prettier** roda local (`npx prettier@3.3.3`). Escreva o teste primeiro (TDD), mas a execução do teste acontece no CI.
- **CI carrega o schema via `db:schema:load`** (NÃO roda migrations). Logo, `db/schema.rb` PRECISA conter as colunas novas antes do CI rodar → regenerado via **scratch DB na VPS** (Task 11), commitado no mesmo PR.
- **Semear em toda conta polui specs nativos** (lição 2C): nada de criar Labels/registros globais novos no `after_create`. As colunas desta fatia são **aditivas** e não tocam enumerações globais — baixo risco. Não adicionar seed que crie linhas em tabelas que specs nativos enumeram.
- **`value` é dinheiro:** serializar como número e formatar no front com `Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' })`. Nunca usar float-math no JS pra dinheiro.
- **Salvamento da gaveta = por campo** (decisão do Eduardo, 30/06): texto salva no `@blur` se mudou; select salva no `@change`. Sem botão "Salvar".
- **Regra de aprovação:** push/merge-na-origin/deploy exigem OK explícito do Eduardo. O auto-classifier do deploy bloqueia `db:migrate` em prod sem aprovação.
- **Branch:** trabalhar em `feat/ramon-hub-a1-card-drawer` a partir de `ramon`. Commits conventional (`feat:`/`test:`/`chore:`). Rodar `npx prettier@3.3.3 --write` em todo arquivo `app/javascript/dashboard/routes/dashboard/ramon/` e store/`ramon` tocado antes de commitar (o build GHCR não roda eslint; o CI roda).
- **i18n:** chaves novas vão nos DOIS locales (`en` e `pt_BR`) em `ramon.json` (já registrado nos `index.js`).

---

### Task 1: Migração — colunas novas em `leads` e `lead_stages`

**Files:**
- Create: `db/migrate/20260630000005_add_a1_fields_to_leads_and_stages.rb`
- Test: `spec/models/lead_spec.rb` (adicionar um `it`), `spec/models/lead_stage_spec.rb` (adicionar um `it`)

**Interfaces:**
- Produces: colunas `leads.value` (decimal 12,2, null), `leads.source` (string, null), `leads.notes` (text, null), `lead_stages.color` (string, null). Consumidas por Tasks 2–6, 8–10.

- [ ] **Step 1: Escrever os testes (falham até o schema regenerado)**

Em `spec/models/lead_spec.rb`, dentro do `RSpec.describe Lead do`, adicionar:

```ruby
  it 'expõe as colunas A1 (value, source, notes)' do
    expect(Lead.column_names).to include('value', 'source', 'notes')
  end
```

Em `spec/models/lead_stage_spec.rb`, dentro do `RSpec.describe LeadStage do`, adicionar:

```ruby
  it 'expõe a coluna color' do
    expect(LeadStage.column_names).to include('color')
  end
```

- [ ] **Step 2: Verificar a falha (via CI)**

Local indisponível (sem Ruby). Esses testes falham até o schema conter as colunas. Serão verdes no CI após o schema regenerado (Task 11). Não há comando local.

- [ ] **Step 3: Escrever a migração**

`db/migrate/20260630000005_add_a1_fields_to_leads_and_stages.rb`:

```ruby
class AddA1FieldsToLeadsAndStages < ActiveRecord::Migration[7.1]
  def change
    add_column :leads, :value, :decimal, precision: 12, scale: 2, null: true
    add_column :leads, :source, :string, null: true
    add_column :leads, :notes, :text, null: true
    add_column :lead_stages, :color, :string, null: true
  end
end
```

- [ ] **Step 4: Verificar os testes (via CI / Task 11)**

Verde no CI depois do schema regenerado. Sem run local.

- [ ] **Step 5: Commit**

```bash
git add db/migrate/20260630000005_add_a1_fields_to_leads_and_stages.rb spec/models/lead_spec.rb spec/models/lead_stage_spec.rb
git commit -m "feat: migração A1 (leads value/source/notes + lead_stages color)"
```

---

### Task 2: Seed grava `color` da etapa (+ backfill idempotente)

**Files:**
- Modify: `app/services/leads/seed_default_config_service.rb` (`seed_stages`, ~linhas 42-52)
- Test: `spec/services/leads/seed_default_config_service_spec.rb` (criar se não existir; senão adicionar `it`)

**Interfaces:**
- Consumes: `lead_stages.color` (Task 1), constante `STAGES` (já tem `:color`).
- Produces: toda etapa semeada tem `color` = cor do `STAGES`. Re-rodar `perform` faz backfill (idempotente). `lead_config` (Task 4) e o card (Task 8) leem essa cor.

- [ ] **Step 1: Escrever o teste**

Conferir se existe `spec/services/leads/seed_default_config_service_spec.rb`. Se não, criar:

```ruby
require 'rails_helper'

RSpec.describe Leads::SeedDefaultConfigService do
  let(:account) { create(:account) }

  it 'grava a cor de cada etapa a partir de STAGES' do
    described_class.new(account).perform
    novo = account.lead_stages.find_by(name: 'Novo')
    fechado = account.lead_stages.find_by(name: 'Fechado')
    expect(novo.color).to eq('#6b7280')
    expect(fechado.color).to eq('#22c55e')
  end

  it 'faz backfill da cor ao re-rodar quando a etapa está sem cor' do
    described_class.new(account).perform
    novo = account.lead_stages.find_by(name: 'Novo')
    novo.update_column(:color, nil)
    described_class.new(account).perform
    expect(novo.reload.color).to eq('#6b7280')
  end
end
```

> Nota: `create(:account)` já dispara o seed via `after_create` (Fase 2A). Os testes re-rodam `perform` explicitamente — é idempotente.

- [ ] **Step 2: Verificar a falha (via CI)**

Sem run local. Falha até `seed_stages` gravar `color`.

- [ ] **Step 3: Implementar — `seed_stages` grava/atualiza `color`**

Em `app/services/leads/seed_default_config_service.rb`, trocar o método `seed_stages` por:

```ruby
  def seed_stages
    STAGES.each_with_index do |attrs, i|
      stage = @account.lead_stages.find_or_create_by!(name: attrs[:name]) do |s|
        s.position = i
        s.is_won = attrs[:is_won]
        s.is_lost = attrs[:is_lost]
        s.label = attrs[:label]
        s.color = attrs[:color]
      end
      stage.update!(label: attrs[:label]) if stage.label != attrs[:label]
      stage.update!(color: attrs[:color]) if stage.color != attrs[:color]
    end
  end
```

- [ ] **Step 4: Verificar os testes (via CI)**

Verde no CI.

- [ ] **Step 5: Commit**

```bash
git add app/services/leads/seed_default_config_service.rb spec/services/leads/seed_default_config_service_spec.rb
git commit -m "feat: seed grava color da etapa (idempotente, com backfill)"
```

---

### Task 3: Serializer `_lead` — campos novos + nomes desnormalizados + contato

**Files:**
- Modify: `app/views/api/v1/accounts/leads/_lead.json.jbuilder`
- Test: `spec/controllers/api/v1/accounts/leads_controller_spec.rb` (adicionar `it`)

**Interfaces:**
- Consumes: colunas Task 1, associações `lead.lead_stage` (`name`/`color`), `lead.benefit_type.name`, `lead.lead_priority.name`, `lead.sdr.name`, `lead.closer.name`, `lead.contact` (`name`/`phone_number`/`email`).
- Produces: payload do lead com `value`, `source`, `notes`, `stage_name`, `stage_color`, `benefit_type_name`, `lead_priority_name`, `sdr_name`, `closer_name`, `contact_name`, `contact_phone`, `contact_email`. Consumido pelo card (Task 8) e pela gaveta (Task 9).

- [ ] **Step 1: Escrever o teste**

Em `spec/controllers/api/v1/accounts/leads_controller_spec.rb`, adicionar:

```ruby
  it 'serializa value/source/notes + nomes desnormalizados + contato' do
    contact = create(:contact, account: account, name: 'Cliente X',
                               phone_number: '+5547999990000', email: 'x@cli.com')
    bt = account.benefit_types.find_by(name: 'Auxílio-acidente')
    lead = create(:lead, account: account, lead_stage: novo, contact: contact,
                         benefit_type: bt, value: 12_000.50, source: 'Meta Ads',
                         notes: 'ligar à tarde')
    get "/api/v1/accounts/#{account.id}/leads/#{lead.id}",
        headers: admin.create_new_auth_token, as: :json
    body = response.parsed_body
    expect(body['value'].to_f).to eq(12_000.50)
    expect(body['source']).to eq('Meta Ads')
    expect(body['notes']).to eq('ligar à tarde')
    expect(body['stage_name']).to eq('Novo')
    expect(body['stage_color']).to eq('#6b7280')
    expect(body['benefit_type_name']).to eq('Auxílio-acidente')
    expect(body['contact_name']).to eq('Cliente X')
    expect(body['contact_phone']).to eq('+5547999990000')
    expect(body['contact_email']).to eq('x@cli.com')
  end
```

- [ ] **Step 2: Verificar a falha (via CI)**

Sem run local. Falha até o serializer expor os campos.

- [ ] **Step 3: Implementar — estender `_lead.json.jbuilder`**

Substituir o conteúdo de `app/views/api/v1/accounts/leads/_lead.json.jbuilder` por:

```ruby
json.id lead.id
json.name lead.name
json.lead_stage_id lead.lead_stage_id
json.benefit_type_id lead.benefit_type_id
json.lead_priority_id lead.lead_priority_id
json.contact_id lead.contact_id
json.conversation_id lead.conversation_id
json.sdr_id lead.sdr_id
json.closer_id lead.closer_id
json.position lead.position
json.lost_reason lead.lost_reason
json.custom_attributes lead.custom_attributes

json.value lead.value
json.source lead.source
json.notes lead.notes

json.stage_name lead.lead_stage&.name
json.stage_color lead.lead_stage&.color
json.benefit_type_name lead.benefit_type&.name
json.lead_priority_name lead.lead_priority&.name
json.sdr_name lead.sdr&.name
json.closer_name lead.closer&.name

json.contact_name lead.contact&.name
json.contact_phone lead.contact&.phone_number
json.contact_email lead.contact&.email
```

- [ ] **Step 4: Verificar os testes (via CI)**

Verde no CI.

- [ ] **Step 5: Commit**

```bash
git add app/views/api/v1/accounts/leads/_lead.json.jbuilder spec/controllers/api/v1/accounts/leads_controller_spec.rb
git commit -m "feat: serializer _lead expõe value/source/notes + nomes desnormalizados + contato"
```

---

### Task 4: `lead_config#show` — expõe `color` por etapa

**Files:**
- Modify: `app/views/api/v1/accounts/lead_config/show.json.jbuilder` (bloco `stages`, ~linhas 1-9)
- Test: `spec/controllers/api/v1/accounts/lead_config_controller_spec.rb` (adicionar `it`)

**Interfaces:**
- Consumes: `lead_stages.color` (Tasks 1-2).
- Produces: cada `stage` do `lead_config` tem `color`. Consumido pela gaveta (select de etapa) e pelo store `leadConfig`.

- [ ] **Step 1: Escrever o teste**

Em `spec/controllers/api/v1/accounts/lead_config_controller_spec.rb`, adicionar:

```ruby
  it 'expõe a cor de cada etapa' do
    get "/api/v1/accounts/#{account.id}/lead_config",
        headers: admin.create_new_auth_token, as: :json
    novo = response.parsed_body['stages'].find { |s| s['name'] == 'Novo' }
    expect(novo['color']).to eq('#6b7280')
  end
```

- [ ] **Step 2: Verificar a falha (via CI)**

Sem run local.

- [ ] **Step 3: Implementar — adicionar `color` no bloco de stage**

Em `app/views/api/v1/accounts/lead_config/show.json.jbuilder`, dentro do `json.array! @stages do |stage|`, adicionar a linha `json.color stage.color` (logo após `json.name stage.name`):

```ruby
json.stages do
  json.array! @stages do |stage|
    json.id stage.id
    json.name stage.name
    json.color stage.color
    json.position stage.position
    json.is_won stage.is_won
    json.is_lost stage.is_lost
  end
end
```

- [ ] **Step 4: Verificar os testes (via CI)**

Verde no CI.

- [ ] **Step 5: Commit**

```bash
git add app/views/api/v1/accounts/lead_config/show.json.jbuilder spec/controllers/api/v1/accounts/lead_config_controller_spec.rb
git commit -m "feat: lead_config expõe color por etapa"
```

---

### Task 5: `Lead#push_event_data` — card rico no realtime

**Files:**
- Modify: `app/models/lead.rb` (método `push_event_data`, linhas 17-28)
- Test: `spec/models/lead_spec.rb` (adicionar `it`)

**Interfaces:**
- Consumes: colunas Task 1 + associações (como Task 3).
- Produces: `push_event_data` carrega `value`, `source`, `stage_color`, `stage_name`, `benefit_type_name`, `lead_priority_name`, `sdr_name`, `closer_name`, `contact_name`. Consumido pelo realtime 2B (`leads/upsert`) — garante que o card não "empobrece" após update ao vivo.

> **Por que estes campos e não `notes`/`contact_phone`/`contact_email`?** `push_event_data` alimenta o realtime, que é um **delta**. Os campos aqui são os que o CARD mostra (precisam existir mesmo num lead recém-criado em outra aba). Os campos só-da-gaveta (`notes`, telefone, e-mail) ficam de fora de propósito — o store faz **merge** (Task 7), então a gaveta aberta não os perde.

- [ ] **Step 1: Escrever o teste**

Em `spec/models/lead_spec.rb`, adicionar:

```ruby
  it 'push_event_data inclui os campos do card rico' do
    stage = account.lead_stages.find_by(name: 'Negociação')
    lead = create(:lead, account: account, lead_stage: stage, value: 5000, source: 'Indicação')
    data = lead.push_event_data
    expect(data).to include(
      value: lead.value, source: 'Indicação',
      stage_name: 'Negociação', stage_color: '#f59e0b'
    )
    expect(data.keys).to include(:benefit_type_name, :lead_priority_name, :sdr_name, :closer_name, :contact_name)
  end
```

- [ ] **Step 2: Verificar a falha (via CI)**

Sem run local.

- [ ] **Step 3: Implementar — estender `push_event_data`**

Em `app/models/lead.rb`, substituir o método `push_event_data` por:

```ruby
  def push_event_data
    {
      id: id,
      name: name,
      lead_stage_id: lead_stage_id,
      benefit_type_id: benefit_type_id,
      lead_priority_id: lead_priority_id,
      contact_id: contact_id,
      conversation_id: conversation_id,
      position: position,
      value: value,
      source: source,
      stage_name: lead_stage&.name,
      stage_color: lead_stage&.color,
      benefit_type_name: benefit_type&.name,
      lead_priority_name: lead_priority&.name,
      sdr_name: sdr&.name,
      closer_name: closer&.name,
      contact_name: contact&.name
    }
  end
```

- [ ] **Step 4: Verificar os testes (via CI)**

Verde no CI.

- [ ] **Step 5: Commit**

```bash
git add app/models/lead.rb spec/models/lead_spec.rb
git commit -m "feat: push_event_data carrega campos do card rico (realtime 2B)"
```

---

### Task 6: Controller — permitir `value`/`source`/`notes`

**Files:**
- Modify: `app/controllers/api/v1/accounts/leads_controller.rb` (`permitted_params`, linhas 31-35)
- Test: `spec/controllers/api/v1/accounts/leads_controller_spec.rb` (adicionar `it`)

**Interfaces:**
- Consumes: colunas Task 1.
- Produces: `update`/`create` aceitam `value`, `source`, `notes`. Mesma policy (admin/agent). Consumido pela gaveta (Task 9).

- [ ] **Step 1: Escrever o teste**

Em `spec/controllers/api/v1/accounts/leads_controller_spec.rb`, adicionar:

```ruby
  it 'update aceita value/source/notes' do
    lead = create(:lead, account: account, lead_stage: novo)
    patch "/api/v1/accounts/#{account.id}/leads/#{lead.id}",
          params: { value: 8500.25, source: 'Meta Ads', notes: 'cliente quente' },
          headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    lead.reload
    expect(lead.value).to eq(8500.25)
    expect(lead.source).to eq('Meta Ads')
    expect(lead.notes).to eq('cliente quente')
  end
```

- [ ] **Step 2: Verificar a falha (via CI)**

Sem run local. `update!` ignora os params não permitidos → valores não persistem.

- [ ] **Step 3: Implementar — estender `permitted_params`**

Em `app/controllers/api/v1/accounts/leads_controller.rb`, trocar `permitted_params` por:

```ruby
  def permitted_params
    params.permit(:name, :lead_stage_id, :benefit_type_id, :lead_priority_id,
                  :contact_id, :conversation_id, :sdr_id, :closer_id,
                  :position, :lost_reason, :value, :source, :notes)
  end
```

- [ ] **Step 4: Verificar os testes (via CI)**

Verde no CI.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/api/v1/accounts/leads_controller.rb spec/controllers/api/v1/accounts/leads_controller_spec.rb
git commit -m "feat: leads#update permite value/source/notes"
```

---

### Task 7: Store `leads` — realtime por merge + lead selecionado

**Files:**
- Modify: `app/javascript/dashboard/store/mutation-types.js` (bloco LEAD, linhas 124-129)
- Modify: `app/javascript/dashboard/store/modules/leads.js`
- Test: `app/javascript/dashboard/store/modules/specs/leads/actions.spec.js` (adicionar casos)
- Test: `app/javascript/dashboard/store/modules/specs/leads/mutations.spec.js` (criar)

**Interfaces:**
- Consumes: payload do realtime (`push_event_data`, Task 5).
- Produces:
  - mutation-types `MERGE_LEAD`, `SET_SELECTED_LEAD`.
  - action `upsert(lead)` → `MERGE_LEAD` (merge-or-create, NÃO substitui o registro inteiro).
  - action `select(id)` → `SET_SELECTED_LEAD`.
  - getter `getSelectedLead` → registro de `records` cujo `id === selectedId`, ou `null`.

> **Por que merge e não replace no realtime?** `setSingleRecord` (usado por `EDIT_LEAD`) substitui o objeto inteiro. O realtime traz só o subconjunto de `push_event_data` (sem `notes`/`contact_phone`/`contact_email`). Se substituísse, a gaveta aberta perderia esses campos a cada eco de update. `MERGE_LEAD` faz spread sobre o registro existente (mantém campos da gaveta) e, se o lead não existir ainda (criado em outra aba), insere — então `lead.created` via realtime continua aparecendo no board. `move`/`update` seguem em `EDIT_LEAD` (recebem o serializer completo).

- [ ] **Step 1: Escrever os testes**

Adicionar ao final do `describe('leads actions', ...)` em `actions.spec.js`:

```js
  it('upsert faz commit de MERGE_LEAD', () => {
    const commit = vi.fn();
    actions.upsert({ commit }, { id: 7, name: 'Live' });
    expect(commit).toHaveBeenCalledWith(types.MERGE_LEAD, { id: 7, name: 'Live' });
  });

  it('select faz commit de SET_SELECTED_LEAD', () => {
    const commit = vi.fn();
    actions.select({ commit }, 42);
    expect(commit).toHaveBeenCalledWith(types.SET_SELECTED_LEAD, 42);
  });
```

Criar `app/javascript/dashboard/store/modules/specs/leads/mutations.spec.js`:

```js
import { mutations } from '../../leads';
import types from '../../../mutation-types';

describe('leads mutations', () => {
  it('MERGE_LEAD funde sobre o registro existente sem dropar campos', () => {
    const state = { records: [{ id: 1, name: 'Ana', notes: 'manter' }] };
    mutations[types.MERGE_LEAD](state, { id: 1, name: 'Ana Maria', value: 100 });
    expect(state.records[0]).toEqual({
      id: 1,
      name: 'Ana Maria',
      notes: 'manter',
      value: 100,
    });
  });

  it('MERGE_LEAD insere quando o lead não existe', () => {
    const state = { records: [] };
    mutations[types.MERGE_LEAD](state, { id: 9, name: 'Novo' });
    expect(state.records).toHaveLength(1);
    expect(state.records[0].id).toBe(9);
  });

  it('SET_SELECTED_LEAD guarda o id selecionado', () => {
    const state = { selectedId: null };
    mutations[types.SET_SELECTED_LEAD](state, 5);
    expect(state.selectedId).toBe(5);
  });
});
```

- [ ] **Step 2: Verificar a falha (via CI)**

Sem run local (vitest só no CI). Falham até as mutations/actions existirem.

- [ ] **Step 3: Adicionar os mutation-types**

Em `app/javascript/dashboard/store/mutation-types.js`, no bloco LEAD (após `SET_LEAD_CONFIG`), adicionar:

```js
  MERGE_LEAD: 'MERGE_LEAD',
  SET_SELECTED_LEAD: 'SET_SELECTED_LEAD',
```

- [ ] **Step 4: Implementar no `leads.js`**

`state` ganha `selectedId`:

```js
export const state = {
  records: [],
  selectedId: null,
  uiFlags: {
    isFetching: false,
    isCreating: false,
    isUpdating: false,
    isDeleting: false,
  },
};
```

`getters` ganha `getSelectedLead`:

```js
  getSelectedLead(_state) {
    return _state.records.find(lead => lead.id === _state.selectedId) || null;
  },
```

`actions`: trocar `upsert` e adicionar `select`:

```js
  upsert: ({ commit }, lead) => {
    commit(types.MERGE_LEAD, lead);
  },
  select: ({ commit }, id) => {
    commit(types.SET_SELECTED_LEAD, id);
  },
```

`mutations`: adicionar `MERGE_LEAD` e `SET_SELECTED_LEAD`:

```js
  [types.MERGE_LEAD](_state, data) {
    const index = _state.records.findIndex(record => record.id === data.id);
    if (index > -1) {
      _state.records[index] = { ..._state.records[index], ...data };
    } else {
      _state.records.push(data);
    }
  },
  [types.SET_SELECTED_LEAD](_state, id) {
    _state.selectedId = id;
  },
```

- [ ] **Step 5: Verificar os testes (via CI)** + prettier local

```bash
npx prettier@3.3.3 --write app/javascript/dashboard/store/modules/leads.js app/javascript/dashboard/store/modules/specs/leads/
```

- [ ] **Step 6: Commit**

```bash
git add app/javascript/dashboard/store/mutation-types.js app/javascript/dashboard/store/modules/leads.js app/javascript/dashboard/store/modules/specs/leads/
git commit -m "feat: store leads — realtime por merge (MERGE_LEAD) + lead selecionado"
```

---

### Task 8: `LeadCard.vue` — card rico (+ remove prop-drilling)

**Files:**
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/components/kanban/LeadCard.vue`
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/components/kanban/KanbanColumn.vue`
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/components/kanban/KanbanBoard.vue`
- Test: `app/javascript/dashboard/routes/dashboard/ramon/components/kanban/specs/LeadCard.spec.js` (criar)
- Test: `app/javascript/dashboard/routes/dashboard/ramon/components/kanban/specs/KanbanColumn.spec.js` (atualizar)

**Interfaces:**
- Consumes: campos desnormalizados do serializer/realtime (`stage_color`, `stage_name`, `benefit_type_name`, `lead_priority_name`, `value`, `sdr_name`/`closer_name`, `conversation_id`).
- Produces: `LeadCard` emite `open-lead(lead)` ao clicar no corpo e `open-conversation(id)` no botão (`@click.stop`). `KanbanColumn` re-emite `open-lead`. Não recebe mais `benefitTypes`/`priorities` (o serializer já desnormaliza — DRY).

> **Simplificação (DRY/YAGNI):** com os nomes desnormalizados no serializer, o card não precisa mais cruzar as listas `benefitTypes`/`priorities`. Removemos esse prop-drilling de `LeadCard` → `KanbanColumn` → `KanbanBoard`.

- [ ] **Step 1: Escrever o teste do `LeadCard`**

Criar `app/javascript/dashboard/routes/dashboard/ramon/components/kanban/specs/LeadCard.spec.js`:

```js
import { shallowMount } from '@vue/test-utils';
import LeadCard from '../LeadCard.vue';

const lead = {
  id: 10,
  name: 'João',
  conversation_id: 99,
  stage_name: 'Negociação',
  stage_color: '#f59e0b',
  benefit_type_name: 'Auxílio-acidente',
  lead_priority_name: 'Alta',
  value: '12000.50',
  closer_name: 'Eduardo Schlata',
};

const mountCard = (props = {}) =>
  shallowMount(LeadCard, {
    props: { lead, ...props },
    global: { mocks: { $t: k => k } },
  });

describe('LeadCard.vue', () => {
  it('renderiza nome, benefício e valor formatado em BRL', () => {
    const wrapper = mountCard();
    expect(wrapper.text()).toContain('João');
    expect(wrapper.text()).toContain('Auxílio-acidente');
    expect(wrapper.text()).toContain('12.000,50');
  });

  it('aplica a cor da etapa no chip', () => {
    const wrapper = mountCard();
    const chip = wrapper.find('[data-testid="stage-chip"]');
    expect(chip.attributes('style')).toContain('rgb(245, 158, 11)');
  });

  it('emite open-lead ao clicar no corpo', async () => {
    const wrapper = mountCard();
    await wrapper.find('[data-testid="lead-card-body"]').trigger('click');
    expect(wrapper.emitted('open-lead')[0][0]).toEqual(lead);
  });

  it('emite open-conversation sem abrir a gaveta (click.stop)', async () => {
    const wrapper = mountCard();
    await wrapper.find('[data-testid="open-conversation"]').trigger('click');
    expect(wrapper.emitted('open-conversation')[0][0]).toBe(99);
    expect(wrapper.emitted('open-lead')).toBeFalsy();
  });
});
```

- [ ] **Step 2: Verificar a falha (via CI)**

Sem run local.

- [ ] **Step 3: Reescrever `LeadCard.vue`**

```vue
<script setup>
import { computed } from 'vue';

const props = defineProps({
  lead: { type: Object, required: true },
});
const emit = defineEmits(['open-conversation', 'open-lead']);

const formattedValue = computed(() => {
  const v = props.lead.value;
  if (v === null || v === undefined || v === '') return null;
  return new Intl.NumberFormat('pt-BR', {
    style: 'currency',
    currency: 'BRL',
  }).format(Number(v));
});

const ownerName = computed(
  () => props.lead.closer_name || props.lead.sdr_name || null
);
const ownerInitials = computed(() => {
  if (!ownerName.value) return null;
  return ownerName.value
    .trim()
    .split(/\s+/)
    .map(word => word[0])
    .slice(0, 2)
    .join('')
    .toUpperCase();
});
</script>

<template>
  <div
    class="p-3 mb-2 rounded-xl bg-n-solid-2 border border-n-weak cursor-pointer hover:border-n-iris-8"
  >
    <div class="flex items-start justify-between gap-2">
      <button
        data-testid="lead-card-body"
        class="flex-1 text-left"
        @click="emit('open-lead', lead)"
      >
        <p class="text-sm font-medium text-n-slate-12">{{ lead.name }}</p>
      </button>
      <button
        v-if="lead.conversation_id"
        data-testid="open-conversation"
        :title="$t('RAMON.FUNIL.OPEN_CONVERSATION')"
        class="text-n-slate-10 hover:text-n-iris-11"
        @click.stop="emit('open-conversation', lead.conversation_id)"
      >
        <span class="i-lucide-message-square size-4" />
      </button>
    </div>

    <div class="flex flex-wrap items-center gap-1.5 mt-2">
      <span
        v-if="lead.stage_name"
        data-testid="stage-chip"
        class="inline-block px-2 py-0.5 text-[11px] rounded-full text-white"
        :style="{ backgroundColor: lead.stage_color || '#71717a' }"
      >
        {{ lead.stage_name }}
      </span>
      <span
        v-if="lead.benefit_type_name"
        class="inline-block px-2 py-0.5 text-[11px] rounded-full bg-n-alpha-2 text-n-slate-11"
      >
        {{ lead.benefit_type_name }}
      </span>
    </div>

    <div class="flex items-center justify-between mt-2">
      <div class="flex items-center gap-2">
        <span
          v-if="lead.lead_priority_name"
          class="inline-flex items-center gap-1 px-2 py-0.5 text-[11px] rounded-full bg-n-iris-9 text-white"
        >
          <span class="i-lucide-flag size-3" />{{ lead.lead_priority_name }}
        </span>
        <span v-if="formattedValue" class="text-xs font-medium text-n-slate-12">
          {{ formattedValue }}
        </span>
      </div>
      <span
        v-if="ownerInitials"
        :title="ownerName"
        class="inline-flex items-center justify-center size-6 text-[10px] rounded-full bg-n-alpha-2 text-n-slate-11"
      >
        {{ ownerInitials }}
      </span>
    </div>
  </div>
</template>
```

- [ ] **Step 4: Atualizar `KanbanColumn.vue` — re-emitir `open-lead`, parar de passar props ao card**

No `<script setup>`, trocar a linha de props e emits:

```js
const props = defineProps({
  stage: { type: Object, required: true },
  leads: { type: Array, default: () => [] },
});
const emit = defineEmits(['move', 'open-conversation', 'open-lead']);
```

No template, o `<LeadCard>` vira:

```vue
      <template #item="{ element }">
        <LeadCard
          :lead="element"
          @open-conversation="id => emit('open-conversation', id)"
          @open-lead="lead => emit('open-lead', lead)"
        />
      </template>
```

- [ ] **Step 5: Atualizar `KanbanBoard.vue` — remover benefitTypes/priorities, re-emitir `open-lead`**

No `<script setup>`, remover os computeds `benefitTypes` e `priorities` (linhas 11-14) e adicionar `open-lead` aos emits:

```js
const emit = defineEmits(['new-lead', 'open-conversation', 'open-lead']);
```

(Manter `stages`, `leadsByStage`, `onMove`, `onMounted`.) No template, o `<KanbanColumn>` vira:

```vue
      <KanbanColumn
        v-for="stage in stages"
        :key="stage.id"
        :stage="stage"
        :leads="leadsByStage(stage.id)"
        @move="onMove"
        @open-conversation="id => emit('open-conversation', id)"
        @open-lead="lead => emit('open-lead', lead)"
      />
```

> A montagem da gaveta e o tratamento de `open-lead` vêm na Task 10. Aqui o `KanbanBoard` só **propaga** o evento.

- [ ] **Step 6: Atualizar `KanbanColumn.spec.js`**

Trocar o helper `mountColumn` (remover `benefitTypes`/`priorities`) e adicionar um teste de re-emit:

```js
const mountColumn = (props = {}) =>
  shallowMount(KanbanColumn, {
    props: { stage, leads, ...props },
  });
```

Adicionar dentro do `describe`:

```js
  it('re-emite open-lead vindo do LeadCard', () => {
    const wrapper = mountColumn();
    wrapper.findComponent({ name: 'LeadCard' }).vm.$emit('open-lead', { id: 10 });
    expect(wrapper.emitted('open-lead')[0][0]).toEqual({ id: 10 });
  });
```

> Se `findComponent({ name: 'LeadCard' })` não resolver no shallowMount, usar `findComponent(LeadCard)` com `import LeadCard from '../LeadCard.vue'` no topo do spec.

- [ ] **Step 7: Prettier + Commit**

```bash
npx prettier@3.3.3 --write app/javascript/dashboard/routes/dashboard/ramon/components/kanban/
git add app/javascript/dashboard/routes/dashboard/ramon/components/kanban/
git commit -m "feat: LeadCard rico (chip colorido/valor/dono, clique abre gaveta) + remove prop-drilling"
```

---

### Task 9: `LeadDrawer.vue` (novo) + i18n

**Files:**
- Create: `app/javascript/dashboard/routes/dashboard/ramon/components/kanban/LeadDrawer.vue`
- Modify: `app/javascript/dashboard/i18n/locale/pt_BR/ramon.json`
- Modify: `app/javascript/dashboard/i18n/locale/en/ramon.json`
- Test: `app/javascript/dashboard/routes/dashboard/ramon/components/kanban/specs/LeadDrawer.spec.js` (criar)

**Interfaces:**
- Consumes: getter `leads/getSelectedLead`, `leadConfig/getStages|getBenefitTypes|getPriorities`, `agents/getAgents`; actions `leads/update`, `leads/select`.
- Produces: painel lateral à direita. Editáveis (salvam por campo): nome · etapa · benefício · prioridade · SDR · closer · valor · origem · notas. Só-leitura: contato (nome/telefone/e-mail) + botão "Abrir conversa". Fecha por X/Esc/clique-fora → `leads/select(null)`. Emite `open-conversation(id)`.

> **Salvamento por campo:** cada campo mantém um `ref` local sincronizado do lead selecionado (via `watch`). Texto (`name`/`value`/`source`/`notes`) salva no `@blur` **se mudou**; select (`lead_stage_id`/`benefit_type_id`/`lead_priority_id`/`sdr_id`/`closer_id`) salva no `@change`. `value` vazio → envia `null`. Editar a etapa dispara o espelho `fase-*` (2C) no backend, de graça.

- [ ] **Step 1: Escrever o teste do `LeadDrawer`**

Criar `app/javascript/dashboard/routes/dashboard/ramon/components/kanban/specs/LeadDrawer.spec.js`:

```js
import { shallowMount } from '@vue/test-utils';
import { createStore } from 'vuex';
import LeadDrawer from '../LeadDrawer.vue';

const lead = {
  id: 10,
  name: 'João',
  lead_stage_id: 1,
  benefit_type_id: null,
  lead_priority_id: null,
  sdr_id: null,
  closer_id: null,
  value: '5000.00',
  source: 'Meta Ads',
  notes: 'nota',
  conversation_id: 77,
  contact_name: 'João Cliente',
  contact_phone: '+55479999',
  contact_email: 'j@cli.com',
};

const buildStore = (updateSpy, selectSpy) =>
  createStore({
    modules: {
      leads: {
        namespaced: true,
        getters: { getSelectedLead: () => lead },
        actions: { update: updateSpy, select: selectSpy },
      },
      leadConfig: {
        namespaced: true,
        getters: {
          getStages: () => [{ id: 1, name: 'Novo' }, { id: 2, name: 'Negociação' }],
          getBenefitTypes: () => [{ id: 3, name: 'Auxílio-acidente' }],
          getPriorities: () => [{ id: 4, name: 'Alta' }],
        },
      },
      agents: { namespaced: true, getters: { getAgents: () => [{ id: 8, name: 'Eduardo' }] } },
    },
  });

const mountDrawer = (updateSpy = vi.fn(), selectSpy = vi.fn()) =>
  shallowMount(LeadDrawer, {
    global: {
      plugins: [buildStore(updateSpy, selectSpy)],
      mocks: { $t: k => k },
    },
  });

describe('LeadDrawer.vue', () => {
  it('carrega o lead selecionado e mostra dados de contato (só leitura)', () => {
    const wrapper = mountDrawer();
    expect(wrapper.text()).toContain('João Cliente');
    expect(wrapper.text()).toContain('+55479999');
  });

  it('salva o nome no blur quando muda', async () => {
    const update = vi.fn();
    const wrapper = mountDrawer(update);
    const input = wrapper.find('[data-testid="field-name"]');
    await input.setValue('João Silva');
    await input.trigger('blur');
    expect(update).toHaveBeenCalledWith(expect.anything(), { id: 10, name: 'João Silva' });
  });

  it('NÃO salva no blur quando o valor não mudou', async () => {
    const update = vi.fn();
    const wrapper = mountDrawer(update);
    await wrapper.find('[data-testid="field-name"]').trigger('blur');
    expect(update).not.toHaveBeenCalled();
  });

  it('salva a etapa no change', async () => {
    const update = vi.fn();
    const wrapper = mountDrawer(update);
    const select = wrapper.find('[data-testid="field-stage"]');
    await select.setValue(2);
    expect(update).toHaveBeenCalledWith(expect.anything(), { id: 10, lead_stage_id: 2 });
  });

  it('fecha desselecionando o lead', async () => {
    const select = vi.fn();
    const wrapper = mountDrawer(vi.fn(), select);
    await wrapper.find('[data-testid="drawer-close"]').trigger('click');
    expect(select).toHaveBeenCalledWith(expect.anything(), null);
  });

  it('emite open-conversation', async () => {
    const wrapper = mountDrawer();
    await wrapper.find('[data-testid="drawer-open-conversation"]').trigger('click');
    expect(wrapper.emitted('open-conversation')[0][0]).toBe(77);
  });
});
```

- [ ] **Step 2: Verificar a falha (via CI)**

Sem run local.

- [ ] **Step 3: Criar `LeadDrawer.vue`**

```vue
<script setup>
import { ref, watch, computed } from 'vue';
import { useStore, useStoreGetters } from 'dashboard/composables/store';

const emit = defineEmits(['open-conversation']);
const store = useStore();
const getters = useStoreGetters();

const lead = computed(() => getters['leads/getSelectedLead'].value);
const stages = computed(() => getters['leadConfig/getStages'].value);
const benefitTypes = computed(() => getters['leadConfig/getBenefitTypes'].value);
const priorities = computed(() => getters['leadConfig/getPriorities'].value);
const agents = computed(() => getters['agents/getAgents'].value);

// refs locais editáveis, ressincronizados sempre que o lead selecionado muda
const name = ref('');
const value = ref('');
const source = ref('');
const notes = ref('');

watch(
  lead,
  l => {
    name.value = l?.name ?? '';
    value.value = l?.value ?? '';
    source.value = l?.source ?? '';
    notes.value = l?.notes ?? '';
  },
  { immediate: true }
);

const save = payload => {
  if (!lead.value) return;
  store.dispatch('leads/update', { id: lead.value.id, ...payload });
};

// texto: salva no blur só se mudou
const saveText = (key, refVal, original) => {
  const next = refVal.value === '' ? null : refVal.value;
  const prev = original ?? null;
  if (next === prev) return;
  save({ [key]: next });
};

const saveName = () => saveText('name', name, lead.value?.name);
const saveSource = () => saveText('source', source, lead.value?.source);
const saveNotes = () => saveText('notes', notes, lead.value?.notes);
const saveValue = () => {
  const next = value.value === '' ? null : Number(value.value);
  const prev = lead.value?.value == null ? null : Number(lead.value.value);
  if (next === prev) return;
  save({ value: next });
};

// select: salva direto no change
const saveSelect = (key, val) => save({ [key]: val === '' ? null : val });

const close = () => store.dispatch('leads/select', null);

const onKeydown = e => {
  if (e.key === 'Escape') close();
};
</script>

<template>
  <div
    v-if="lead"
    class="fixed inset-0 z-40 flex justify-end"
    @keydown="onKeydown"
  >
    <div
      class="absolute inset-0 bg-black/40"
      data-testid="drawer-overlay"
      @click="close"
    />
    <aside
      class="relative z-10 w-96 h-full overflow-y-auto bg-n-solid-1 border-l border-n-weak p-5"
    >
      <div class="flex items-center justify-between mb-4">
        <h2 class="text-lg font-cormorant text-n-slate-12">{{ lead.name }}</h2>
        <button
          data-testid="drawer-close"
          class="text-n-slate-10 hover:text-n-slate-12"
          @click="close"
        >
          <span class="i-lucide-x size-5" />
        </button>
      </div>

      <!-- Editáveis -->
      <label class="block mb-1 text-xs text-n-slate-10">{{ $t('RAMON.DRAWER.NAME') }}</label>
      <input
        v-model="name"
        data-testid="field-name"
        class="w-full px-3 py-2 mb-3 text-sm rounded-lg bg-n-alpha-1 text-n-slate-12 border border-n-weak"
        @blur="saveName"
      />

      <label class="block mb-1 text-xs text-n-slate-10">{{ $t('RAMON.DRAWER.STAGE') }}</label>
      <select
        data-testid="field-stage"
        :value="lead.lead_stage_id"
        class="w-full px-3 py-2 mb-3 text-sm rounded-lg bg-n-alpha-1 text-n-slate-12 border border-n-weak"
        @change="e => saveSelect('lead_stage_id', Number(e.target.value))"
      >
        <option v-for="s in stages" :key="s.id" :value="s.id">{{ s.name }}</option>
      </select>

      <label class="block mb-1 text-xs text-n-slate-10">{{ $t('RAMON.DRAWER.BENEFIT') }}</label>
      <select
        :value="lead.benefit_type_id"
        class="w-full px-3 py-2 mb-3 text-sm rounded-lg bg-n-alpha-1 text-n-slate-12 border border-n-weak"
        @change="e => saveSelect('benefit_type_id', e.target.value ? Number(e.target.value) : null)"
      >
        <option :value="''">—</option>
        <option v-for="b in benefitTypes" :key="b.id" :value="b.id">{{ b.name }}</option>
      </select>

      <label class="block mb-1 text-xs text-n-slate-10">{{ $t('RAMON.DRAWER.PRIORITY') }}</label>
      <select
        :value="lead.lead_priority_id"
        class="w-full px-3 py-2 mb-3 text-sm rounded-lg bg-n-alpha-1 text-n-slate-12 border border-n-weak"
        @change="e => saveSelect('lead_priority_id', e.target.value ? Number(e.target.value) : null)"
      >
        <option :value="''">—</option>
        <option v-for="p in priorities" :key="p.id" :value="p.id">{{ p.name }}</option>
      </select>

      <label class="block mb-1 text-xs text-n-slate-10">{{ $t('RAMON.DRAWER.SDR') }}</label>
      <select
        :value="lead.sdr_id"
        class="w-full px-3 py-2 mb-3 text-sm rounded-lg bg-n-alpha-1 text-n-slate-12 border border-n-weak"
        @change="e => saveSelect('sdr_id', e.target.value ? Number(e.target.value) : null)"
      >
        <option :value="''">—</option>
        <option v-for="a in agents" :key="a.id" :value="a.id">{{ a.name }}</option>
      </select>

      <label class="block mb-1 text-xs text-n-slate-10">{{ $t('RAMON.DRAWER.CLOSER') }}</label>
      <select
        :value="lead.closer_id"
        class="w-full px-3 py-2 mb-3 text-sm rounded-lg bg-n-alpha-1 text-n-slate-12 border border-n-weak"
        @change="e => saveSelect('closer_id', e.target.value ? Number(e.target.value) : null)"
      >
        <option :value="''">—</option>
        <option v-for="a in agents" :key="a.id" :value="a.id">{{ a.name }}</option>
      </select>

      <label class="block mb-1 text-xs text-n-slate-10">{{ $t('RAMON.DRAWER.VALUE') }}</label>
      <input
        v-model="value"
        data-testid="field-value"
        type="number"
        step="0.01"
        class="w-full px-3 py-2 mb-3 text-sm rounded-lg bg-n-alpha-1 text-n-slate-12 border border-n-weak"
        @blur="saveValue"
      />

      <label class="block mb-1 text-xs text-n-slate-10">{{ $t('RAMON.DRAWER.SOURCE') }}</label>
      <input
        v-model="source"
        class="w-full px-3 py-2 mb-3 text-sm rounded-lg bg-n-alpha-1 text-n-slate-12 border border-n-weak"
        @blur="saveSource"
      />

      <label class="block mb-1 text-xs text-n-slate-10">{{ $t('RAMON.DRAWER.NOTES') }}</label>
      <textarea
        v-model="notes"
        rows="3"
        class="w-full px-3 py-2 mb-4 text-sm rounded-lg bg-n-alpha-1 text-n-slate-12 border border-n-weak"
        @blur="saveNotes"
      />

      <!-- Só leitura: contato -->
      <div class="pt-4 mt-2 border-t border-n-weak">
        <p class="mb-2 text-[9px] tracking-widest uppercase text-n-slate-9">
          {{ $t('RAMON.DRAWER.CONTACT') }}
        </p>
        <p v-if="lead.contact_name" class="text-sm text-n-slate-12">{{ lead.contact_name }}</p>
        <p v-if="lead.contact_phone" class="text-xs text-n-slate-10">{{ lead.contact_phone }}</p>
        <p v-if="lead.contact_email" class="text-xs text-n-slate-10">{{ lead.contact_email }}</p>
        <button
          v-if="lead.conversation_id"
          data-testid="drawer-open-conversation"
          class="flex items-center gap-1 mt-3 px-3 py-1.5 text-sm rounded-lg bg-n-iris-9 text-white hover:bg-n-iris-10"
          @click="emit('open-conversation', lead.conversation_id)"
        >
          <span class="i-lucide-message-square size-4" />{{ $t('RAMON.FUNIL.OPEN_CONVERSATION') }}
        </button>
      </div>
    </aside>
  </div>
</template>
```

- [ ] **Step 4: Adicionar as chaves i18n (pt_BR e en)**

Em `app/javascript/dashboard/i18n/locale/pt_BR/ramon.json`, dentro do objeto `"RAMON"` (ex.: após o bloco `"FUNIL"`), adicionar:

```json
    "DRAWER": {
      "NAME": "Nome",
      "STAGE": "Etapa",
      "BENEFIT": "Tipo de benefício",
      "PRIORITY": "Prioridade",
      "SDR": "SDR",
      "CLOSER": "Closer",
      "VALUE": "Valor (R$)",
      "SOURCE": "Origem",
      "NOTES": "Notas",
      "CONTACT": "Contato"
    }
```

Em `app/javascript/dashboard/i18n/locale/en/ramon.json`, no mesmo lugar, adicionar:

```json
    "DRAWER": {
      "NAME": "Name",
      "STAGE": "Stage",
      "BENEFIT": "Benefit type",
      "PRIORITY": "Priority",
      "SDR": "SDR",
      "CLOSER": "Closer",
      "VALUE": "Value (R$)",
      "SOURCE": "Source",
      "NOTES": "Notes",
      "CONTACT": "Contact"
    }
```

> Atenção à vírgula JSON: adicionar uma vírgula após o bloco anterior (`"FUNIL": { ... },`) antes de `"DRAWER"`.

- [ ] **Step 5: Verificar (via CI) + prettier**

```bash
npx prettier@3.3.3 --write app/javascript/dashboard/routes/dashboard/ramon/components/kanban/LeadDrawer.vue
node -e "JSON.parse(require('fs').readFileSync('app/javascript/dashboard/i18n/locale/pt_BR/ramon.json','utf8')); JSON.parse(require('fs').readFileSync('app/javascript/dashboard/i18n/locale/en/ramon.json','utf8')); console.log('JSON_OK')"
```

Esperado: `JSON_OK`.

- [ ] **Step 6: Commit**

```bash
git add app/javascript/dashboard/routes/dashboard/ramon/components/kanban/LeadDrawer.vue \
        app/javascript/dashboard/routes/dashboard/ramon/components/kanban/specs/LeadDrawer.spec.js \
        app/javascript/dashboard/i18n/locale/pt_BR/ramon.json \
        app/javascript/dashboard/i18n/locale/en/ramon.json
git commit -m "feat: LeadDrawer — gaveta de detalhe do lead, salva por campo + i18n"
```

---

### Task 10: Montagem — abrir a gaveta nos dois mundos + buscar agents

**Files:**
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/components/kanban/KanbanBoard.vue`
- Test: `app/javascript/dashboard/routes/dashboard/ramon/components/kanban/specs/KanbanBoard.spec.js` (criar)

**Interfaces:**
- Consumes: evento `open-lead` (Tasks 8), action `leads/select` (Task 7), `agents/get` (store nativo), `LeadDrawer` (Task 9).
- Produces: o `KanbanBoard` (compartilhado por `Funil.vue` e `KanbanView.vue`) monta a `LeadDrawer`, despacha `leads/select(lead.id)` ao receber `open-lead`, e propaga `open-conversation` da gaveta. Busca agents no mount (pros selects SDR/Closer). Funciona igual nos dois mundos sem tocar `Funil.vue`/`KanbanView.vue`.

- [ ] **Step 1: Escrever o teste do `KanbanBoard`**

Criar `app/javascript/dashboard/routes/dashboard/ramon/components/kanban/specs/KanbanBoard.spec.js`:

```js
import { shallowMount } from '@vue/test-utils';
import { createStore } from 'vuex';
import KanbanBoard from '../KanbanBoard.vue';

const dispatch = vi.fn();
const buildStore = () =>
  createStore({
    modules: {
      leads: {
        namespaced: true,
        getters: { getLeadsByStage: () => () => [] },
      },
      leadConfig: {
        namespaced: true,
        getters: { getStages: () => [{ id: 1, name: 'Novo', color: '#000' }] },
      },
    },
  });

const mountBoard = () => {
  const store = buildStore();
  store.dispatch = dispatch;
  return shallowMount(KanbanBoard, {
    global: { plugins: [store], mocks: { $t: k => k } },
  });
};

describe('KanbanBoard.vue', () => {
  beforeEach(() => dispatch.mockClear());

  it('busca leadConfig, leads e agents no mount', () => {
    mountBoard();
    expect(dispatch).toHaveBeenCalledWith('leadConfig/get');
    expect(dispatch).toHaveBeenCalledWith('leads/get');
    expect(dispatch).toHaveBeenCalledWith('agents/get');
  });

  it('seleciona o lead ao receber open-lead de uma coluna', () => {
    const wrapper = mountBoard();
    wrapper
      .findComponent({ name: 'KanbanColumn' })
      .vm.$emit('open-lead', { id: 33 });
    expect(dispatch).toHaveBeenCalledWith('leads/select', 33);
  });
});
```

> Se `findComponent({ name: 'KanbanColumn' })` não resolver, importar `KanbanColumn` e usar `findComponent(KanbanColumn)`.

- [ ] **Step 2: Verificar a falha (via CI)**

Sem run local.

- [ ] **Step 3: Atualizar `KanbanBoard.vue`**

`<script setup>` final (substitui o arquivo todo, já incorporando a remoção de benefitTypes/priorities da Task 8):

```vue
<script setup>
import { computed, onMounted } from 'vue';
import { useStore, useStoreGetters } from 'dashboard/composables/store';
import KanbanColumn from './KanbanColumn.vue';
import LeadDrawer from './LeadDrawer.vue';

const emit = defineEmits(['new-lead', 'open-conversation']);
const store = useStore();
const getters = useStoreGetters();

const stages = computed(() => getters['leadConfig/getStages'].value);
const leadsByStage = stageId => getters['leads/getLeadsByStage'].value(stageId);

const onMove = ({ id, leadStageId, newIndex }) => {
  store.dispatch('leads/move', { id, leadStageId, position: newIndex });
};

const onOpenLead = lead => {
  store.dispatch('leads/select', lead.id);
};

onMounted(() => {
  store.dispatch('leadConfig/get');
  store.dispatch('leads/get');
  store.dispatch('agents/get');
});
</script>

<template>
  <div class="flex flex-col h-full">
    <div class="flex items-center justify-between px-4 py-3">
      <h1 class="text-xl font-cormorant text-n-slate-12">
        {{ $t('RAMON.FUNIL.TITLE') }}
      </h1>
      <button
        class="flex items-center gap-1 px-3 py-1.5 text-sm rounded-lg bg-n-iris-9 text-white hover:bg-n-iris-10"
        @click="emit('new-lead')"
      >
        <span class="i-lucide-plus size-4" />{{ $t('RAMON.FUNIL.NEW_LEAD') }}
      </button>
    </div>
    <div class="flex flex-1 gap-3 px-4 pb-4 overflow-x-auto">
      <KanbanColumn
        v-for="stage in stages"
        :key="stage.id"
        :stage="stage"
        :leads="leadsByStage(stage.id)"
        @move="onMove"
        @open-conversation="id => emit('open-conversation', id)"
        @open-lead="onOpenLead"
      />
    </div>
    <LeadDrawer @open-conversation="id => emit('open-conversation', id)" />
  </div>
</template>
```

> `LeadDrawer` tem `v-if="lead"` interno — só renderiza quando há lead selecionado. `Funil.vue` e `KanbanView.vue` não mudam: ambos já roteiam `open-conversation` ao `inbox_conversation`.

- [ ] **Step 4: Verificar (via CI) + prettier**

```bash
npx prettier@3.3.3 --write app/javascript/dashboard/routes/dashboard/ramon/components/kanban/KanbanBoard.vue app/javascript/dashboard/routes/dashboard/ramon/components/kanban/specs/KanbanBoard.spec.js
```

- [ ] **Step 5: Commit**

```bash
git add app/javascript/dashboard/routes/dashboard/ramon/components/kanban/KanbanBoard.vue \
        app/javascript/dashboard/routes/dashboard/ramon/components/kanban/specs/KanbanBoard.spec.js
git commit -m "feat: monta LeadDrawer no board + busca agents + abre gaveta no open-lead"
```

---

### Task 11: Schema regen + lint + PR/CI + deploy/smoke

**Files:**
- Modify: `db/schema.rb` (regenerado via scratch DB na VPS — NÃO editar à mão)

**Interfaces:**
- Consumes: tudo das Tasks 1-10.
- Produces: PR verde no CI (`run_foss_spec`) → merge → deploy na VPS → smoke.

> Esta task tem passos que **só o Eduardo autoriza/executa** (SSH na VPS, push/merge, `db:migrate` em prod). Claude propõe e, com OK explícito, roda via SSH (padrão 2A/2B/2C).

- [ ] **Step 1: Regenerar `db/schema.rb` via scratch DB na VPS**

Como não há Ruby local e o CI faz `db:schema:load` (não roda migrations), o `schema.rb` precisa refletir as 4 colunas novas. Rodar num container descartável contra um banco scratch (produção intacta) — imagem é slim, usar `sh`:

```bash
ssh -i ~/.ssh/id_ed25519 root@185.194.216.67 \
  "cd /opt/intranet-ramon && docker compose run --rm \
   -e POSTGRES_DATABASE=ramon_schema_scratch4 \
   -e DISABLE_DATABASE_ENVIRONMENT_CHECK=1 \
   chatwoot-web sh -lc 'bundle exec rails db:create db:schema:load db:migrate db:schema:dump && cat db/schema.rb' > /tmp/schema_a1.rb"
```

Copiar o `db/schema.rb` resultante para o working tree local, conferir que ele contém `t.decimal \"value\"`, `t.string \"source\"`, `t.text \"notes\"` em `create_table \"leads\"` e `t.string \"color\"` em `create_table \"lead_stages\"`, e que o `version:` subiu para `2026_06_30_000005`. Dropar o scratch:

```bash
ssh -i ~/.ssh/id_ed25519 root@185.194.216.67 \
  "cd /opt/intranet-ramon && docker compose run --rm chatwoot-web sh -lc 'PGPASSWORD=\$POSTGRES_PASSWORD dropdb -h \$POSTGRES_HOST -U \$POSTGRES_USERNAME ramon_schema_scratch4'"
```

```bash
git add db/schema.rb
git commit -m "chore: regenera schema.rb com as colunas A1"
```

- [ ] **Step 2: Lint final (prettier em todo o ramon tocado)**

```bash
npx prettier@3.3.3 --check app/javascript/dashboard/routes/dashboard/ramon/components/kanban/ app/javascript/dashboard/store/modules/leads.js
```

Se acusar diferença, rodar `--write` e commitar.

- [ ] **Step 3: Push da branch + abrir PR (Eduardo autoriza)**

```bash
git push -u origin feat/ramon-hub-a1-card-drawer
gh pr create --title "feat: A1 — card rico + gaveta de detalhe do lead" \
  --body "Implementa a fatia A1 (card rico + LeadDrawer). Salva por campo. Reusa o espelho fase-* da 2C ao editar etapa. Colunas novas: leads.value/source/notes, lead_stages.color." \
  --base ramon
```

- [ ] **Step 4: Acompanhar o CI (`run_foss_spec`) até verde**

```bash
gh pr checks --watch
```

Esperado: rspec + vitest + rubocop + eslint verdes. Se vermelho: ler o log, corrigir (lições recorrentes: rubocop `Metrics/*` → disable pontual; `RSpec/DescribeClass` em describe-string; eslint só falha em error). Commitar o fix e re-observar.

- [ ] **Step 5: Merge (Eduardo autoriza) + deploy na VPS (OK explícito p/ db:migrate)**

Após o merge na `ramon`, o workflow `ramon-publish.yml` builda a imagem `ghcr.io/doods-maker/ramon-hub:v4.15.1-ramon` (~7-8min com cache). Com OK do Eduardo:

```bash
ssh -i ~/.ssh/id_ed25519 root@185.194.216.67 \
  "cd /opt/intranet-ramon && git pull && \
   docker compose pull chatwoot-web chatwoot-worker && \
   docker compose run --rm chatwoot-web sh -lc 'bundle exec rails db:migrate' && \
   docker compose up -d chatwoot-web chatwoot-worker"
```

> `db:migrate` aplica `20260630000005` em prod (cria as 4 colunas). O backfill da `color` nas 8 etapas da conta 2 acontece ao re-rodar o seed:

```bash
ssh -i ~/.ssh/id_ed25519 root@185.194.216.67 \
  "cd /opt/intranet-ramon && docker compose run --rm chatwoot-web sh -lc \
   'bundle exec rails runner \"Account.find(2).then { |a| Leads::SeedDefaultConfigService.new(a).perform }\"'"
```

- [ ] **Step 6: Smoke**

- Técnico (via SSH): `curl -s localhost/api | grep version` → 4.15.1; `.git_sha` = HEAD da `ramon`; web/worker `Up`; `Account.find(2).lead_stages.pluck(:name, :color)` → 8 etapas com cor.
- Visual (Eduardo): abrir o Funil (mundo Intranet) e o Kanban (mundo Conversas); card mostra chip colorido/valor/dono; clicar no card abre a gaveta à direita; editar um campo e ver salvar (recarregar confirma); editar a etapa na gaveta → a label `fase-*` da conversa muda (espelho 2C); abrir conversa pela gaveta; fechar por X/Esc/clique-fora.

---

## Notas de verificação (self-review)

- **Cobertura da spec:** value/source/notes (T1,3,5,6,8,9) · color da etapa (T1,2,4,8) · serializer desnormalizado + contato (T3) · push_event_data (T5) · controller params (T6) · LeadCard rico + open-lead (T8) · LeadDrawer editável/só-leitura/fechar (T9) · montagem nos dois mundos + agents (T10) · realtime sem empobrecer (T7, merge) · testes model/serializer/controller/front (todas) · schema/PR/CI/deploy (T11). ✅
- **Decisão de design além da spec:** o realtime usa **merge** (`MERGE_LEAD`) em vez de replace — a spec só pedia push_event_data completo, mas `setSingleRecord` substitui o objeto, então sem merge a gaveta perderia `notes`/contato no eco de update. Documentado na Task 7.
- **Fora de escopo (futuras fatias):** A2/2D (configs geríveis na UI: criar/renomear/reordenar etapas+cor, benefícios/prioridades, toggles) · A3 (filtros/busca + valor total por coluna + quick-add) · A4/2E (campos custom).
