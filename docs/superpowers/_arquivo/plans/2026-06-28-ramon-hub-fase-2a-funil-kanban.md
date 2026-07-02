# Fase 2A — Funil/Kanban com `Lead` nativo (espinha) — Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Entregar um board Funil/Kanban usável, com `Lead` nativo no Postgres da VPS, drag&drop entre etapas, criação manual de lead e "abrir conversa" — renderizado tanto no mundo **Intranet** (Funil) quanto no mundo **Conversas** (Kanban Board), compartilhando o mesmo store Vuex.

**Architecture:** `Lead` é um recurso Rails account-scoped espelhando o padrão de `Label` (model/controller/jbuilder/policy/store/api). Etapas, tipos de benefício e prioridades nascem como **tabelas relacionais semeadas** (não enum hardcoded) para que as Fases 2D (CRUD dessas listas) e 2E (campos custom, via coluna `custom_attributes` jsonb já provisionada) não exijam re-migração. O board é um componente único (`KanbanBoard`) consumido pelas duas telas a partir do mesmo módulo Vuex — o espelho entre os mundos é automático na mesma aba (realtime multi-usuário é a Fase 2B).

**Tech Stack:** Ruby on Rails (RSpec), Postgres (`chatwoot_production` na VPS), Vue 3 + Vuex + Vite, `vuedraggable ^4.1.0` (já nas deps), Tailwind (tokens bronze de `_ramon-brand.scss`).

## Global Constraints

- **Versão base:** Chatwoot v4.15.1 (fork `ramon-hub`, branch `ramon`). Não fazer rebase/upgrade.
- **Fork-safe:** arquivos novos sob namespace `ramon/` no front sempre que possível. Tocar no core SÓ nos pontos de registro listados por tarefa; nunca editar `enterprise/`. Registrar pontos novos em `docs/FORK-PONTOS-DE-REGISTRO.md`.
- **Marca:** dark + bronze; tokens de `app/javascript/dashboard/assets/scss/_ramon-brand.scss`. **Sem segunda cor** — prioridade "Alta" é bronze sólido, nunca vermelho. Cormorant (`font-cormorant`) para títulos/números; Inter para UI. **Sem emoji.** Ícones Lucide (`i-lucide-*`).
- **i18n:** PT-BR em `app/javascript/dashboard/i18n/locale/pt_BR/ramon.json` (já registrado no `index.js`); espelho mínimo em `en/ramon.json`. Chaves sob `RAMON.*`.
- **Etapas semeadas (ordem):** Novo · Qualificação · Reunião agendada · Reunião realizada · Negociação · Última chance · Fechado *(is_won)* · Perdido *(is_lost)*.
- **Benefícios semeados:** Aposentadoria · BPC/LOAS · Auxílio-doença · Auxílio-acidente · Pensão por morte · Trabalhista · Outro.
- **Prioridades semeadas:** Alta *(weight 3)* · Média *(weight 2)* · Baixa *(weight 1)*.
- **Account-scoped:** todo recurso vive em `Current.account`. Na 2A todos os agents/admins veem todos os leads (sem filtro por SDR).

---

## File Structure

**Backend (novos, fork-safe):**
- `db/migrate/20260628000001_create_ramon_leads.rb` — 4 tabelas.
- `app/services/leads/seed_default_config_service.rb` — semeia stages/benefits/priorities de uma conta.
- `app/models/lead_stage.rb`, `app/models/benefit_type.rb`, `app/models/lead_priority.rb`, `app/models/lead.rb`.
- `app/policies/lead_policy.rb`.
- `app/controllers/api/v1/accounts/leads_controller.rb`.
- `app/controllers/api/v1/accounts/lead_config_controller.rb`.
- `app/views/api/v1/accounts/leads/{index,show,create,update}.json.jbuilder` + `_lead.json.jbuilder`.
- `app/views/api/v1/accounts/lead_config/index.json.jbuilder`.

**Backend (toques no core, aditivos):**
- `config/routes.rb` — `resources :leads` + `resource :lead_config` no bloco `accounts`.
- `app/models/account.rb` — `has_many` + `after_create_commit` de seed.

**Frontend (novos, fork-safe sob `ramon/` quando aplicável):**
- `app/javascript/dashboard/api/leads.js`, `app/javascript/dashboard/api/leadConfig.js`.
- `app/javascript/dashboard/store/modules/leads.js`, `.../store/modules/leadConfig.js`.
- `app/javascript/dashboard/routes/dashboard/ramon/components/kanban/KanbanBoard.vue`, `KanbanColumn.vue`, `LeadCard.vue`, `NewLeadModal.vue`.
- `app/javascript/dashboard/routes/dashboard/ramon/pages/Funil.vue`.
- `app/javascript/dashboard/routes/dashboard/conversation/KanbanView.vue` (wrapper do mundo Conversas).

**Frontend (toques no core, aditivos):**
- `app/javascript/dashboard/store/index.js` — registrar módulos `leads`, `leadConfig`.
- `app/javascript/dashboard/store/mutation-types.js` — tipos de Lead/LeadConfig.
- `app/javascript/dashboard/routes/dashboard/ramon/ramon.routes.js` — rota `ramon_funil`.
- `app/javascript/dashboard/routes/dashboard/ramon/components/IntranetSidebar.vue` — ligar item "Funil".
- `app/javascript/dashboard/routes/dashboard/conversation/conversation.routes.js` — rota `kanban_board`.
- `app/javascript/dashboard/components-next/sidebar/Sidebar.vue` — item "Kanban Board" no `menuItems`.
- `app/javascript/dashboard/i18n/locale/{pt_BR,en}/ramon.json` — chaves `RAMON.FUNIL.*`.

---

## Task 1: Migration — tabelas de Lead + config + serviço de seed

**Files:**
- Create: `db/migrate/20260628000001_create_ramon_leads.rb`
- Create: `app/services/leads/seed_default_config_service.rb`
- Test: `spec/services/leads/seed_default_config_service_spec.rb`
- Test: `spec/migrate/create_ramon_leads_spec.rb` (smoke via schema)

**Interfaces:**
- Produces: tabelas `lead_stages`, `benefit_types`, `lead_priorities`, `leads`. Serviço `Leads::SeedDefaultConfigService.new(account).perform` — idempotente (não duplica se já existir por nome).

- [ ] **Step 1: Escrever a migration**

```ruby
class CreateRamonLeads < ActiveRecord::Migration[7.0]
  def change
    create_table :lead_stages do |t|
      t.references :account, null: false, index: true
      t.string :name, null: false
      t.integer :position, null: false, default: 0
      t.boolean :is_won, null: false, default: false
      t.boolean :is_lost, null: false, default: false
      t.timestamps
    end
    add_index :lead_stages, [:account_id, :name], unique: true

    create_table :benefit_types do |t|
      t.references :account, null: false, index: true
      t.string :name, null: false
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :benefit_types, [:account_id, :name], unique: true

    create_table :lead_priorities do |t|
      t.references :account, null: false, index: true
      t.string :name, null: false
      t.integer :weight, null: false, default: 0
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :lead_priorities, [:account_id, :name], unique: true

    create_table :leads do |t|
      t.references :account, null: false, index: true
      t.references :contact, null: true, index: true
      t.references :conversation, null: true, index: true
      t.references :lead_stage, null: false, index: true
      t.references :benefit_type, null: true, index: true
      t.references :lead_priority, null: true, index: true
      t.string :name
      t.float :position, null: false, default: 0
      t.bigint :sdr_id
      t.bigint :closer_id
      t.string :lost_reason
      t.jsonb :custom_attributes, null: false, default: {}
      t.timestamps
    end
    add_index :leads, [:account_id, :lead_stage_id]

    reversible do |dir|
      dir.up do
        Account.find_each { |account| Leads::SeedDefaultConfigService.new(account).perform }
      end
    end
  end
end
```

- [ ] **Step 2: Escrever o serviço de seed**

```ruby
class Leads::SeedDefaultConfigService
  STAGES = [
    { name: 'Novo', is_won: false, is_lost: false },
    { name: 'Qualificação', is_won: false, is_lost: false },
    { name: 'Reunião agendada', is_won: false, is_lost: false },
    { name: 'Reunião realizada', is_won: false, is_lost: false },
    { name: 'Negociação', is_won: false, is_lost: false },
    { name: 'Última chance', is_won: false, is_lost: false },
    { name: 'Fechado', is_won: true, is_lost: false },
    { name: 'Perdido', is_won: false, is_lost: true }
  ].freeze

  BENEFITS = ['Aposentadoria', 'BPC/LOAS', 'Auxílio-doença', 'Auxílio-acidente',
              'Pensão por morte', 'Trabalhista', 'Outro'].freeze

  PRIORITIES = [
    { name: 'Alta', weight: 3 },
    { name: 'Média', weight: 2 },
    { name: 'Baixa', weight: 1 }
  ].freeze

  def initialize(account)
    @account = account
  end

  def perform
    STAGES.each_with_index do |attrs, i|
      @account.lead_stages.find_or_create_by!(name: attrs[:name]) do |s|
        s.position = i
        s.is_won = attrs[:is_won]
        s.is_lost = attrs[:is_lost]
      end
    end
    BENEFITS.each_with_index do |name, i|
      @account.benefit_types.find_or_create_by!(name: name) { |b| b.position = i }
    end
    PRIORITIES.each_with_index do |attrs, i|
      @account.lead_priorities.find_or_create_by!(name: attrs[:name]) do |p|
        p.weight = attrs[:weight]
        p.position = i
      end
    end
  end
end
```

> Nota: o serviço depende das associações `account.lead_stages/benefit_types/lead_priorities`, adicionadas na Task 4. Para rodar a migration isolada antes da Task 4, as associações já precisam existir — **execute a Task 4 (associações no `Account`) junto com esta migration** ou rode `Leads::SeedDefaultConfigService` só após a Task 4. O reviewer pode aprovar Task 1 com o seed exercitado pelo spec da Task 4.

- [ ] **Step 3: Rodar a migration**

Run: `bundle exec rails db:migrate`
Expected: cria as 4 tabelas; `db/schema.rb` atualizado.

- [ ] **Step 4: Spec do serviço de seed (após associações da Task 4 existirem)**

```ruby
require 'rails_helper'

RSpec.describe Leads::SeedDefaultConfigService do
  let(:account) { create(:account) }

  it 'semeia 8 etapas, 7 benefícios e 3 prioridades, idempotente' do
    described_class.new(account).perform
    described_class.new(account).perform # idempotência

    expect(account.lead_stages.count).to eq(8)
    expect(account.benefit_types.count).to eq(7)
    expect(account.lead_priorities.count).to eq(3)
    expect(account.lead_stages.find_by(name: 'Fechado')).to be_is_won
    expect(account.lead_stages.find_by(name: 'Perdido')).to be_is_lost
  end
end
```

- [ ] **Step 5: Rodar o spec**

Run: `bundle exec rspec spec/services/leads/seed_default_config_service_spec.rb`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add db/migrate/20260628000001_create_ramon_leads.rb db/schema.rb app/services/leads/seed_default_config_service.rb spec/services/leads/seed_default_config_service_spec.rb
git commit -m "ramon(fase2a): migration de leads + config + serviço de seed"
```

---

## Task 2: Models de configuração (LeadStage / BenefitType / LeadPriority)

**Files:**
- Create: `app/models/lead_stage.rb`, `app/models/benefit_type.rb`, `app/models/lead_priority.rb`
- Test: `spec/models/lead_stage_spec.rb`

**Interfaces:**
- Produces: `LeadStage` (`belongs_to :account`, `has_many :leads`, scope por `position`), `BenefitType`, `LeadPriority`. Validação de `name` único por conta.

- [ ] **Step 1: Spec de LeadStage (falha)**

```ruby
require 'rails_helper'

RSpec.describe LeadStage do
  let(:account) { create(:account) }

  it 'valida nome único por conta e ordena por position' do
    account.lead_stages.create!(name: 'Novo', position: 0)
    dup = account.lead_stages.build(name: 'Novo', position: 1)
    expect(dup).not_to be_valid

    account.lead_stages.create!(name: 'Fechado', position: 2)
    expect(account.lead_stages.pluck(:name).first).to eq('Novo')
  end
end
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `bundle exec rspec spec/models/lead_stage_spec.rb`
Expected: FAIL ("uninitialized constant LeadStage").

- [ ] **Step 3: Implementar os 3 models**

`app/models/lead_stage.rb`:
```ruby
class LeadStage < ApplicationRecord
  belongs_to :account
  has_many :leads, dependent: :restrict_with_exception

  validates :name, presence: true, uniqueness: { scope: :account_id }
  default_scope { order(:position) }
end
```

`app/models/benefit_type.rb`:
```ruby
class BenefitType < ApplicationRecord
  belongs_to :account
  has_many :leads, dependent: :nullify

  validates :name, presence: true, uniqueness: { scope: :account_id }
  default_scope { order(:position) }
end
```

`app/models/lead_priority.rb`:
```ruby
class LeadPriority < ApplicationRecord
  belongs_to :account
  has_many :leads, dependent: :nullify

  validates :name, presence: true, uniqueness: { scope: :account_id }
  default_scope { order(:position) }
end
```

- [ ] **Step 4: Rodar e ver passar**

Run: `bundle exec rspec spec/models/lead_stage_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/models/lead_stage.rb app/models/benefit_type.rb app/models/lead_priority.rb spec/models/lead_stage_spec.rb
git commit -m "ramon(fase2a): models de configuração do funil"
```

---

## Task 3: Model `Lead`

**Files:**
- Create: `app/models/lead.rb`
- Test: `spec/models/lead_spec.rb`
- Factory: `spec/factories/leads.rb` (+ factories de stage/benefit/priority se faltarem)

**Interfaces:**
- Consumes: `LeadStage`, `BenefitType`, `LeadPriority` (Task 2).
- Produces: `Lead` com `belongs_to :account`, `belongs_to :lead_stage`, opcionais `contact/conversation/benefit_type/lead_priority`, `sdr`/`closer` (User), ordenado por `position`. Método `push_event_data` (payload do card, reusado na Fase 2B).

- [ ] **Step 1: Factories**

`spec/factories/leads.rb`:
```ruby
FactoryBot.define do
  factory :lead_stage do
    account
    sequence(:name) { |n| "Etapa #{n}" }
    position { 0 }
  end

  factory :benefit_type do
    account
    sequence(:name) { |n| "Benefício #{n}" }
  end

  factory :lead_priority do
    account
    sequence(:name) { |n| "Prioridade #{n}" }
    weight { 1 }
  end

  factory :lead do
    account
    lead_stage { association :lead_stage, account: account }
    name { 'Maria das Dores' }
  end
end
```

- [ ] **Step 2: Spec do Lead (falha)**

```ruby
require 'rails_helper'

RSpec.describe Lead do
  let(:account) { create(:account) }

  it 'pertence a uma etapa e expõe push_event_data' do
    stage = create(:lead_stage, account: account, name: 'Novo')
    lead = create(:lead, account: account, lead_stage: stage, name: 'João')

    expect(lead.lead_stage).to eq(stage)
    expect(lead.push_event_data).to include(id: lead.id, name: 'João', lead_stage_id: stage.id)
  end

  it 'exige etapa' do
    lead = build(:lead, account: account, lead_stage: nil)
    expect(lead).not_to be_valid
  end
end
```

- [ ] **Step 3: Rodar e ver falhar**

Run: `bundle exec rspec spec/models/lead_spec.rb`
Expected: FAIL ("uninitialized constant Lead").

- [ ] **Step 4: Implementar o model**

```ruby
class Lead < ApplicationRecord
  belongs_to :account
  belongs_to :lead_stage
  belongs_to :contact, optional: true
  belongs_to :conversation, optional: true
  belongs_to :benefit_type, optional: true
  belongs_to :lead_priority, optional: true
  belongs_to :sdr, class_name: 'User', optional: true
  belongs_to :closer, class_name: 'User', optional: true

  validates :lead_stage, presence: true
  default_scope { order(:lead_stage_id, :position, :id) }

  def push_event_data
    {
      id: id,
      name: name,
      lead_stage_id: lead_stage_id,
      benefit_type_id: benefit_type_id,
      lead_priority_id: lead_priority_id,
      contact_id: contact_id,
      conversation_id: conversation_id,
      position: position
    }
  end
end
```

- [ ] **Step 5: Rodar e ver passar**

Run: `bundle exec rspec spec/models/lead_spec.rb`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/models/lead.rb spec/models/lead_spec.rb spec/factories/leads.rb
git commit -m "ramon(fase2a): model Lead"
```

---

## Task 4: Associações + seed automático no `Account` (core, aditivo)

**Files:**
- Modify: `app/models/account.rb` (adicionar associações + hook)
- Test: `spec/models/account_spec.rb` (adicionar exemplo) ou `spec/models/lead_stage_spec.rb`

**Interfaces:**
- Produces: `account.lead_stages`, `account.benefit_types`, `account.lead_priorities`, `account.leads`. Conta nova nasce semeada.

- [ ] **Step 1: Spec (falha) — conta nova vem semeada**

Adicionar em `spec/models/account_spec.rb`:
```ruby
  it 'semeia a configuração de leads ao criar a conta' do
    account = create(:account)
    expect(account.lead_stages.count).to eq(8)
    expect(account.benefit_types.count).to eq(7)
    expect(account.lead_priorities.count).to eq(3)
  end
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `bundle exec rspec spec/models/account_spec.rb -e "semeia a configuração de leads"`
Expected: FAIL (associação inexistente / contagem 0).

- [ ] **Step 3: Editar `app/models/account.rb`**

Adicionar junto às demais `has_many` (procurar o bloco de associações, ex.: perto de `has_many :labels`):
```ruby
  has_many :lead_stages, dependent: :destroy_async
  has_many :benefit_types, dependent: :destroy_async
  has_many :lead_priorities, dependent: :destroy_async
  has_many :leads, dependent: :destroy_async
```
Adicionar o hook (junto aos outros `after_create_commit` do model):
```ruby
  after_create_commit :seed_lead_config

  def seed_lead_config
    Leads::SeedDefaultConfigService.new(self).perform
  end
```

- [ ] **Step 4: Rodar e ver passar**

Run: `bundle exec rspec spec/models/account_spec.rb -e "semeia a configuração de leads"`
Expected: PASS. Rodar também a Task 1 Step 4 (`seed_default_config_service_spec`) → PASS.

- [ ] **Step 5: Registrar ponto de fork + commit**

Adicionar entrada em `docs/FORK-PONTOS-DE-REGISTRO.md` (model `Account`: associações + `seed_lead_config`).
```bash
git add app/models/account.rb spec/models/account_spec.rb docs/FORK-PONTOS-DE-REGISTRO.md
git commit -m "ramon(fase2a): Account semeia config de leads + associações"
```

---

## Task 5: API de leitura da config (`lead_config#index`)

**Files:**
- Create: `app/controllers/api/v1/accounts/lead_config_controller.rb`
- Create: `app/views/api/v1/accounts/lead_config/index.json.jbuilder`
- Modify: `config/routes.rb` (core, aditivo)
- Test: `spec/controllers/api/v1/accounts/lead_config_controller_spec.rb`

**Interfaces:**
- Produces: `GET /api/v1/accounts/:account_id/lead_config` → `{ stages: [...], benefit_types: [...], priorities: [...] }`.

- [ ] **Step 1: Spec (falha)**

```ruby
require 'rails_helper'

RSpec.describe 'Lead Config API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }

  it 'retorna stages, benefit_types e priorities da conta' do
    get "/api/v1/accounts/#{account.id}/lead_config",
        headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    body = response.parsed_body
    expect(body['stages'].size).to eq(8)
    expect(body['benefit_types'].size).to eq(7)
    expect(body['priorities'].size).to eq(3)
  end
end
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `bundle exec rspec spec/controllers/api/v1/accounts/lead_config_controller_spec.rb`
Expected: FAIL (rota inexistente → 404).

- [ ] **Step 3: Rota**

Em `config/routes.rb`, dentro do bloco `namespace :accounts do` (ao lado de `resources :labels`):
```ruby
      resource :lead_config, only: [:show]
```
> `resource` (singular) gera `GET /lead_config` mapeado para `#show`. Use a action `show` no controller (não `index`).

- [ ] **Step 4: Controller + jbuilder**

`app/controllers/api/v1/accounts/lead_config_controller.rb`:
```ruby
class Api::V1::Accounts::LeadConfigController < Api::V1::Accounts::BaseController
  before_action :current_account

  def show
    @stages = Current.account.lead_stages
    @benefit_types = Current.account.benefit_types
    @priorities = Current.account.lead_priorities
  end
end
```

`app/views/api/v1/accounts/lead_config/show.json.jbuilder`:
```ruby
json.stages do
  json.array! @stages do |stage|
    json.id stage.id
    json.name stage.name
    json.position stage.position
    json.is_won stage.is_won
    json.is_lost stage.is_lost
  end
end
json.benefit_types do
  json.array! @benefit_types do |bt|
    json.id bt.id
    json.name bt.name
    json.position bt.position
  end
end
json.priorities do
  json.array! @priorities do |p|
    json.id p.id
    json.name p.name
    json.weight p.weight
    json.position p.position
  end
end
```
> Ajustar o spec do Step 1 para `show` (a rota singular usa `#show`); a URL `GET /lead_config` permanece.

- [ ] **Step 5: Rodar e ver passar**

Run: `bundle exec rspec spec/controllers/api/v1/accounts/lead_config_controller_spec.rb`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add config/routes.rb app/controllers/api/v1/accounts/lead_config_controller.rb app/views/api/v1/accounts/lead_config/ spec/controllers/api/v1/accounts/lead_config_controller_spec.rb docs/FORK-PONTOS-DE-REGISTRO.md
git commit -m "ramon(fase2a): API de leitura da config do funil"
```

---

## Task 6: API CRUD de `leads`

**Files:**
- Create: `app/controllers/api/v1/accounts/leads_controller.rb`
- Create: `app/policies/lead_policy.rb`
- Create: `app/views/api/v1/accounts/leads/{index,show,create,update}.json.jbuilder` + `_lead.json.jbuilder`
- Modify: `config/routes.rb` (core, aditivo)
- Test: `spec/controllers/api/v1/accounts/leads_controller_spec.rb`

**Interfaces:**
- Consumes: `Lead` (Task 3), `LeadPolicy`.
- Produces: REST `leads` (index/show/create/update/destroy). `update` aceita `{ lead_stage_id, position, ... }` (é o endpoint de "mover" no drag&drop). Payload do card via `_lead.json.jbuilder`.

- [ ] **Step 1: Spec (falha)**

```ruby
require 'rails_helper'

RSpec.describe 'Leads API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:novo) { account.lead_stages.find_by(name: 'Novo') }
  let(:qualif) { account.lead_stages.find_by(name: 'Qualificação') }

  it 'cria um lead na etapa Novo' do
    post "/api/v1/accounts/#{account.id}/leads",
         params: { name: 'João', lead_stage_id: novo.id },
         headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    expect(response.parsed_body['name']).to eq('João')
    expect(account.leads.count).to eq(1)
  end

  it 'move um lead de etapa via update' do
    lead = create(:lead, account: account, lead_stage: novo, name: 'Ana')
    patch "/api/v1/accounts/#{account.id}/leads/#{lead.id}",
          params: { lead_stage_id: qualif.id, position: 1.5 },
          headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    expect(lead.reload.lead_stage).to eq(qualif)
    expect(lead.position).to eq(1.5)
  end

  it 'lista os leads da conta' do
    create(:lead, account: account, lead_stage: novo)
    get "/api/v1/accounts/#{account.id}/leads",
        headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['payload'].size).to eq(1)
  end
end
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `bundle exec rspec spec/controllers/api/v1/accounts/leads_controller_spec.rb`
Expected: FAIL (rota/controller inexistentes → 404).

- [ ] **Step 3: Rota + policy**

`config/routes.rb` (ao lado de `resources :labels`):
```ruby
      resources :leads
```

`app/policies/lead_policy.rb`:
```ruby
class LeadPolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    true
  end

  def create?
    true
  end

  def update?
    true
  end

  def destroy?
    @account_user.administrator?
  end
end
```
> Espelha o nível de acesso de `LabelPolicy`. Na 2A "todos veem tudo"; `destroy` restrito a admin (operação de uma pessoa só → ela é admin).

- [ ] **Step 4: Controller**

```ruby
class Api::V1::Accounts::LeadsController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :fetch_lead, except: [:index, :create]
  before_action :check_authorization

  def index
    @leads = policy_scope(Current.account.leads)
  end

  def show; end

  def create
    @lead = Current.account.leads.create!(permitted_params)
  end

  def update
    @lead.update!(permitted_params)
  end

  def destroy
    @lead.destroy!
    head :ok
  end

  private

  def fetch_lead
    @lead = Current.account.leads.find(params[:id])
  end

  def permitted_params
    params.permit(:name, :lead_stage_id, :benefit_type_id, :lead_priority_id,
                  :contact_id, :conversation_id, :sdr_id, :closer_id,
                  :position, :lost_reason)
  end
end
```

- [ ] **Step 5: jbuilders**

`app/views/api/v1/accounts/leads/_lead.json.jbuilder`:
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
```

`index.json.jbuilder`:
```ruby
json.payload do
  json.array! @leads, partial: 'lead', as: :lead
end
```

`show.json.jbuilder`, `create.json.jbuilder`, `update.json.jbuilder` (idênticos):
```ruby
json.partial! 'lead', lead: @lead
```

- [ ] **Step 6: Rodar e ver passar**

Run: `bundle exec rspec spec/controllers/api/v1/accounts/leads_controller_spec.rb`
Expected: PASS (3 exemplos).

- [ ] **Step 7: Commit**

```bash
git add config/routes.rb app/controllers/api/v1/accounts/leads_controller.rb app/policies/lead_policy.rb app/views/api/v1/accounts/leads/ spec/controllers/api/v1/accounts/leads_controller_spec.rb docs/FORK-PONTOS-DE-REGISTRO.md
git commit -m "ramon(fase2a): API CRUD de leads"
```

---

## Task 7: API clients + stores Vuex (`leads`, `leadConfig`)

**Files:**
- Create: `app/javascript/dashboard/api/leads.js`, `app/javascript/dashboard/api/leadConfig.js`
- Create: `app/javascript/dashboard/store/modules/leads.js`, `.../store/modules/leadConfig.js`
- Modify: `app/javascript/dashboard/store/index.js`, `.../store/mutation-types.js` (core, aditivo)
- Test: `app/javascript/dashboard/store/modules/specs/leads/actions.spec.js`

**Interfaces:**
- Produces: getters `leads/getLeads`, `leads/getLeadsByStage(stageId)`; actions `leads/get`, `leads/create`, `leads/update`, `leads/move`, `leads/upsert` (esta última reusada na Fase 2B/realtime). `leadConfig/get` + getters `leadConfig/getStages`, `getBenefitTypes`, `getPriorities`.

- [ ] **Step 1: API clients**

`app/javascript/dashboard/api/leads.js`:
```javascript
import ApiClient from './ApiClient';

class LeadsAPI extends ApiClient {
  constructor() {
    super('leads', { accountScoped: true });
  }
}

export default new LeadsAPI();
```

`app/javascript/dashboard/api/leadConfig.js`:
```javascript
import ApiClient from './ApiClient';

class LeadConfigAPI extends ApiClient {
  constructor() {
    super('lead_config', { accountScoped: true });
  }
}

export default new LeadConfigAPI();
```

- [ ] **Step 2: Mutation types (core, aditivo)**

Em `app/javascript/dashboard/store/mutation-types.js`, adicionar um bloco:
```javascript
  // Ramon — Leads
  SET_LEAD_UI_FLAG: 'SET_LEAD_UI_FLAG',
  SET_LEADS: 'SET_LEADS',
  ADD_LEAD: 'ADD_LEAD',
  EDIT_LEAD: 'EDIT_LEAD',
  DELETE_LEAD: 'DELETE_LEAD',
  SET_LEAD_CONFIG: 'SET_LEAD_CONFIG',
```
> Conferir a sintaxe real do arquivo (objeto único `export default { ... }`); inserir as chaves no mesmo formato das vizinhas.

- [ ] **Step 3: Spec do store (falha)**

`app/javascript/dashboard/store/modules/specs/leads/actions.spec.js`:
```javascript
import axios from 'axios';
import { actions } from '../../leads';
import types from '../../../mutation-types';

vi.mock('axios');

describe('leads actions', () => {
  it('get faz commit de SET_LEADS', async () => {
    axios.get.mockResolvedValue({ data: { payload: [{ id: 1, name: 'João' }] } });
    const commit = vi.fn();
    await actions.get({ commit });
    expect(commit).toHaveBeenCalledWith(types.SET_LEAD_UI_FLAG, { isFetching: true });
    expect(commit).toHaveBeenCalledWith(types.SET_LEADS, [{ id: 1, name: 'João' }]);
  });
});
```

- [ ] **Step 4: Rodar e ver falhar**

Run: `pnpm test app/javascript/dashboard/store/modules/specs/leads/actions.spec.js`
Expected: FAIL (módulo `../../leads` inexistente).
> Se o runner do projeto for `jest`, usar `pnpm jest <path>` e `jest.fn()`/`jest.mock`. Confirmar em `package.json` antes de rodar.

- [ ] **Step 5: Store `leads`**

`app/javascript/dashboard/store/modules/leads.js`:
```javascript
import * as MutationHelpers from 'shared/helpers/vuex/mutationHelpers';
import types from '../mutation-types';
import LeadsAPI from '../../api/leads';

export const state = {
  records: [],
  uiFlags: { isFetching: false, isCreating: false, isUpdating: false, isDeleting: false },
};

export const getters = {
  getLeads(_state) {
    return _state.records;
  },
  getLeadsByStage: _state => stageId =>
    _state.records
      .filter(lead => lead.lead_stage_id === stageId)
      .sort((a, b) => a.position - b.position),
  getUIFlags(_state) {
    return _state.uiFlags;
  },
};

export const actions = {
  get: async ({ commit }) => {
    commit(types.SET_LEAD_UI_FLAG, { isFetching: true });
    try {
      const response = await LeadsAPI.get();
      commit(types.SET_LEADS, response.data.payload);
    } finally {
      commit(types.SET_LEAD_UI_FLAG, { isFetching: false });
    }
  },
  create: async ({ commit }, payload) => {
    commit(types.SET_LEAD_UI_FLAG, { isCreating: true });
    try {
      const response = await LeadsAPI.create(payload);
      commit(types.ADD_LEAD, response.data);
      return response.data;
    } finally {
      commit(types.SET_LEAD_UI_FLAG, { isCreating: false });
    }
  },
  update: async ({ commit }, { id, ...payload }) => {
    const response = await LeadsAPI.update(id, payload);
    commit(types.EDIT_LEAD, response.data);
    return response.data;
  },
  move: async ({ commit }, { id, leadStageId, position }) => {
    const response = await LeadsAPI.update(id, { lead_stage_id: leadStageId, position });
    commit(types.EDIT_LEAD, response.data);
  },
  upsert: ({ commit }, lead) => {
    commit(types.EDIT_LEAD, lead);
  },
  delete: async ({ commit }, id) => {
    await LeadsAPI.delete(id);
    commit(types.DELETE_LEAD, id);
  },
};

export const mutations = {
  [types.SET_LEAD_UI_FLAG](_state, data) {
    _state.uiFlags = { ..._state.uiFlags, ...data };
  },
  [types.SET_LEADS]: MutationHelpers.set,
  [types.ADD_LEAD]: MutationHelpers.create,
  [types.EDIT_LEAD]: MutationHelpers.setSingleRecord,
  [types.DELETE_LEAD]: MutationHelpers.destroy,
};

export default { namespaced: true, state, getters, actions, mutations };
```
> `EDIT_LEAD` usa `setSingleRecord` (upsert) para o realtime da Fase 2B funcionar sem alteração.

- [ ] **Step 6: Store `leadConfig`**

`app/javascript/dashboard/store/modules/leadConfig.js`:
```javascript
import types from '../mutation-types';
import LeadConfigAPI from '../../api/leadConfig';

export const state = {
  stages: [],
  benefitTypes: [],
  priorities: [],
  uiFlags: { isFetching: false },
};

export const getters = {
  getStages: _state => _state.stages,
  getBenefitTypes: _state => _state.benefitTypes,
  getPriorities: _state => _state.priorities,
};

export const actions = {
  get: async ({ commit }) => {
    commit(types.SET_LEAD_UI_FLAG, { isFetching: true });
    try {
      const response = await LeadConfigAPI.get();
      commit(types.SET_LEAD_CONFIG, response.data);
    } finally {
      commit(types.SET_LEAD_UI_FLAG, { isFetching: false });
    }
  },
};

export const mutations = {
  [types.SET_LEAD_UI_FLAG](_state, data) {
    _state.uiFlags = { ..._state.uiFlags, ...data };
  },
  [types.SET_LEAD_CONFIG](_state, data) {
    _state.stages = data.stages || [];
    _state.benefitTypes = data.benefit_types || [];
    _state.priorities = data.priorities || [];
  },
};

export default { namespaced: true, state, getters, actions, mutations };
```

- [ ] **Step 7: Registrar no `store/index.js`**

Adicionar imports (perto de `import labels from './modules/labels';`):
```javascript
import leads from './modules/leads';
import leadConfig from './modules/leadConfig';
```
E no objeto `modules: { ... }`:
```javascript
    leads,
    leadConfig,
```

- [ ] **Step 8: Rodar e ver passar**

Run: `pnpm test app/javascript/dashboard/store/modules/specs/leads/actions.spec.js`
Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add app/javascript/dashboard/api/leads.js app/javascript/dashboard/api/leadConfig.js app/javascript/dashboard/store/modules/leads.js app/javascript/dashboard/store/modules/leadConfig.js app/javascript/dashboard/store/index.js app/javascript/dashboard/store/mutation-types.js app/javascript/dashboard/store/modules/specs/leads/ docs/FORK-PONTOS-DE-REGISTRO.md
git commit -m "ramon(fase2a): stores Vuex de leads e config"
```

---

## Task 8: Componentes do board (`KanbanBoard`, `KanbanColumn`, `LeadCard`)

**Files:**
- Create: `app/javascript/dashboard/routes/dashboard/ramon/components/kanban/KanbanBoard.vue`
- Create: `.../kanban/KanbanColumn.vue`
- Create: `.../kanban/LeadCard.vue`

**Interfaces:**
- Consumes: `leads/getLeadsByStage`, `leadConfig/getStages|getBenefitTypes|getPriorities`, `leads/move`.
- Produces: `<KanbanBoard>` autocontido — busca config+leads no `onMounted`, renderiza uma coluna por etapa, drag&drop persiste via `leads/move`. Emite `@new-lead` (botão "Novo lead") e `@open-conversation(conversationId)`.

> **Calibração visual:** as classes Tailwind abaixo são o ponto de partida fiel ao mock (`design-ref/screenshots/02-kanban.png`): coluna `#17120d`, card `#1f1812`, pílula de prioridade em bronze. Ajustar finos contra o screenshot durante a execução; **não introduzir segunda cor**.

- [ ] **Step 1: `LeadCard.vue`**

```vue
<script setup>
import { computed } from 'vue';

const props = defineProps({
  lead: { type: Object, required: true },
  benefitTypes: { type: Array, default: () => [] },
  priorities: { type: Array, default: () => [] },
});
const emit = defineEmits(['open-conversation']);

const benefitName = computed(
  () => props.benefitTypes.find(b => b.id === props.lead.benefit_type_id)?.name
);
const priorityName = computed(
  () => props.priorities.find(p => p.id === props.lead.lead_priority_id)?.name
);
</script>

<template>
  <div class="p-3 mb-2 rounded-xl bg-n-solid-2 border border-n-weak">
    <div class="flex items-start justify-between gap-2">
      <p class="text-sm font-medium text-n-slate-12">{{ lead.name }}</p>
      <button
        v-if="lead.conversation_id"
        :title="$t('RAMON.FUNIL.OPEN_CONVERSATION')"
        class="text-n-slate-10 hover:text-n-iris-11"
        @click="emit('open-conversation', lead.conversation_id)"
      >
        <span class="i-lucide-message-square size-4" />
      </button>
    </div>
    <span v-if="benefitName" class="inline-block mt-2 px-2 py-0.5 text-[11px] rounded-full bg-n-alpha-2 text-n-slate-11">
      {{ benefitName }}
    </span>
    <div v-if="priorityName" class="mt-2">
      <p class="text-[9px] tracking-widest uppercase text-n-slate-9">{{ $t('RAMON.FUNIL.PRIORITY') }}</p>
      <span class="inline-flex items-center gap-1 mt-1 px-2 py-0.5 text-[11px] rounded-full bg-n-iris-9 text-white">
        <span class="i-lucide-flag size-3" />{{ priorityName }}
      </span>
    </div>
  </div>
</template>
```

- [ ] **Step 2: `KanbanColumn.vue`**

```vue
<script setup>
import Draggable from 'vuedraggable';
import LeadCard from './LeadCard.vue';

defineProps({
  stage: { type: Object, required: true },
  leads: { type: Array, default: () => [] },
  benefitTypes: { type: Array, default: () => [] },
  priorities: { type: Array, default: () => [] },
});
const emit = defineEmits(['move', 'open-conversation']);

const onChange = stageId => evt => {
  const added = evt.added || evt.moved;
  if (!added) return;
  emit('move', { id: added.element.id, leadStageId: stageId, newIndex: added.newIndex });
};
</script>

<template>
  <div class="flex flex-col w-72 flex-shrink-0 rounded-xl bg-[#17120d] border border-n-weak">
    <div class="flex items-center justify-between px-3 py-2">
      <span class="text-sm text-n-slate-12">{{ stage.name }}</span>
      <span class="text-xs text-n-slate-9">{{ leads.length }}</span>
    </div>
    <Draggable
      :model-value="leads"
      group="leads"
      item-key="id"
      class="flex-1 px-2 pb-2 min-h-[120px]"
      @change="onChange(stage.id)"
    >
      <template #item="{ element }">
        <LeadCard
          :lead="element"
          :benefit-types="benefitTypes"
          :priorities="priorities"
          @open-conversation="id => emit('open-conversation', id)"
        />
      </template>
    </Draggable>
  </div>
</template>
```

- [ ] **Step 3: `KanbanBoard.vue`**

```vue
<script setup>
import { computed, onMounted } from 'vue';
import { useStore, useStoreGetters } from 'dashboard/composables/store';
import KanbanColumn from './KanbanColumn.vue';

const emit = defineEmits(['new-lead', 'open-conversation']);
const store = useStore();
const getters = useStoreGetters();

const stages = computed(() => getters['leadConfig/getStages'].value);
const benefitTypes = computed(() => getters['leadConfig/getBenefitTypes'].value);
const priorities = computed(() => getters['leadConfig/getPriorities'].value);
const leadsByStage = stageId => getters['leads/getLeadsByStage'].value(stageId);

const onMove = ({ id, leadStageId, newIndex }) => {
  store.dispatch('leads/move', { id, leadStageId, position: newIndex });
};

onMounted(() => {
  store.dispatch('leadConfig/get');
  store.dispatch('leads/get');
});
</script>

<template>
  <div class="flex flex-col h-full">
    <div class="flex items-center justify-between px-4 py-3">
      <h1 class="text-xl font-cormorant text-n-slate-12">{{ $t('RAMON.FUNIL.TITLE') }}</h1>
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
        :benefit-types="benefitTypes"
        :priorities="priorities"
        @move="onMove"
        @open-conversation="id => emit('open-conversation', id)"
      />
    </div>
  </div>
</template>
```

- [ ] **Step 4: Verificação manual (sem teste unitário de componente nesta tarefa)**

A verificação real é visual, nas Tasks 9/10 (com rota montada). Aqui só garantir build:
Run: `pnpm exec vue-tsc --noEmit` *(se o projeto usar; senão confiar no build da Task 10)*
Expected: sem erro de sintaxe nos 3 componentes.

- [ ] **Step 5: Commit**

```bash
git add app/javascript/dashboard/routes/dashboard/ramon/components/kanban/
git commit -m "ramon(fase2a): componentes do board kanban"
```

---

## Task 9: Página Funil (mundo Intranet) + rota + sidebar

**Files:**
- Create: `app/javascript/dashboard/routes/dashboard/ramon/pages/Funil.vue`
- Create: `app/javascript/dashboard/routes/dashboard/ramon/components/kanban/NewLeadModal.vue`
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/ramon.routes.js`
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/components/IntranetSidebar.vue`
- Modify: `app/javascript/dashboard/i18n/locale/{pt_BR,en}/ramon.json`

**Interfaces:**
- Consumes: `KanbanBoard` (Task 8), `leadConfig/getStages|getBenefitTypes`, `leads/create`.
- Produces: rota nomeada `ramon_funil` (`meta.world = 'intranet'`), página que monta o board + modal de novo lead.

- [ ] **Step 1: `NewLeadModal.vue`**

```vue
<script setup>
import { ref, computed } from 'vue';
import { useStore, useStoreGetters } from 'dashboard/composables/store';

const emit = defineEmits(['close', 'created']);
const store = useStore();
const getters = useStoreGetters();

const name = ref('');
const benefitTypeId = ref(null);
const stages = computed(() => getters['leadConfig/getStages'].value);
const benefitTypes = computed(() => getters['leadConfig/getBenefitTypes'].value);

const submit = async () => {
  const firstStage = stages.value[0];
  if (!name.value || !firstStage) return;
  const lead = await store.dispatch('leads/create', {
    name: name.value,
    lead_stage_id: firstStage.id,
    benefit_type_id: benefitTypeId.value,
  });
  emit('created', lead);
  emit('close');
};
</script>

<template>
  <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/50" @click.self="emit('close')">
    <div class="w-96 p-5 rounded-2xl bg-n-solid-1 border border-n-weak">
      <h2 class="mb-4 text-lg font-cormorant text-n-slate-12">{{ $t('RAMON.FUNIL.NEW_LEAD') }}</h2>
      <label class="block mb-1 text-xs text-n-slate-10">{{ $t('RAMON.FUNIL.LEAD_NAME') }}</label>
      <input v-model="name" class="w-full px-3 py-2 mb-3 text-sm rounded-lg bg-n-alpha-1 text-n-slate-12 border border-n-weak" />
      <label class="block mb-1 text-xs text-n-slate-10">{{ $t('RAMON.FUNIL.BENEFIT') }}</label>
      <select v-model="benefitTypeId" class="w-full px-3 py-2 mb-4 text-sm rounded-lg bg-n-alpha-1 text-n-slate-12 border border-n-weak">
        <option :value="null">—</option>
        <option v-for="b in benefitTypes" :key="b.id" :value="b.id">{{ b.name }}</option>
      </select>
      <div class="flex justify-end gap-2">
        <button class="px-3 py-1.5 text-sm text-n-slate-11" @click="emit('close')">{{ $t('RAMON.FUNIL.CANCEL') }}</button>
        <button class="px-3 py-1.5 text-sm rounded-lg bg-n-iris-9 text-white" @click="submit">{{ $t('RAMON.FUNIL.SAVE') }}</button>
      </div>
    </div>
  </div>
</template>
```

- [ ] **Step 2: `Funil.vue`**

```vue
<script setup>
import { ref } from 'vue';
import { useRouter } from 'vue-router';
import { useAccount } from 'dashboard/composables/useAccount';
import KanbanBoard from '../components/kanban/KanbanBoard.vue';
import NewLeadModal from '../components/kanban/NewLeadModal.vue';

const router = useRouter();
const { accountScopedRoute } = useAccount();
const showModal = ref(false);

const openConversation = conversationId => {
  router.push({ name: 'conversation_through_conversation', params: { conversationId } });
};
</script>

<template>
  <div class="flex flex-col w-full h-full bg-n-background">
    <KanbanBoard @new-lead="showModal = true" @open-conversation="openConversation" />
    <NewLeadModal v-if="showModal" @close="showModal = false" />
  </div>
</template>
```
> Conferir o `name` real da rota de conversa individual no fork (`rg "name: 'conversation" app/javascript/dashboard/routes/dashboard/conversation`). Ajustar `openConversation` ao nome correto.

- [ ] **Step 3: Rota `ramon_funil`**

Em `ramon.routes.js`, adicionar ao array (irmã de `ramon_index`, achatada — não aninhar):
```javascript
  {
    path: 'funil',
    name: 'ramon_funil',
    meta: { permissions: ['administrator', 'agent'], world: 'intranet' },
    component: () => import('./pages/Funil.vue'),
  },
```
> Conferir o formato exato das rotas existentes (`ramon_index`, `ramon_external_shortcuts`) e o prefixo de `path` para casar com `/ramon/funil`.

- [ ] **Step 4: Ligar o item "Funil" na `IntranetSidebar.vue`**

Trocar a linha 14 (`{ key: 'funil', ... soon: true }`) por:
```javascript
      { key: 'funil', label: t('RAMON.NAV.FUNIL'), icon: 'i-lucide-filter', to: accountScopedRoute('ramon_funil') },
```

- [ ] **Step 5: i18n**

Adicionar em `pt_BR/ramon.json` (sob `RAMON`):
```json
"FUNIL": {
  "TITLE": "Funil de Leads",
  "NEW_LEAD": "Novo lead",
  "LEAD_NAME": "Nome do lead",
  "BENEFIT": "Tipo de benefício",
  "PRIORITY": "Prioridade",
  "OPEN_CONVERSATION": "Abrir conversa",
  "CANCEL": "Cancelar",
  "SAVE": "Salvar"
}
```
Espelhar em `en/ramon.json` (mesmas chaves, em inglês).

- [ ] **Step 6: Verificação manual**

Build + abrir `/app/accounts/<id>/ramon/funil` no mundo Intranet:
Run: `pnpm exec vite build` *(ou o script de build do projeto)*
Expected: build sem erro; rota monta o board com as 8 colunas; "Novo lead" cria card na coluna "Novo".

- [ ] **Step 7: Commit**

```bash
git add app/javascript/dashboard/routes/dashboard/ramon/pages/Funil.vue app/javascript/dashboard/routes/dashboard/ramon/components/kanban/NewLeadModal.vue app/javascript/dashboard/routes/dashboard/ramon/ramon.routes.js app/javascript/dashboard/routes/dashboard/ramon/components/IntranetSidebar.vue app/javascript/dashboard/i18n/locale/pt_BR/ramon.json app/javascript/dashboard/i18n/locale/en/ramon.json
git commit -m "ramon(fase2a): página Funil no mundo Intranet"
```

---

## Task 10: Kanban Board no mundo Conversas + item de menu

**Files:**
- Create: `app/javascript/dashboard/routes/dashboard/conversation/KanbanView.vue`
- Modify: `app/javascript/dashboard/routes/dashboard/conversation/conversation.routes.js`
- Modify: `app/javascript/dashboard/components-next/sidebar/Sidebar.vue` (core — `menuItems`)
- Modify: `app/javascript/dashboard/i18n/locale/{pt_BR,en}/*` (rótulo do menu)

**Interfaces:**
- Consumes: `KanbanBoard` (Task 8) — **mesmo componente e mesmo store** do Funil → espelho automático na mesma aba.
- Produces: rota `kanban_board` no mundo Conversas + item no `menuItems`.

- [ ] **Step 1: `KanbanView.vue`**

```vue
<script setup>
import { useRouter } from 'vue-router';
import KanbanBoard from '../ramon/components/kanban/KanbanBoard.vue';

const router = useRouter();
const openConversation = conversationId => {
  router.push({ name: 'conversation_through_conversation', params: { conversationId } });
};
</script>

<template>
  <div class="flex flex-col w-full h-full bg-n-background">
    <KanbanBoard @open-conversation="openConversation" />
  </div>
</template>
```
> Sem botão "Novo lead" aqui (criação fica no Funil). Caminho de import relativo a `conversation/` → `../ramon/components/kanban/KanbanBoard.vue`. Confirmar o `name` da rota de conversa.

- [ ] **Step 2: Rota `kanban_board`**

Em `conversation.routes.js`, adicionar uma rota irmã das de conversa (conferir o padrão e o `frontendURL`/prefixo reais do arquivo):
```javascript
  {
    path: 'kanban',
    name: 'kanban_board',
    component: () => import('./KanbanView.vue'),
    meta: { permissions: ['administrator', 'agent'] },
  },
```

- [ ] **Step 3: Item "Kanban Board" no `menuItems` do `Sidebar.vue`**

No computed `menuItems` (≈ linha 316-847), adicionar uma entrada logo após o item de Conversas (`Conversation`, ≈ linha 436), no mesmo formato dos vizinhos:
```javascript
        {
          name: 'kanban_board',
          label: t('SIDEBAR.KANBAN_BOARD'),
          icon: 'i-lucide-columns-3',
          to: accountScopedRoute('kanban_board'),
          activeOn: ['kanban_board'],
        },
```
> Copiar a forma EXATA de um item vizinho (alguns usam `key`, `component`, `children` — manter a mesma estrutura para não quebrar o array).

- [ ] **Step 4: i18n do menu**

Adicionar `SIDEBAR.KANBAN_BOARD` em `pt_BR/settings.json` (= "Kanban Board") e `en/settings.json` (= "Kanban Board"). Conferir o arquivo onde `SIDEBAR.*` é definido (mesmo de `SIDEBAR.RAMON`).

- [ ] **Step 5: Verificação manual (espelho)**

Build + smoke do espelho:
Run: `pnpm exec vite build`
Expected: build ok. Abrir o Kanban no mundo Conversas e o Funil no mundo Intranet na mesma aba; mover um card num e ver refletir no outro ao navegar (mesmo store). Botão "abrir conversa" leva à conversa nativa.

- [ ] **Step 6: Registrar pontos de fork + commit**

Atualizar `docs/FORK-PONTOS-DE-REGISTRO.md` (Sidebar.vue menuItems, conversation.routes.js, settings.json SIDEBAR.KANBAN_BOARD).
```bash
git add app/javascript/dashboard/routes/dashboard/conversation/KanbanView.vue app/javascript/dashboard/routes/dashboard/conversation/conversation.routes.js app/javascript/dashboard/components-next/sidebar/Sidebar.vue app/javascript/dashboard/i18n/locale/pt_BR/settings.json app/javascript/dashboard/i18n/locale/en/settings.json docs/FORK-PONTOS-DE-REGISTRO.md
git commit -m "ramon(fase2a): Kanban Board no mundo Conversas (board compartilhado)"
```

---

## Self-Review

**Spec coverage (vs decisões travadas):**
- Lead nativo no Postgres da VPS → Tasks 1-4. ✓
- Board Funil (Intranet) + Kanban (Conversas) compartilhando store → Tasks 8-10. ✓
- Drag&drop persistindo etapa/posição → Task 8 (`onChange`→`leads/move`) + Task 6 (`update`). ✓
- Criar lead manual → Tasks 9 (modal) + 6 (create). ✓
- "Abrir conversa" nativa → Tasks 8/9/10 (emit `open-conversation`). ✓
- Listas (etapas/benefícios/prioridades) como tabelas semeadas (não enum) → Tasks 1-2-5. ✓ (prepara 2D).
- `custom_attributes` jsonb provisionado → Task 1. ✓ (prepara 2E).
- Começa vazio (leads) → nenhum seed de `leads`. ✓
- Todos veem todos / destroy só admin → Task 6 (policy). ✓
- Marca bronze, sem segunda cor, Cormorant, sem emoji → Global Constraints + notas de calibração na Task 8. ✓

**Fora de escopo (próximas fatias, propositalmente ausentes):** realtime/WS e auto-criação (2B); espelho etapa↔label (2C); UI de CRUD das listas (2D); campos custom (2E). O schema já comporta todas sem re-migração.

**Pontos a confirmar na execução (não bloqueiam o plano):**
1. Runner de teste JS (`pnpm test` vitest vs `jest`) — conferir `package.json` antes da Task 7.
2. Nome real da rota de conversa individual (`conversation_through_conversation`?) — `rg "name: 'conversation"`.
3. Formato exato de um item vizinho no `menuItems` do `Sidebar.vue` (Task 10) e das rotas em `conversation.routes.js`/`ramon.routes.js`.
4. Arquivo i18n onde `SIDEBAR.*` mora (mesmo de `SIDEBAR.RAMON`).
5. `ApplicationPolicy` expõe `@account_user` (Task 6) — confirmar em `LabelPolicy`/`app/policies/application_policy.rb`.

**Placeholder scan:** sem TODO/TBD; todo passo com código ou comando concreto. As notas `>` são confirmações de caminho do fork (o design-ref exige inspecionar o repo real antes de criar/renomear), não placeholders de implementação.
