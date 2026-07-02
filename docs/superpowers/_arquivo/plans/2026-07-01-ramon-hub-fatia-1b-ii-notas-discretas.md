# Fatia 1b-ii — Notas discretas do lead Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transformar o campo único `leads.notes` (blob) em **notas discretas** (`lead_notes`, com autor e data): adicionar no Resumo (lista + caixa "adicionar nota") e ver intercaladas na timeline do Histórico (via atividade `note_added`).

**Architecture:** Nova tabela `lead_notes`. Ao criar uma nota, um callback registra também uma `lead_activity` `note_added` (autor = `Current.user`) para a nota aparecer na timeline (a 1b-i já renderiza atividades). O `LeadFields` troca o textarea de notas por uma lista + input. O blob `leads.notes` é migrado para 1 nota por lead e a coluna é removida; todas as referências ao blob (serializer, permitted_params, LeadFields) são retiradas na mesma fatia.

**Tech Stack:** Ruby on Rails (2 migrations + model + callback + API), Vue 3 `<script setup>` + Vuex, RSpec, Vitest, Tailwind. Fork do Chatwoot v4.15.1, branch `ramon`.

## Global Constraints

- Fork merge-safe: código novo sob `ramon/` (frontend) ou backend fork-owned; **toda edição de arquivo core registrada** em `docs/FORK-PONTOS-DE-REGISTRO.md`. Core tocado: `app/models/lead.rb`, `app/models/account.rb`, `config/routes.rb`, `app/views/api/v1/accounts/leads/_lead.json.jbuilder`, `app/controllers/api/v1/accounts/leads_controller.rb`.
- **Sem ambiente de teste local.** Verificação = feature branch → PR → CI (`run_foss_spec`). Só `npx prettier@3.3.3 --write` roda local. Specs TDD-first, raciocinar RED/GREEN, marcar "CI-deferred".
- **TEM MIGRAÇÃO** (2 migrations: create_lead_notes + remove leads.notes). `db/schema.rb` **NÃO é editado pelo implementer** — o controller regenera na VPS (scratch DB). Deploy roda `db:migrate` + restart.
- **Lições reutilizáveis das fatias anteriores (aplicar):**
  - `Lint/RedundantCopDisableDirective`: **NÃO adicionar `# rubocop:disable` preventivo** — só adicionar disable depois que o CI confirmar o offense. (Callbacks/migrations que usam `create!` não precisam de disable; `delete_all` numa migration/spec pode ou não ser flagado — não pré-disable.)
  - `RSpec/ContextWording`: todo `context '...'` começa com `when`/`with`/`without`.
  - `vue/no-bare-strings-in-template`: nenhum símbolo/texto solto no template (`·`, `→`, etc.) — montar via interpolação/`useI18n` `t`.
  - **Callback que cria registro no `create`** → specs que fixam esses registros devem **`destroy_all` antes** (a criação do lead/nota auto-gera atividade).
  - `vue/define-macros-order`: `defineProps` antes de `defineOptions`.
  - Evento custom Vue camelCase (emit) / kebab (listener); prettier em todo `ramon/`.
- Autor: `Current.user` disponível no callback durante o request; sistema (jobs) = nil; nunca falhar por autor nil.
- Regra de ouro: nada no ar sem OK explícito do Eduardo; merge/deploy dele.

---

### Task 1: Tabela `lead_notes` + model + associações

**Files:**
- Create: `db/migrate/<timestamp>_create_lead_notes.rb`
- Create: `app/models/lead_note.rb`
- Modify: `app/models/account.rb` (has_many), `app/models/lead.rb` (has_many)
- Test: `spec/models/lead_note_spec.rb`
- Modify: `docs/FORK-PONTOS-DE-REGISTRO.md`

**Interfaces:**
- Produces: model `LeadNote` colunas `account_id` (null:false), `lead_id` (null:false), `user_id` (nullable), `body` (text, null:false), `created_at`/`updated_at`; `belongs_to :account/:lead`, `belongs_to :user, optional: true`; `validates :body, presence: true`; `default_scope { order(created_at: :asc) }`.

- [ ] **Step 1: model spec que falha**

```ruby
# spec/models/lead_note_spec.rb
require 'rails_helper'

RSpec.describe LeadNote do
  let(:account) { create(:account) }
  let(:lead) { create(:lead, account: account) }

  it 'is valid with a lead and body' do
    expect(described_class.new(account: account, lead: lead, body: 'oi')).to be_valid
  end

  it 'requires a body' do
    expect(described_class.new(account: account, lead: lead, body: nil)).not_to be_valid
  end

  it 'belongs to an optional author' do
    user = create(:user, account: account)
    note = described_class.create!(account: account, lead: lead, user: user, body: 'x')
    expect(note.reload.user).to eq(user)
  end
end
```

- [ ] **Step 2: rodar (CI) e ver falhar** — Esperado: FAIL (`uninitialized constant LeadNote`).

- [ ] **Step 3: migration** (versão `ActiveRecord::Migration[7.1]` como as vizinhas; timestamp > a mais nova em `db/migrate/`)

```ruby
class CreateLeadNotes < ActiveRecord::Migration[7.1]
  def change
    create_table :lead_notes do |t|
      t.references :account, null: false, foreign_key: true
      t.references :lead, null: false, foreign_key: true
      t.references :user, null: true, foreign_key: true
      t.text :body, null: false
      t.timestamps
    end
    add_index :lead_notes, [:lead_id, :created_at]
  end
end
```

- [ ] **Step 4: model**

```ruby
# app/models/lead_note.rb
class LeadNote < ApplicationRecord
  belongs_to :account
  belongs_to :lead
  belongs_to :user, optional: true

  validates :body, presence: true

  default_scope { order(created_at: :asc) }
end
```

- [ ] **Step 5: associações** — `has_many :lead_notes, dependent: :destroy_async` em `account.rb` (junto de lead_activities, alfabético) e em `lead.rb`.

- [ ] **Step 6: FORK-PONTOS** (account.rb + lead.rb has_many :lead_notes — fase 1b-ii). **NÃO editar `db/schema.rb`.**

- [ ] **Step 7: Commit**

```bash
git add db/migrate app/models/lead_note.rb app/models/account.rb app/models/lead.rb \
        spec/models/lead_note_spec.rb docs/FORK-PONTOS-DE-REGISTRO.md
git commit -m "feat: add lead_notes table and model"
```

---

### Task 2: Nota gera atividade `note_added` (com autor)

**Files:**
- Modify: `app/models/lead_note.rb`
- Test: `spec/models/lead_note_spec.rb` (adicionar contexto)

**Interfaces:**
- Consumes: `LeadActivity` (1b-i), `Current.user`.
- Produces: ao criar uma `LeadNote` → 1 `LeadActivity` `kind:'note_added'`, `user: Current.user`, `to_value` = trecho do corpo (até 60 chars), no mesmo lead/account.

- [ ] **Step 1: spec que falha**

```ruby
# em spec/models/lead_note_spec.rb
RSpec.describe LeadNote do
  let(:account) { create(:account) }
  let(:lead) { create(:lead, account: account) }
  before { Current.user = nil }
  after { Current.user = nil }

  it 'records a note_added activity on creation with author and body snippet' do
    agent = create(:user, account: account)
    Current.user = agent
    note = described_class.create!(account: account, lead: lead, body: 'Ligou pedindo retorno')
    activity = lead.lead_activities.find_by(kind: 'note_added')
    expect(activity).to be_present
    expect(activity.user).to eq(agent)
    expect(activity.to_value).to include('Ligou pedindo retorno')
  end
end
```

- [ ] **Step 2: rodar (CI) e ver falhar.**

- [ ] **Step 3: callback no model**

```ruby
# app/models/lead_note.rb — adicionar
after_create_commit :record_note_activity

private

def record_note_activity
  lead.lead_activities.create!(
    account: account, user: Current.user, kind: 'note_added', to_value: body.to_s.truncate(60)
  )
end
```

- [ ] **Step 4: rodar (CI) e ver passar.**

- [ ] **Step 5: Commit**

```bash
git add app/models/lead_note.rb spec/models/lead_note_spec.rb
git commit -m "feat: record note_added activity when a lead note is created"
```

---

### Task 3: API de notas (index + create)

**Files:**
- Create: `app/controllers/api/v1/accounts/lead_notes_controller.rb`
- Create: `app/policies/lead_note_policy.rb`
- Create: `app/views/api/v1/accounts/lead_notes/index.json.jbuilder`, `_lead_note.json.jbuilder`, `create.json.jbuilder`
- Modify: `config/routes.rb`
- Test: `spec/controllers/api/v1/accounts/lead_notes_controller_spec.rb`
- Modify: `docs/FORK-PONTOS-DE-REGISTRO.md`

**Interfaces:**
- Produces: `GET /api/v1/accounts/:account_id/leads/:lead_id/notes` → `{payload:[{id, body, author_name, created_at}]}` (asc); `POST .../notes` body `{body}` → cria e retorna a nota (autor = usuário atual). Note: o `note_added` activity é gerado pelo model (Task 2), não pelo controller.

- [ ] **Step 1: request spec que falha**

```ruby
# spec/controllers/api/v1/accounts/lead_notes_controller_spec.rb
require 'rails_helper'

RSpec.describe 'Lead Notes API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:lead) { create(:lead, account: account) }

  it 'lists notes chronologically' do
    lead.lead_notes.create!(account: account, body: 'primeira', created_at: 2.days.ago)
    lead.lead_notes.create!(account: account, body: 'segunda', user: admin, created_at: 1.hour.ago)
    get "/api/v1/accounts/#{account.id}/leads/#{lead.id}/notes",
        headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    payload = response.parsed_body['payload']
    expect(payload.map { |n| n['body'] }).to eq(%w[primeira segunda])
    expect(payload.last['author_name']).to eq(admin.name)
  end

  it 'creates a note authored by the current user' do
    expect do
      post "/api/v1/accounts/#{account.id}/leads/#{lead.id}/notes",
           params: { body: 'nova nota' }, headers: admin.create_new_auth_token, as: :json
    end.to change(lead.lead_notes, :count).by(1)
    expect(response).to have_http_status(:success)
    expect(response.parsed_body['author_name']).to eq(admin.name)
  end
end
```

- [ ] **Step 2: rodar (CI) e ver falhar.**

- [ ] **Step 3: rota** — dentro do bloco `resources :leads do`:
```ruby
resources :notes, only: [:index, :create], controller: 'lead_notes'
```

- [ ] **Step 4: controller**

```ruby
# app/controllers/api/v1/accounts/lead_notes_controller.rb
class Api::V1::Accounts::LeadNotesController < Api::V1::Accounts::BaseController
  before_action :fetch_lead

  def index
    authorize(@lead, :show?)
    @notes = @lead.lead_notes
  end

  def create
    authorize(@lead, :show?)
    @note = @lead.lead_notes.create!(account: @lead.account, user: Current.user, body: params.require(:body))
    render :show
  end

  private

  def fetch_lead
    @lead = Current.account.leads.find(params[:lead_id])
  end
end
```

Confirme a superclasse/estilo lendo `lead_activities_controller.rb` (1b-i) e siga IGUAL. Se `render :show` exigir view própria, use a `create.json.jbuilder` do Step 6 (renderiza `_lead_note`). O `authorize(@lead, :show?)` reusa `LeadPolicy`; ainda assim crie `LeadNotePolicy` (Step 5) com `index?`/`create?` (lição 1a: se algum dia declarar check_authorization).

- [ ] **Step 5: policy**
```ruby
# app/policies/lead_note_policy.rb
class LeadNotePolicy < ApplicationPolicy
  def index?
    @account_user.administrator? || @account_user.agent?
  end

  def create?
    @account_user.administrator? || @account_user.agent?
  end
end
```

- [ ] **Step 6: views**
```ruby
# index.json.jbuilder
json.payload do
  json.array! @notes, partial: 'lead_note', as: :note
end
```
```ruby
# _lead_note.json.jbuilder
json.id note.id
json.body note.body
json.author_name note.user&.name
json.created_at note.created_at
```
```ruby
# create.json.jbuilder  (renderiza a nota criada)
json.partial! 'lead_note', note: @note
```
(Confirme se o controller deve `render :show` ou `render :create` — use o nome do arquivo que criar; o exemplo usa `create.json.jbuilder`, então troque `render :show` por `render :create` OU renderize implícito deixando a action sem `render` e criando `create.json.jbuilder`. Siga o padrão do `leads_controller` `create`.)

- [ ] **Step 7: rodar (CI) e ver passar.**

- [ ] **Step 8: FORK-PONTOS (routes) + Commit**
```bash
git add app/controllers/api/v1/accounts/lead_notes_controller.rb app/policies/lead_note_policy.rb \
        app/views/api/v1/accounts/lead_notes config/routes.rb \
        spec/controllers/api/v1/accounts/lead_notes_controller_spec.rb docs/FORK-PONTOS-DE-REGISTRO.md
git commit -m "feat: add lead notes index/create endpoints"
```

---

### Task 4: Store + API client de notas

**Files:**
- Modify: `app/javascript/dashboard/api/leads.js`
- Modify: `app/javascript/dashboard/store/modules/leads.js`
- Test: `app/javascript/dashboard/store/modules/specs/leads/actions.spec.js`

**Interfaces:**
- Produces:
  - `LeadsAPI.getNotes(leadId)` → GET `${this.url}/${leadId}/notes`
  - `LeadsAPI.createNote(leadId, body)` → POST `${this.url}/${leadId}/notes` `{body}`
  - store `leads/fetchNotes(_ctx, leadId)` → retorna `response.data.payload`
  - store `leads/createNote(_ctx, { leadId, body })` → retorna `response.data` (a nota criada); sem mutação de store.

- [ ] **Step 1: testes que falham**

```js
describe('leads/fetchNotes', () => {
  it('gets notes and returns payload', async () => {
    const notes = [{ id: 1, body: 'a' }];
    axios.get.mockResolvedValue({ data: { payload: notes } });
    expect(await actions.fetchNotes({}, 5)).toEqual(notes);
  });
});
describe('leads/createNote', () => {
  it('posts a note and returns it', async () => {
    const note = { id: 9, body: 'nova' };
    axios.post.mockResolvedValue({ data: note });
    const result = await actions.createNote({}, { leadId: 5, body: 'nova' });
    expect(result).toEqual(note);
    expect(axios.post).toHaveBeenCalledWith(expect.stringContaining('/5/notes'), { body: 'nova' });
  });
});
```

- [ ] **Step 2: rodar (CI) e ver falhar.**

- [ ] **Step 3: api methods** (em `api/leads.js`)
```js
getNotes(leadId) {
  return axios.get(`${this.url}/${leadId}/notes`);
}
createNote(leadId, body) {
  return axios.post(`${this.url}/${leadId}/notes`, { body });
}
```

- [ ] **Step 4: store actions**
```js
async fetchNotes(_ctx, leadId) {
  const response = await LeadsAPI.getNotes(leadId);
  return response.data.payload;
},
async createNote(_ctx, { leadId, body }) {
  const response = await LeadsAPI.createNote(leadId, body);
  return response.data;
},
```

- [ ] **Step 5: rodar (CI) e ver passar.**

- [ ] **Step 6: Prettier + Commit**
```bash
npx prettier@3.3.3 --write app/javascript/dashboard/api/leads.js app/javascript/dashboard/store/modules/leads.js
git add app/javascript/dashboard/api/leads.js app/javascript/dashboard/store/modules/leads.js \
        app/javascript/dashboard/store/modules/specs/leads/actions.spec.js
git commit -m "feat: add fetchNotes/createNote store actions"
```

---

### Task 5: `LeadFields` — notas discretas (lista + adicionar), remove o blob

**Files:**
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/components/lead/LeadFields.vue`
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/components/lead/specs/LeadFields.spec.js`
- Modify: `app/javascript/dashboard/i18n/locale/en/ramon.json`, `pt_BR/ramon.json`

**Interfaces:**
- Consumes: `leads/fetchNotes`, `leads/createNote` (Task 4).
- Produces: `LeadFields` deixa de usar `lead.notes` (blob); mostra lista de notas (autor + texto) + caixa "adicionar nota". Emite nada (usa store).

- [ ] **Step 1: atualizar o spec (falha)**

Remover as asserções sobre o textarea `notes` (blob) e adicionar:
```js
// no build store, adicionar actions fetchNotes/createNote spies e um getter/estado não é necessário (local ref)
it('loads notes on mount and adds a note', async () => {
  const fetchNotes = vi.fn().mockResolvedValue([{ id: 1, body: 'oi', author_name: 'Ana', created_at: 'x' }]);
  const createNote = vi.fn().mockResolvedValue({ id: 2, body: 'nova', author_name: 'Ana', created_at: 'y' });
  const wrapper = mountFields(/* store com actions leads: {fetchNotes, createNote, update} */);
  await flushPromises();
  expect(fetchNotes).toHaveBeenCalledWith(expect.anything(), 3); // lead.id do fixture
  await wrapper.find('[data-testid="note-input"]').setValue('nova');
  await wrapper.find('[data-testid="note-add"]').trigger('click');
  expect(createNote).toHaveBeenCalledWith(expect.anything(), { leadId: 3, body: 'nova' });
});
```
Ajuste o helper `mountFields`/`build` do arquivo p/ incluir `fetchNotes`/`createNote` nas actions do módulo `leads` e mockar `vue-i18n` `useI18n` se você usar `t` no script (lição 1b-i). Mantenha os testes existentes dos outros campos.

- [ ] **Step 2: rodar (CI) e ver falhar.**

- [ ] **Step 3: editar `LeadFields.vue`**

Remover: `const notes = ref('')`, o sync `notes.value = l?.notes` no watch, `saveNotes`, e o bloco `<textarea>` de notas (label `RAMON.DRAWER.NOTES`).

Adicionar no `<script setup>`:
```js
import { useStore } from 'dashboard/composables/store'; // já existe
const noteList = ref([]);
const newNote = ref('');
const loadNotes = async () => {
  noteList.value = await store.dispatch('leads/fetchNotes', props.lead.id);
};
watch(() => props.lead?.id, id => { if (id) loadNotes(); }, { immediate: true });
const addNote = async () => {
  const body = newNote.value.trim();
  if (!body) return;
  await store.dispatch('leads/createNote', { leadId: props.lead.id, body });
  newNote.value = '';
  await loadNotes();
};
```
Adicionar no `<template>` (no lugar do textarea antigo):
```html
<div class="flex flex-col gap-2">
  <span class="text-xs uppercase opacity-60">{{ $t('RAMON.DRAWER.NOTES') }}</span>
  <div v-for="note in noteList" :key="note.id" data-testid="note-item" class="text-sm border-l-2 pl-2">
    <strong v-if="note.author_name">{{ note.author_name }}</strong>
    <span>{{ note.body }}</span>
  </div>
  <textarea v-model="newNote" data-testid="note-input" rows="2" class="..." :placeholder="$t('RAMON.DRAWER.NOTES_ADD')" />
  <button data-testid="note-add" class="..." @click="addNote">{{ $t('RAMON.DRAWER.NOTES_ADD_BUTTON') }}</button>
</div>
```
(Reaproveite classes Tailwind já usadas no arquivo p/ inputs/botões; nada de `:value=""`.)

- [ ] **Step 4: i18n** — em `en/ramon.json` e `pt_BR/ramon.json`:
  - sob `RAMON.DRAWER`: `NOTES_ADD` (pt "Escreva uma nota…" / en "Write a note…"), `NOTES_ADD_BUTTON` (pt "Adicionar nota" / en "Add note").
  - sob `RAMON.LEAD_PANEL.HISTORY.KIND`: `NOTE_ADDED` (pt "adicionou nota" / en "added a note") — para o `note_added` aparecer no Histórico.

- [ ] **Step 5: rodar (CI) e ver passar.**

- [ ] **Step 6: Prettier + Commit**
```bash
npx prettier@3.3.3 --write app/javascript/dashboard/routes/dashboard/ramon/components/lead \
        app/javascript/dashboard/i18n/locale/en/ramon.json app/javascript/dashboard/i18n/locale/pt_BR/ramon.json
git add app/javascript/dashboard/routes/dashboard/ramon/components/lead \
        app/javascript/dashboard/i18n/locale/en/ramon.json app/javascript/dashboard/i18n/locale/pt_BR/ramon.json
git commit -m "feat: discrete notes list and add-note in LeadFields"
```

---

### Task 6: Migrar o blob + remover a coluna + limpar referências

**Files:**
- Create: `db/migrate/<ts1>_backfill_lead_notes_from_blob.rb`
- Create: `db/migrate/<ts2>_remove_notes_from_leads.rb`
- Modify: `app/views/api/v1/accounts/leads/_lead.json.jbuilder` (remover linha `json.notes`)
- Modify: `app/controllers/api/v1/accounts/leads_controller.rb` (remover `:notes` do permitted_params)
- Modify: `docs/FORK-PONTOS-DE-REGISTRO.md`

**Interfaces:** consome `LeadNote` (Task 1). `<ts2>` deve ser > `<ts1>` (backfill roda antes do drop).

- [ ] **Step 1: backfill migration**
```ruby
class BackfillLeadNotesFromBlob < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!
  def up
    Lead.where.not(notes: [nil, '']).find_each do |lead|
      next if lead.lead_notes.exists?
      lead.lead_notes.create!(account_id: lead.account_id, body: lead.notes, created_at: lead.created_at)
    end
  end
  def down; end
end
```
(Idempotente: `next if lead.lead_notes.exists?`. `user_id` nulo. NÃO gera `note_added` — evita ruído; o callback só dispara em create via app, mas aqui é migration; o after_create_commit DISPARARIA. Para evitar, usar `LeadNote.insert_all` NÃO — perde validação/callback control. Alternativa: aceitar 1 `note_added` por nota migrada é aceitável? **Decisão: aceitar** — a nota migrada gera 1 note_added na timeline, coerente. Se não quiser, o revisor decide.)

- [ ] **Step 2: remove-column migration**
```ruby
class RemoveNotesFromLeads < ActiveRecord::Migration[7.1]
  def change
    remove_column :leads, :notes, :text
  end
end
```

- [ ] **Step 3: remover `json.notes lead.notes`** de `_lead.json.jbuilder` (linha ~16).

- [ ] **Step 4: remover `:notes`** do `permitted_params` em `leads_controller.rb` (linha ~78).

- [ ] **Step 5: grep de segurança** — rodar `grep -rn "\.notes\b\|:notes\|'notes'\|\"notes\"" app/ spec/ --include=*.rb --include=*.vue --include=*.js` e confirmar que NENHUMA referência a `leads.notes` (blob) sobrou (LeadFields já limpo na Task 5; specs de lead não devem setar `notes:`). `lead_notes`/`note.body` são OK (é a tabela nova). Reportar o resultado.

- [ ] **Step 6: FORK-PONTOS** (jbuilder + controller — remoção do blob notes; 2 migrations) + Commit
```bash
git add db/migrate app/views/api/v1/accounts/leads/_lead.json.jbuilder \
        app/controllers/api/v1/accounts/leads_controller.rb docs/FORK-PONTOS-DE-REGISTRO.md
git commit -m "feat: backfill lead notes from blob and drop leads.notes column"
```

---

### Task 7: schema regen, PR, CI, deploy (com migração), smoke

**Files:** nenhum de app.

- [ ] **Step 1: Regenerar `db/schema.rb` (controller, VPS scratch DB)** — mesmo procedimento da 1b-i: container one-off contra `ramon_schema_scratchN`, injetar as migrations DDL desta fatia (create_lead_notes + remove_notes), `db:create db:schema:load db:migrate db:schema:dump`, extrair o schema.rb, ajustar a versão para a mais nova, produção intacta. Commit `chore: regenerate schema.rb for lead_notes`.

- [ ] **Step 2: Push + PR** contra `ramon`, título `feat: notas discretas do lead (Resumo + Histórico)`.

- [ ] **Step 3: CI `run_foss_spec` verde** — aplicar as lições (sem disables preventivos; context wording; bare strings; `destroy_all` em specs que fixam notas/atividades — a criação de nota gera `note_added`).

- [ ] **Step 4: Merge (OK do Eduardo).**

- [ ] **Step 5: Deploy VPS (OK explícito do Eduardo) — COM migração** — pull + `docker compose --profile init run --rm chatwoot-init` (roda create_lead_notes + backfill + remove_notes) + `up -d chatwoot-web chatwoot-worker`; verificar no banco: tabela `lead_notes` existe, coluna `leads.notes` NÃO existe mais, notas migradas. Smoke: abrir conversa → Resumo → ver/adicionar nota; Histórico → "adicionou nota".

---

## Self-Review

**Spec coverage (contra `2026-07-01-ramon-hub-fatia-1b-...-design.md`, parte 1b-ii):**
- `lead_notes` (tabela + model) → Task 1. ✅
- Nota gera `note_added` na timeline (com autor) → Task 2. ✅
- API notas (index+create) → Task 3. ✅
- Store → Task 4. ✅
- Resumo: lista + adicionar nota; remove textarea blob → Task 5. ✅
- Notas intercaladas no Histórico → via `note_added` (1b-i renderiza) + i18n KIND.NOTE_ADDED (Task 5). ✅
- Migrar blob → nota + remover coluna `leads.notes` + limpar serializer/controller → Task 6. ✅
- schema regen + deploy com migração → Task 7. ✅

**Placeholder scan:** sem TBD; cada passo tem código. Pontos "confirme no código real" (superclasse do controller, render de create, classes Tailwind) são verificações do executor.

**Type consistency:** `LeadNote(body, user, account, lead)`; `note_added` kind ↔ i18n `KIND.NOTE_ADDED`; `fetchNotes(_ctx, leadId)`/`createNote(_ctx,{leadId,body})` → payload/nota; `getNotes`/`createNote` api; `note-input`/`note-add`/`note-item` testids. Consistentes Tasks 1→6.

**Riscos abertos:** (1) remover `leads.notes` é irreversível — a Task 6 Step 5 (grep) é a rede de segurança contra referência órfã; o review final deve reconfirmar. (2) backfill gera 1 `note_added` por nota migrada (decisão aceita; revisor pode vetar). (3) a criação de nota gera atividade → specs que fixam notas/atividades usam `destroy_all` antes.
