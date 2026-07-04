# PR A — Cadência + Kanban (Centro de Operações v2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Dar ao CRM a camada de cadência (tarefas com prazo, apodrecimento visual, motivo de perda, datas de ciclo, forecast ponderado) e elevar o Kanban ao nível dos CRMs de referência (Smart Views, filtros, criação completa com dedup).

**Architecture:** Uma migração única adiciona `lead_tasks`, `lost_reasons` e colunas de cadência em `lead_stages`/`leads`; callbacks no `Lead` mantêm `stage_entered_at`/`won_at`/`lost_at`; API REST nested para tasks; frontend estende os componentes ramon existentes (LeadCard/KanbanColumn/KanbanFilters/NewLeadModal/LeadFields) + componentes novos pequenos. Validação de motivo de perda fica **no controller do dashboard** (o espelho label↔etapa e a captação pública não passam por ela).

**Tech Stack:** Rails 7 (fork Chatwoot v4.15.1), Pundit, jbuilder, Vue 3 Options/Composition + Vuex, Tailwind, vuedraggable.

## Global Constraints

- Base da branch: `feat/ramon-teses-playbooks` (PR #20). Branch nova: `feat/ramon-cadencia-kanban`. Worktree própria.
- **Sem teste local** (não há Postgres local): specs são escritas mas quem roda é o CI. Verificação local = `bundle exec rubocop <arquivos>` e `pnpm eslint <arquivos>` apenas.
- `db/schema.rb` NÃO é editado à mão — regen via scratch DB na VPS no fim (task 8).
- Fork merge-safe: arquivos novos em namespace ramon; edições de core registradas em `docs/FORK-PONTOS-DE-REGISTRO.md`.
- Specs: `create(:account)` já seeda o funil (Novo…Fechado/Perdido) — nunca criar etapa com nome seedado; `Lead` tem `default_scope order(:lead_stage_id, :position, :id)` (`.last` não é o mais recente); Rubocop exige `ENV.fetch`; máx 7 expectations por exemplo; erros por `error.class.name` quando útil.
- Vue: eventos custom SEMPRE camelCase; actions Vuex usam `state: moduleState` (no-shadow); i18n obrigatório (en + pt_BR: `ramon.json`); Tailwind only, sem CSS custom.
- Commits: Conventional Commits, sem referência a Claude.
- Moeda: BRL via `toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' })` (padrão já usado no board).

---

### Task 1: Migração + models (LeadTask, LostReason, colunas de cadência)

**Files:**
- Create: `db/migrate/20260703000001_add_cadence_to_ramon_crm.rb`
- Create: `app/models/lead_task.rb`
- Create: `app/models/lost_reason.rb`
- Modify: `app/models/lead.rb`
- Modify: `app/models/lead_stage.rb` (validações das colunas novas)
- Modify: `app/services/leads/seed_default_config_service.rb`
- Test: `spec/models/lead_task_spec.rb`, `spec/models/lead_cadence_spec.rb`

**Interfaces (Produces):**
- `LeadTask(account_id, lead_id, user_id, title, kind, due_at, completed_at)` — scopes `open_tasks` (`completed_at: nil`), `overdue` (`open_tasks.where(due_at: ...Time.current)`); método `complete!(user)` seta `completed_at` e grava activity `task_completed`.
- `LostReason(account_id, name, position)`.
- `Lead` ganha: `has_many :lead_tasks`; colunas `stage_entered_at`, `won_at`, `lost_at`; método `stalled?`; `push_event_data` ampliado com `stage_entered_at won_at lost_at open_tasks_count next_task_due_at contact_phone`.
- `LeadStage` ganha `probability` (0..100) e `stalled_after_days` (nil ok).
- Novos kinds de `lead_activities`: `task_created`, `task_completed`.

- [ ] **Step 1: Migração**

```ruby
class AddCadenceToRamonCrm < ActiveRecord::Migration[7.0]
  DEFAULTS = {
    'Novo' => [10, 2], 'Qualificação' => [20, 3], 'Reunião agendada' => [40, nil],
    'Reunião realizada' => [60, 5], 'Negociação' => [75, 5], 'Última chance' => [50, 7],
    'Fechado' => [100, nil], 'Perdido' => [0, nil]
  }.freeze
  LOST_REASONS = ['Sem viabilidade', 'Sumiu / não respondeu', 'Honorário',
                  'Foi para concorrente', 'Fora da área', 'Outro'].freeze

  def up
    create_table :lead_tasks do |t|
      t.references :account, null: false, index: false
      t.references :lead, null: false
      t.references :user
      t.string :title, null: false
      t.string :kind, null: false, default: 'follow_up'
      t.datetime :due_at, null: false
      t.datetime :completed_at
      t.timestamps
    end
    add_index :lead_tasks, [:account_id, :due_at]
    add_index :lead_tasks, [:lead_id, :completed_at]

    create_table :lost_reasons do |t|
      t.references :account, null: false
      t.string :name, null: false
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    add_column :lead_stages, :probability, :integer, null: false, default: 0
    add_column :lead_stages, :stalled_after_days, :integer
    add_column :leads, :stage_entered_at, :datetime
    add_column :leads, :won_at, :datetime
    add_column :leads, :lost_at, :datetime

    backfill
  end

  def down
    drop_table :lead_tasks
    drop_table :lost_reasons
    remove_column :lead_stages, :probability
    remove_column :lead_stages, :stalled_after_days
    remove_column :leads, :stage_entered_at
    remove_column :leads, :won_at
    remove_column :leads, :lost_at
  end

  private

  def backfill
    DEFAULTS.each do |name, (probability, stalled)|
      LeadStage.where(name: name).update_all(probability: probability, stalled_after_days: stalled)
    end
    Account.find_each do |account|
      LOST_REASONS.each_with_index do |name, index|
        LostReason.create!(account_id: account.id, name: name, position: index)
      end
    end
    # stage_entered_at: última transição conhecida ou criação
    execute <<~SQL.squish
      UPDATE leads SET stage_entered_at = COALESCE(
        (SELECT MAX(la.created_at) FROM lead_activities la
          WHERE la.lead_id = leads.id AND la.kind = 'stage_changed'),
        leads.created_at)
    SQL
  end
end
```

- [ ] **Step 2: Models novos**

```ruby
# app/models/lead_task.rb
class LeadTask < ApplicationRecord
  KINDS = %w[follow_up document meeting other].freeze

  belongs_to :account
  belongs_to :lead
  belongs_to :user, optional: true

  validates :title, presence: true, length: { maximum: 255 }
  validates :kind, inclusion: { in: KINDS }
  validates :due_at, presence: true

  scope :open_tasks, -> { where(completed_at: nil) }
  scope :overdue, -> { open_tasks.where(due_at: ...Time.current) }
  scope :due_today, -> { open_tasks.where(due_at: Time.current.all_day) }

  after_create_commit :record_created_activity, :touch_lead
  after_update_commit :touch_lead

  def complete!(completing_user)
    update!(completed_at: Time.current)
    lead.lead_activities.create!(account: account, user: completing_user, kind: 'task_completed', to_value: title)
  end

  private

  def record_created_activity
    lead.lead_activities.create!(account: account, user: Current.user, kind: 'task_created', to_value: title)
  end

  def touch_lead
    lead.dispatch_task_update
  end
end
```

```ruby
# app/models/lost_reason.rb
class LostReason < ApplicationRecord
  belongs_to :account
  validates :name, presence: true, uniqueness: { scope: :account_id }
  default_scope { order(:position, :id) }
end
```

- [ ] **Step 3: Lead — associações, callbacks de ciclo, payload**

Em `app/models/lead.rb`: adicionar `has_many :lead_tasks, dependent: :destroy_async`; `before_save :track_stage_cycle`; ampliar `push_event_data`; expor `dispatch_task_update` (público) que dispara `Events::Types::LEAD_UPDATED` (reaproveita o broadcast p/ atualizar badges de task no board):

```ruby
  has_many :lead_tasks, dependent: :destroy_async

  before_save :track_stage_cycle

  def stalled?
    return false if lead_stage&.stalled_after_days.blank? || stage_entered_at.blank?

    stage_entered_at < lead_stage.stalled_after_days.days.ago
  end

  def dispatch_task_update
    dispatch_update_event
  end

  # dentro de push_event_data, adicionar as chaves:
  #   stage_entered_at: stage_entered_at, won_at: won_at, lost_at: lost_at,
  #   stalled: stalled?,
  #   open_tasks_count: lead_tasks.open_tasks.size,
  #   next_task_due_at: lead_tasks.open_tasks.minimum(:due_at),
  #   contact_phone: contact&.phone_number

  private

  def track_stage_cycle
    return unless will_save_change_to_lead_stage_id? || new_record?

    self.stage_entered_at = Time.current
    stage = LeadStage.find_by(id: lead_stage_id)
    self.won_at = stage&.is_won ? (won_at || Time.current) : nil
    self.lost_at = stage&.is_lost ? (lost_at || Time.current) : nil
    self.lost_reason = nil unless stage&.is_lost
  end
```

`dispatch_update_event` deixa de ser private-only (mantê-lo private e chamar via `dispatch_task_update` público, como acima). Atenção rubocop: se `push_event_data` estourar complexidade, extrair um hash parcial `cadence_event_data` e fazer `merge`.

- [ ] **Step 4: LeadStage validações + seed service**

Em `app/models/lead_stage.rb`: `validates :probability, numericality: { in: 0..100 }` e `validates :stalled_after_days, numericality: { greater_than: 0 }, allow_nil: true`.

Em `app/services/leads/seed_default_config_service.rb`: incluir `probability`/`stalled_after_days` nos atributos de cada etapa seedada (mesmos valores do hash DEFAULTS da migração) e seedar os 6 `LostReason` padrão (mesma lista). Manter idempotência do serviço (find_or_create_by name).

- [ ] **Step 5: Specs**

`spec/models/lead_task_spec.rb`: validações (title/kind/due_at), scopes `open_tasks`/`overdue`, `complete!` seta `completed_at` e cria activity `task_completed`.
`spec/models/lead_cadence_spec.rb`: mudar etapa atualiza `stage_entered_at`; mover pra etapa won seta `won_at` e limpa `lost_at`; voltar pra etapa ativa limpa ambos e `lost_reason`; `stalled?` true quando `stage_entered_at` além do limite; `push_event_data` inclui `open_tasks_count`. Usar as etapas seedadas do `create(:account)` (buscar por `is_won`/`is_lost`/position, nunca criar homônima).

- [ ] **Step 6: Lint + commit**

Run: `bundle exec rubocop app/models/lead_task.rb app/models/lost_reason.rb app/models/lead.rb app/models/lead_stage.rb app/services/leads/seed_default_config_service.rb db/migrate/20260703000001_add_cadence_to_ramon_crm.rb`
Expected: no offenses.
`git add` dos arquivos + `git commit -m "feat(ramon): cadência no CRM — lead_tasks, lost_reasons, ciclo de etapa e forecast"`

---

### Task 2: API de tarefas (LeadTasks)

**Files:**
- Create: `app/controllers/api/v1/accounts/lead_tasks_controller.rb`
- Create: `app/policies/lead_task_policy.rb`
- Create: `app/views/api/v1/accounts/lead_tasks/index.json.jbuilder`, `create.json.jbuilder`, `update.json.jbuilder` (seguir o padrão dos jbuilders de `lead_notes`, com partial `_lead_task.json.jbuilder`)
- Modify: `config/routes.rb` (bloco das rotas ramon, junto de `leads`)
- Test: `spec/controllers/api/v1/accounts/lead_tasks_controller_spec.rb`

**Interfaces:**
- Consumes: `LeadTask` da Task 1.
- Produces: rotas `GET/POST /api/v1/accounts/:account_id/leads/:lead_id/tasks`, `PATCH .../tasks/:id`, `POST .../tasks/:id/complete`, `DELETE .../tasks/:id` e coleção da conta `GET /api/v1/accounts/:account_id/lead_tasks?scope=open|overdue|today`. Partial jbuilder com `id lead_id user_id title kind due_at completed_at created_at` + `lead_name` (para listas da conta).

- [ ] **Step 1: Rotas** — dentro do `resources :leads` existente adicionar `resources :tasks, only: [:index, :create, :update, :destroy], controller: 'lead_tasks' do; member { post :complete }; end`; e no nível da conta `resources :lead_tasks, only: [:index]`.

- [ ] **Step 2: Controller**

```ruby
class Api::V1::Accounts::LeadTasksController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :fetch_lead, if: -> { params[:lead_id].present? }
  before_action :fetch_task, only: [:update, :destroy, :complete]
  before_action :check_authorization

  def index
    @lead_tasks = params[:lead_id].present? ? @lead.lead_tasks.order(:due_at) : account_scope
  end

  def create
    @lead_task = @lead.lead_tasks.create!(permitted_params.merge(account: Current.account, user: Current.user))
  end

  def update
    @lead_task.update!(permitted_params)
  end

  def complete
    @lead_task.complete!(Current.user)
    render :update
  end

  def destroy
    @lead_task.destroy!
    head :ok
  end

  private

  def account_scope
    scope = Current.account.lead_tasks.includes(:lead)
    case params[:scope]
    when 'overdue' then scope.overdue.order(:due_at)
    when 'today' then scope.due_today.order(:due_at)
    else scope.open_tasks.order(:due_at)
    end
  end

  def fetch_lead
    @lead = Current.account.leads.find(params[:lead_id])
  end

  def fetch_task
    @lead_task = @lead.lead_tasks.find(params[:id])
  end

  def permitted_params
    params.permit(:title, :kind, :due_at)
  end

  def check_authorization
    authorize(LeadTask)
  end
end
```

(Exige `has_many :lead_tasks` em `Account` — adicionar em `app/models/account.rb` junto das associações ramon existentes de leads, registrando em FORK-PONTOS se for edição de core; `leads` já está lá, seguir o mesmo bloco.)

- [ ] **Step 3: Policy** — copiar o padrão de `lead_note_policy.rb`: `index?/create?/update?/complete?/destroy?` = `@account_user.administrator? || @account_user.agent?`.

- [ ] **Step 4: Specs de request** — seguir o padrão de `lead_notes_controller_spec.rb`: agente cria/lista/completa/deleta; usuário sem acesso à conta recebe 404/401; `complete` grava `completed_at`; coleção da conta filtra por `scope=overdue`.

- [ ] **Step 5: Lint + commit** — rubocop nos arquivos novos; `git commit -m "feat(ramon): API de tarefas do lead (próxima ação com prazo)"`

---

### Task 3: Leads API — filtros novos, custom_attributes, trava de motivo de perda; config exposta

**Files:**
- Modify: `app/controllers/api/v1/accounts/leads_controller.rb`
- Modify: `app/controllers/api/v1/accounts/lead_stages_controller.rb` (params += `probability`, `stalled_after_days`)
- Modify: `app/controllers/api/v1/accounts/lead_config_controller.rb` + view jbuilder do `lead_config#show` (expor `probability`/`stalled_after_days` em stages e array `lost_reasons`)
- Modify: partial jbuilder do lead (`app/views/api/v1/accounts/leads/_lead.json.jbuilder` ou equivalente) — espelhar as chaves novas do `push_event_data`
- Test: ampliar `spec/controllers/api/v1/accounts/leads_controller_spec.rb`

**Interfaces:**
- Produces: `leads#index` aceita `lead_stage_id`, `created_after`, `created_before`, `stalled=true`, `no_open_task=true`; `update` devolve **422 com `{ error: 'LOST_REASON_REQUIRED' }`** se mover para etapa `is_lost` sem `lost_reason` (nem no payload nem já gravado); `permitted_params` aceita `custom_attributes: {}` e `lost_reason`.

- [ ] **Step 1: Filtros**

```ruby
  def filtered_leads
    leads = apply_equality_filters(policy_scope(Current.account.leads))
    leads = leads.where('sdr_id = :a OR closer_id = :a', a: params[:agent_id]) if params[:agent_id].present?
    leads = apply_cadence_filters(apply_period_filters(leads))
    leads = search_leads(leads, params[:q]) if params[:q].present?
    leads
  end

  def apply_equality_filters(leads)
    %i[benefit_type_id lead_priority_id lead_stage_id source].each do |key|
      leads = leads.where(key => params[key]) if params[key].present?
    end
    leads
  end

  def apply_period_filters(leads)
    leads = leads.where(created_at: Date.parse(params[:created_after]).beginning_of_day..) if params[:created_after].present?
    leads = leads.where(created_at: ..Date.parse(params[:created_before]).end_of_day) if params[:created_before].present?
    leads
  end

  def apply_cadence_filters(leads)
    if params[:stalled].present?
      leads = leads.joins(:lead_stage).where.not(lead_stages: { stalled_after_days: nil })
                   .where("leads.stage_entered_at < NOW() - (lead_stages.stalled_after_days || ' days')::interval")
    end
    leads = leads.where.missing(:lead_tasks).or(leads.where.not(id: LeadTask.open_tasks.select(:lead_id))) if params[:no_open_task].present?
    leads
  end
```

Atenção: `where.missing(...).or(...)` pode reclamar de estrutura — alternativa segura: `leads.where.not(id: Current.account.lead_tasks.open_tasks.select(:lead_id))` (cobre os dois casos). Usar a forma simples.

- [ ] **Step 2: Trava de perda no `update`**

```ruby
  def update
    ensure_lost_reason!
    @lead.update!(permitted_params)
  end

  private

  def ensure_lost_reason!
    target_stage_id = permitted_params[:lead_stage_id]
    return if target_stage_id.blank?

    stage = Current.account.lead_stages.find_by(id: target_stage_id)
    return unless stage&.is_lost
    return if permitted_params[:lost_reason].presence || @lead.lost_reason.presence

    render json: { error: 'LOST_REASON_REQUIRED' }, status: :unprocessable_entity
  end
```

(`ensure_lost_reason!` renderiza e o `update!` não pode rodar depois — usar `return if performed?` no início do corpo restante de `update`, padrão Rails.)

- [ ] **Step 3: `permitted_params`** — adicionar `custom_attributes: {}` ao final do `params.permit(...)`.

- [ ] **Step 4: lead_config + lead_stages** — `lead_config#show` inclui `@lost_reasons = Current.account.lost_reasons` e o jbuilder ganha o array (`id`, `name`) + `probability`/`stalled_after_days` dentro de cada stage; `lead_stages_controller#permitted_params` += `:probability, :stalled_after_days`.

- [ ] **Step 5: Specs** — filtros `lead_stage_id`/`created_after`/`stalled`/`no_open_task` (com `reorder(nil)` quando usar pluck+DISTINCT); update para etapa perdida sem motivo → 422 `LOST_REASON_REQUIRED`; com motivo → 200 e `lost_at` preenchido; `custom_attributes` persiste.

- [ ] **Step 6: Lint + commit** — `git commit -m "feat(ramon): filtros de cadência, custom_attributes e trava de motivo de perda na API de leads"`

---

### Task 4: Frontend — camada de dados (API clients + stores)

**Files:**
- Create: `app/javascript/dashboard/api/leadTasks.js`
- Create: `app/javascript/dashboard/store/modules/leadTasks.js` (+ registrar em `store/index.js` junto de `leads`)
- Modify: `app/javascript/dashboard/store/modules/leadConfig.js` (state/getter `lostReasons`; stages já carregam o objeto inteiro — garantir pass-through de `probability`/`stalled_after_days`)
- Modify: `app/javascript/dashboard/store/modules/leads.js` (filtros novos no state `filters`: `lead_stage_id`, `created_after`, `created_before`, `stalled`, `no_open_task`)
- Test: specs de store em `app/javascript/dashboard/store/modules/specs/` seguindo o padrão dos specs de `leads`

**Interfaces:**
- Produces: `leadTasks` store — state `{ records: [], uiFlags }`; actions `fetchForLead(leadId)`, `fetchAccountScope(scope)`, `create({ leadId, title, kind, dueAt })`, `complete({ leadId, taskId })`, `destroy({ leadId, taskId })`; getters `getByLead(leadId)` (abertas, ordenadas por due_at), `getAccountTasks`. Mutations fazem MERGE por id (lição SET_THESES).
- API client: `leadTasks.get(leadId)`, `leadTasks.getAccountScope(scope)`, `leadTasks.create(leadId, payload)`, `leadTasks.update(leadId, id, payload)`, `leadTasks.complete(leadId, id)`, `leadTasks.delete(leadId, id)` — payload snake_case (`due_at`).

- [ ] **Step 1: API client** (seguir `api/leadConfig.js` como referência de construção de URL com account scoping).
- [ ] **Step 2: Store module** — actions com `state: moduleState` quando desestruturar; `complete` remove/atualiza o record e re-dispara `leads/get`? NÃO — o broadcast `lead.updated` já atualiza o card; apenas atualizar o record local da task.
- [ ] **Step 3: Filtros no store `leads`** — ampliar `defaultFilters`/`setFilters`/`loadFilters` (persistência `localStorage` `ramon_lead_filters` já existe; incluir chaves novas).
- [ ] **Step 4: Specs de store (vitest)** — merge por id no upsert; `getByLead` só abertas ordenadas.
- [ ] **Step 5: Lint + commit** — `pnpm eslint <arquivos> --fix`; `git commit -m "feat(ramon): store e API client de tarefas + filtros de cadência"`

---

### Task 5: Frontend — LeadCard e KanbanColumn (idade, apodrecimento, sino, wa.me, R$ ponderado)

**Files:**
- Create: `app/javascript/dashboard/routes/dashboard/ramon/components/kanban/TaskBellMenu.vue`
- Modify: `.../kanban/LeadCard.vue`
- Modify: `.../kanban/KanbanColumn.vue`
- Modify: `app/javascript/dashboard/i18n/locale/en/ramon.json` + `pt_BR/ramon.json`

**Interfaces:**
- Consumes: payload do lead com `stage_entered_at`, `stalled`, `open_tasks_count`, `next_task_due_at`, `contact_phone` (Task 1/3); store `leadTasks` (Task 4); `leadConfig/getStages` com `probability`.
- Produces: evento `openLead`/`openConversation` inalterados; TaskBellMenu emite `schedule` com `{ dueAt, title }`.

- [ ] **Step 1: TaskBellMenu.vue** — botão-ícone sino; dropdown com opções fixas: Amanhã 9h, Em 3 dias, Em 1 semana, Escolher data (input datetime-local) + título opcional (default i18n "Follow-up"); ao escolher → `emit('schedule', { dueAt, title })`. `<script setup>`, Tailwind, i18n keys `RAMON.KANBAN.BELL.*`.
- [ ] **Step 2: LeadCard.vue** —
  - idade na etapa: computed `daysInStage` de `lead.stage_entered_at` → chip "3d";
  - classes de borda: `lead.stalled` → `border-amber-500`; `daysInStage > 2 × stalledAfterDays` da etapa (via leadConfig) → `border-red-500`;
  - badge "sem próxima ação": `lead.open_tasks_count === 0` e etapa ativa (nem won nem lost) → ícone alerta com tooltip i18n;
  - sino: monta `TaskBellMenu`, no `schedule` → `dispatch('leadTasks/create', { leadId, title, kind: 'follow_up', dueAt })`;
  - wa.me: se `lead.contact_phone` e `!lead.conversation_id` → `<a :href="'https://wa.me/' + digits" target="_blank" rel="noopener">` com stopPropagation; telefone clicável copia (navigator.clipboard + toast `useAlert`).
- [ ] **Step 3: KanbanColumn.vue** — além da soma existente, computed `weightedValue = totalValue × (stage.probability/100)` exibido como segundo valor menor ("~R$ X ponderado", i18n `RAMON.KANBAN.COLUMN.WEIGHTED`).
- [ ] **Step 4: i18n en+pt_BR** — todas as chaves novas nos dois arquivos.
- [ ] **Step 5: Lint + commit** — `pnpm eslint ... --fix`; `git commit -m "feat(ramon): card com cadência (idade, apodrecimento, sino de follow-up, wa.me) e coluna com forecast ponderado"`

---

### Task 6: Frontend — filtros novos + Smart Views

**Files:**
- Create: `.../kanban/SavedViews.vue`
- Modify: `.../kanban/KanbanFilters.vue`
- Modify: `.../kanban/KanbanBoard.vue` (montar SavedViews na barra de filtros)
- Modify: i18n `en/ramon.json` + `pt_BR/ramon.json`

**Interfaces:**
- Consumes: filtros ampliados do store `leads` (Task 4).
- Produces: SavedViews lê/grava `ui_settings.ramon_lead_views` (`[{ name, filters }]`) via `useUISettings` (mesmo mecanismo de `external_shortcuts` — sem backend); emite `applyView(filters)`.

- [ ] **Step 1: KanbanFilters.vue** — adicionar: select de etapa (stages do leadConfig), par de date inputs (de/até, mapeiam `created_after`/`created_before`), toggles "Parados" (`stalled`) e "Sem próxima ação" (`no_open_task`). Todos passam pelo `setFilters` existente (server-side via `leads/get`).
- [ ] **Step 2: SavedViews.vue** — chips horizontais: cada view salva mostra nome + contador (contagem client-side: aplicar `filters` sobre `leads/getLeads` — helper local `matchesFilters(lead, filters)` cobrindo etapa/benefício/prioridade/source/stalled/no_open_task; para período usar `created_at`); clique aplica (`leads/setFilters` + `get`); botão "salvar view atual" (prompt de nome) e remover (x no chip). Persistência `updateUISettings({ ramon_lead_views })`.
- [ ] **Step 3: Board** — montar `<SavedViews>` acima/ao lado de `<KanbanFilters>`.
- [ ] **Step 4: Lint + commit** — `git commit -m "feat(ramon): filtros de etapa/período/cadência e Smart Views salvas no Kanban"`

---

### Task 7: Frontend — modais de perda/ganho, NewLeadModal completo com dedup, Próximas ações no painel

**Files:**
- Create: `.../kanban/LostReasonModal.vue`
- Create: `.../components/lead/LeadTasksList.vue`
- Modify: `.../kanban/KanbanBoard.vue` (interceptar drop em etapa lost/won)
- Modify: `.../kanban/NewLeadModal.vue`
- Modify: `.../components/lead/LeadFields.vue`
- Modify: i18n en+pt_BR

**Interfaces:**
- Consumes: `leadConfig/getLostReasons` (Task 3/4); store `leadTasks` (Task 4); action `leads/move` existente.
- Produces: LostReasonModal emite `confirmMove({ lostReason })` / `cancelMove`; LeadTasksList é reusável (drawer + painel da conversa) com prop `leadId`.

- [ ] **Step 1: KanbanBoard.vue — interceptar o drop.** No handler de mudança do vuedraggable (onde hoje persiste `lead_stage_id` + `position`): se a etapa destino `is_lost` e o lead não tem `lost_reason` → NÃO despachar `move`; guardar movimento pendente no estado local e abrir `LostReasonModal`; confirmar → `dispatch('leads/update', { id, lead_stage_id, position, lost_reason })`; cancelar → re-render (o board relê do store, que não mudou). Se etapa destino `is_won` e `!lead.value` → abrir mini-modal de valor (input BRL, botões Salvar / Pular) e seguir com o move em ambos (valor é convite, não trava).
- [ ] **Step 2: LostReasonModal.vue** — modal (padrão `RemoveStageModal.vue`): select com `lostReasons` do config + textarea opcional "detalhe" (concatena no `lost_reason` como "Motivo — detalhe"); botão confirmar desabilitado sem seleção.
- [ ] **Step 3: NewLeadModal.vue completo** — campos: nome*, telefone (com DDI default +55), tese/benefício, origem (datalist com sources conhecidos do config), valor, prioridade. No blur do telefone → `LeadsAPI.get({ q: telefone })`; se existir lead em etapa ativa → aviso inline "Já existe lead aberto para este telefone: <nome> (<etapa>)" com botão "Abrir existente" (fecha modal e `leads/select`) — criação continua possível (aviso, não trava). Ao salvar com telefone: buscar/criar Contact nativo (usar o endpoint de contatos existente via `ContactAPI` — busca por phone; criar se ausente com `name`+`phone_number`) e mandar `contact_id` no create do lead.
- [ ] **Step 4: LeadTasksList.vue** — lista das tasks abertas do lead (`leadTasks/getByLead`): título, due_at relativo (vermelho se vencida), checkbox concluir (`complete`); ao concluir → inline "agendar próxima?" com os mesmos atalhos do TaskBellMenu (sugerir, nunca obrigar); botão "+ tarefa" (título + data). Montar no `LeadFields.vue` como bloco "Próximas ações" ACIMA do bloco de notas; `fetchForLead` no mounted (com `v-if` de readiness do lead — lição do fork).
- [ ] **Step 5: LeadFields.vue — lost_reason.** Quando o lead está em etapa perdida, mostrar linha "Motivo da perda" (select das lostReasons + texto atual), editável.
- [ ] **Step 6: Lint + commit** — `git commit -m "feat(ramon): motivo de perda obrigatório, valor no ganho, novo lead completo com dedup e próximas ações no painel"`

---

### Task 8: FORK-PONTOS, schema regen, PR e CI

**Files:**
- Modify: `docs/FORK-PONTOS-DE-REGISTRO.md` (novas edições de core: routes.rb, account.rb, store/index.js, i18n index se aplicável)
- Modify: `db/schema.rb` (via scratch DB na VPS — NUNCA à mão)

- [ ] **Step 1: Registrar pontos de fork** em `docs/FORK-PONTOS-DE-REGISTRO.md`.
- [ ] **Step 2: Regen do schema na VPS** (procedimento validado na F2.1a): clonar a branch em `/opt/scratch`, `docker compose run --rm --no-deps -v /opt/scratch/ramon-hub:/scratch-src -e DATABASE_URL="postgres://chatwoot:$PW@postgres:5432/ramon_schema_scratch" -w /scratch-src --entrypoint sh chatwoot-web -c "rake db:schema:load db:migrate db:schema:dump"`, `scp` do `schema.rb` de volta, dropdb + rm no fim. Commit: `chore(ramon): regen schema.rb com tabelas de cadência`.
- [ ] **Step 3: Push + PR** — `git push -u origin feat/ramon-cadencia-kanban`; `gh pr create --base ramon --title "Cadência no CRM + Kanban nível referência (Centro de Operações v2 — PR A)"` com descrição no formato do AGENTS.md (parágrafo de produto + How to test). **Nota na descrição: depende do merge do PR #20 (base empilhada).**
- [ ] **Step 4: CI pelo método correto** — `gh api repos/doods-maker/ramon-hub/commits/<sha>/check-runs` do commit EXATO: N/N `completed`, zero conclusion fora de `success`/`skipped`. NUNCA lista truncada. Corrigir e repetir até verde.

## Self-review (feito na escrita)
- Cobertura da spec PR A: migração ✓ (T1), tasks API ✓ (T2), filtros/custom_attributes/trava de perda ✓ (T3), stores ✓ (T4), card/coluna ✓ (T5), filtros/views ✓ (T6), modais/NewLead/painel ✓ (T7), schema/PR ✓ (T8). Guidance por etapa e checklist de documentos são do PR B (spec §2-B).
- Consistência de nomes: `lead_tasks`/`LeadTask`/`leadTasks` uniformes; `open_tasks_count`/`next_task_due_at`/`contact_phone`/`stalled` usados em T1→T5; `LOST_REASON_REQUIRED` em T3→T7.
- Riscos apontados no próprio texto (rubocop complexity no push_event_data, or/where.missing, performed? no update).
