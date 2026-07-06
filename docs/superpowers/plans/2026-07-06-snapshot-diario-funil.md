# Snapshot Diário do Funil — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Gravar, todo dia, o retrato agregado do funil (leads e valor por etapa×tese) numa tabela append-only, e mostrar a tendência de 30 dias no Centro de Comando.

**Architecture:** Tabela de fatos `funnel_snapshots` (uma linha por conta×dia×etapa×tese, com rótulos denormalizados). Um serviço agrega os leads vivos e grava idempotentemente (delete-then-insert por dia). Um job diário (sidekiq-cron 00:05 BRT) roda o serviço para cada conta. A leitura reaproveita o endpoint `ramon_dashboard` existente (nova chave `history`) e o `CommandCenter.vue` ganha uma seção com sparkline — sem endpoint/store novos.

**Tech Stack:** Rails 7.1 (fork Chatwoot v4.15.1), RSpec, Sidekiq-cron, Vue 3 `<script setup>`, Vuex, Vitest, Tailwind, jbuilder, i18n (en + pt_BR).

## Global Constraints

- **Ruby**: RuboCop, 150 caracteres máx por linha. `ENV.fetch` (não `ENV[]`).
- **`insert_all`/`delete_all`/`update_column`** disparam o cop `Rails/SkipsModelValidations` → `# rubocop:disable Rails/SkipsModelValidations` inline (padrão do fork).
- **Migração nova → regenerar `db/schema.rb`** (não há Postgres local; CI carrega o schema.rb). Procedimento scratch-DB via workflow temporário do Actions ("Regen schema.rb") — o mesmo usado na PR #35 da prescrição (recuperável de `git show 49efa71bb`). Sem schema.rb atualizado, o CI fica vermelho.
- **Vue**: eventos camelCase; Composition API `<script setup>`; PascalCase nos componentes; Tailwind only (sem CSS custom/scoped/inline).
- **Vuex action**: não desestruturar `state` cru (regra no-shadow) — usar `state: moduleState` se precisar.
- **i18n**: sem string crua no template; namespace `RAMON.*` é da banca → atualizar **en/ramon.json e pt_BR/ramon.json** (a regra "só en" vale pras strings upstream do Chatwoot, não pro namespace Ramon).
- **RSpec**: máx 7 expectations por exemplo. `create(:account)` já semeia o funil (etapas Novo…Fechado/Perdido, com uma won e uma lost). Nunca criar etapa com nome semeado.
- **Deploy só com OK explícito do Eduardo.** Nada sobe pra VPS sem aprovação, mesmo pós-merge.

---

### Task 1: Tabela e modelo `funnel_snapshots`

**Files:**
- Create: `db/migrate/20260706130001_create_funnel_snapshots.rb`
- Create: `app/models/funnel_snapshot.rb`
- Create: `spec/models/funnel_snapshot_spec.rb`
- Modify: `db/schema.rb` (regenerado)

**Interfaces:**
- Produces: modelo `FunnelSnapshot` com colunas `account_id, snapshot_date (date), lead_stage_id (nullable), stage_name, stage_position, is_won, is_lost, thesis_id (nullable), thesis_name, leads_count (int), value_sum (decimal 14,2)`. Associações: `belongs_to :account`, `belongs_to :lead_stage, optional: true`, `belongs_to :thesis, optional: true`.

- [ ] **Step 1: Write the failing test**

`spec/models/funnel_snapshot_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe FunnelSnapshot, type: :model do
  let(:account) { create(:account) }
  let(:stage) { account.lead_stages.find_by(name: 'Novo') }

  it 'persists a snapshot row with denormalized labels' do
    snap = FunnelSnapshot.create!(
      account: account, snapshot_date: Time.zone.today,
      lead_stage: stage, stage_name: stage.name, stage_position: stage.position,
      is_won: false, is_lost: false, thesis_id: nil, thesis_name: nil,
      leads_count: 3, value_sum: 4500
    )
    expect(snap.reload.leads_count).to eq(3)
    expect(snap.value_sum).to eq(4500)
    expect(snap.stage_name).to eq('Novo')
  end

  it 'allows a null lead_stage and thesis (history survives deletes)' do
    snap = FunnelSnapshot.create!(
      account: account, snapshot_date: Time.zone.today,
      stage_name: 'Etapa Removida', stage_position: 9,
      leads_count: 0, value_sum: 0
    )
    expect(snap).to be_persisted
    expect(snap.lead_stage).to be_nil
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/models/funnel_snapshot_spec.rb`
Expected: FAIL — `uninitialized constant FunnelSnapshot` (ou tabela inexistente).

- [ ] **Step 3: Write the migration**

`db/migrate/20260706130001_create_funnel_snapshots.rb`:

```ruby
class CreateFunnelSnapshots < ActiveRecord::Migration[7.1]
  # rubocop:disable Metrics/MethodLength
  def change
    create_table :funnel_snapshots do |t|
      t.references :account, null: false, index: false
      t.date :snapshot_date, null: false
      t.references :lead_stage, null: true, foreign_key: { on_delete: :nullify }
      t.string :stage_name, null: false
      t.integer :stage_position, null: false, default: 0
      t.boolean :is_won, null: false, default: false
      t.boolean :is_lost, null: false, default: false
      t.references :thesis, null: true, foreign_key: { on_delete: :nullify }
      t.string :thesis_name
      t.integer :leads_count, null: false, default: 0
      t.decimal :value_sum, precision: 14, scale: 2, null: false, default: 0
      t.timestamps
    end
    add_index :funnel_snapshots, [:account_id, :snapshot_date]
  end
  # rubocop:enable Metrics/MethodLength
end
```

- [ ] **Step 4: Write the model**

`app/models/funnel_snapshot.rb`:

```ruby
class FunnelSnapshot < ApplicationRecord
  belongs_to :account
  belongs_to :lead_stage, optional: true
  belongs_to :thesis, optional: true
end
```

- [ ] **Step 5: Regenerate `db/schema.rb`**

Não há Postgres local. Rodar o procedimento scratch-DB via workflow temporário do Actions ("Regen schema.rb", padrão da PR #35 — `git show 49efa71bb` traz o workflow se ele não estiver mais registrado), baixar o `schema.rb` regenerado e commitar. Conferir que o bloco `create_table "funnel_snapshots"` aparece no `db/schema.rb` e que a `version` subiu para `2026_07_06_130001`.

- [ ] **Step 6: Run test to verify it passes**

Run: `bundle exec rspec spec/models/funnel_snapshot_spec.rb`
Expected: PASS (no CI, após schema.rb atualizado).

- [ ] **Step 7: Commit**

```bash
git add db/migrate/20260706130001_create_funnel_snapshots.rb app/models/funnel_snapshot.rb spec/models/funnel_snapshot_spec.rb db/schema.rb
git commit -m "feat(funil): tabela e modelo funnel_snapshots"
```

---

### Task 2: Serviço `Ramon::FunnelSnapshotService`

**Files:**
- Create: `app/services/ramon/funnel_snapshot_service.rb`
- Create: `spec/services/ramon/funnel_snapshot_service_spec.rb`

**Interfaces:**
- Consumes: modelo `FunnelSnapshot` (Task 1).
- Produces: `Ramon::FunnelSnapshotService.new(account:, date: Time.zone.today).perform` — grava uma linha por (etapa×tese) com leads naquele dia; idempotente (delete-then-insert por conta+data). Retorna o número de linhas gravadas.

- [ ] **Step 1: Write the failing test**

`spec/services/ramon/funnel_snapshot_service_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe Ramon::FunnelSnapshotService do
  let(:account) { create(:account) }
  let(:novo) { account.lead_stages.find_by(name: 'Novo') }
  let(:aux) { Thesis.create!(account: account, name: 'Auxílio-acidente') }
  let(:bpc) { Thesis.create!(account: account, name: 'BPC') }

  it 'grava uma linha por etapa x tese com contagem e soma' do
    create(:lead, account: account, lead_stage: novo, thesis: aux, value: 1000)
    create(:lead, account: account, lead_stage: novo, thesis: aux, value: 500)
    create(:lead, account: account, lead_stage: novo, thesis: bpc, value: 300)

    described_class.new(account: account, date: Time.zone.today).perform

    rows = FunnelSnapshot.where(account: account, snapshot_date: Time.zone.today)
    aux_row = rows.find_by(thesis_id: aux.id)
    expect(rows.count).to eq(2)
    expect(aux_row.leads_count).to eq(2)
    expect(aux_row.value_sum).to eq(1500)
    expect(aux_row.stage_name).to eq('Novo')
    expect(aux_row.is_won).to be(false)
  end

  it 'é idempotente: re-rodar o mesmo dia não duplica' do
    create(:lead, account: account, lead_stage: novo, thesis: aux, value: 1000)
    2.times { described_class.new(account: account, date: Time.zone.today).perform }
    expect(FunnelSnapshot.where(account: account, snapshot_date: Time.zone.today).count).to eq(1)
  end

  it 'grava leads sem tese com thesis_name nulo' do
    create(:lead, account: account, lead_stage: novo, value: 700)
    described_class.new(account: account, date: Time.zone.today).perform
    row = FunnelSnapshot.find_by(account: account, lead_stage_id: novo.id, thesis_id: nil)
    expect(row.thesis_name).to be_nil
    expect(row.value_sum).to eq(700)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/ramon/funnel_snapshot_service_spec.rb`
Expected: FAIL — `uninitialized constant Ramon::FunnelSnapshotService`.

- [ ] **Step 3: Write the service**

`app/services/ramon/funnel_snapshot_service.rb`:

```ruby
module Ramon
  class FunnelSnapshotService
    def initialize(account:, date: Time.zone.today)
      @account = account
      @date = date
    end

    def perform
      rows = build_rows
      FunnelSnapshot.transaction do
        # rubocop:disable Rails/SkipsModelValidations
        FunnelSnapshot.where(account_id: @account.id, snapshot_date: @date).delete_all
        FunnelSnapshot.insert_all(rows) if rows.any?
        # rubocop:enable Rails/SkipsModelValidations
      end
      rows.size
    end

    private

    # reorder(nil) anula o default_scope de ordenação do Lead, que quebra o
    # GROUP BY no Postgres (mesmo motivo do funnel_section do dashboard).
    def build_rows
      counts = @account.leads.reorder(nil).group(:lead_stage_id, :thesis_id).count
      values = @account.leads.reorder(nil).group(:lead_stage_id, :thesis_id).sum(:value)
      now = Time.current
      counts.filter_map do |(stage_id, thesis_id), count|
        stage = stages[stage_id]
        next unless stage

        row(stage, thesis_id, count, values[[stage_id, thesis_id]] || 0, now)
      end
    end

    def row(stage, thesis_id, count, value_sum, now)
      {
        account_id: @account.id, snapshot_date: @date,
        lead_stage_id: stage.id, stage_name: stage.name, stage_position: stage.position,
        is_won: stage.is_won, is_lost: stage.is_lost,
        thesis_id: thesis_id, thesis_name: thesis_names[thesis_id],
        leads_count: count, value_sum: value_sum,
        created_at: now, updated_at: now
      }
    end

    def stages
      @stages ||= @account.lead_stages.index_by(&:id)
    end

    def thesis_names
      @thesis_names ||= Thesis.where(account_id: @account.id).pluck(:id, :name).to_h
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/services/ramon/funnel_snapshot_service_spec.rb`
Expected: PASS (3 exemplos).

- [ ] **Step 5: Commit**

```bash
git add app/services/ramon/funnel_snapshot_service.rb spec/services/ramon/funnel_snapshot_service_spec.rb
git commit -m "feat(funil): serviço de snapshot diário agregado por etapa e tese"
```

---

### Task 3: Job diário + agendamento

**Files:**
- Create: `app/jobs/ramon/daily_funnel_snapshot_job.rb`
- Create: `spec/jobs/ramon/daily_funnel_snapshot_job_spec.rb`
- Modify: `config/schedule.yml`

**Interfaces:**
- Consumes: `Ramon::FunnelSnapshotService` (Task 2).
- Produces: `Ramon::DailyFunnelSnapshotJob.perform_now` — roda o serviço para `Time.zone.today` em cada conta. Registrado no sidekiq-cron.

- [ ] **Step 1: Write the failing test**

`spec/jobs/ramon/daily_funnel_snapshot_job_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe Ramon::DailyFunnelSnapshotJob do
  it 'grava o snapshot de hoje para a conta' do
    account = create(:account)
    novo = account.lead_stages.find_by(name: 'Novo')
    create(:lead, account: account, lead_stage: novo, value: 1200)

    described_class.perform_now

    row = FunnelSnapshot.find_by(account: account, snapshot_date: Time.zone.today, lead_stage_id: novo.id)
    expect(row).to be_present
    expect(row.value_sum).to eq(1200)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/jobs/ramon/daily_funnel_snapshot_job_spec.rb`
Expected: FAIL — `uninitialized constant Ramon::DailyFunnelSnapshotJob`.

- [ ] **Step 3: Write the job**

`app/jobs/ramon/daily_funnel_snapshot_job.rb`:

```ruby
module Ramon
  class DailyFunnelSnapshotJob < ApplicationJob
    queue_as :scheduled_jobs

    def perform
      Account.find_each do |account|
        Ramon::FunnelSnapshotService.new(account: account).perform
      end
    end
  end
end
```

- [ ] **Step 4: Register in `config/schedule.yml`**

Acrescentar ao fim de `config/schedule.yml`:

```yaml
# executed daily at 0305 UTC = 00:05 America/Sao_Paulo (UTC-3)
# tira o retrato agregado do funil na virada do dia (Organismo, Onda 0)
ramon_daily_funnel_snapshot_job:
  cron: '5 3 * * *'
  class: 'Ramon::DailyFunnelSnapshotJob'
  queue: scheduled_jobs
```

- [ ] **Step 5: Run tests (job + schedule validation) to verify they pass**

Run: `bundle exec rspec spec/jobs/ramon/daily_funnel_snapshot_job_spec.rb spec/configs/schedule_spec.rb`
Expected: PASS (o schedule_spec valida que a classe do novo cron constantiza).

- [ ] **Step 6: Commit**

```bash
git add app/jobs/ramon/daily_funnel_snapshot_job.rb spec/jobs/ramon/daily_funnel_snapshot_job_spec.rb config/schedule.yml
git commit -m "feat(funil): job diário de snapshot + agendamento sidekiq-cron"
```

---

### Task 4: Leitura — `history` no endpoint `ramon_dashboard`

**Files:**
- Modify: `app/controllers/api/v1/accounts/ramon_dashboard_controller.rb`
- Modify: `app/views/api/v1/accounts/ramon_dashboard/show.json.jbuilder`
- Modify: `spec/controllers/api/v1/accounts/ramon_dashboard_controller_spec.rb`

**Interfaces:**
- Consumes: modelo `FunnelSnapshot` (Task 1).
- Produces: a resposta de `GET /api/v1/accounts/:id/ramon_dashboard` ganha `history`: array (ordenado por data asc) de `{ date, leads_count, value_sum }`, rolado por dia sobre as etapas **abertas** (is_won=false, is_lost=false) dos últimos 30 dias.

- [ ] **Step 1: Write the failing test**

Acrescentar ao `spec/controllers/api/v1/accounts/ramon_dashboard_controller_spec.rb` (antes do último `it`):

```ruby
  it 'rola o histórico de 30 dias somando só etapas abertas' do
    open_stage = account.lead_stages.find_by(name: 'Novo')
    won_stage = account.lead_stages.find_by(is_won: true)
    FunnelSnapshot.create!(account: account, snapshot_date: 2.days.ago.to_date,
                           lead_stage: open_stage, stage_name: 'Novo', stage_position: 0,
                           is_won: false, is_lost: false, leads_count: 4, value_sum: 4000)
    FunnelSnapshot.create!(account: account, snapshot_date: 2.days.ago.to_date,
                           lead_stage: won_stage, stage_name: 'Fechado', stage_position: 5,
                           is_won: true, is_lost: false, leads_count: 9, value_sum: 90_000)

    get url, headers: agent.create_new_auth_token, as: :json

    history = response.parsed_body['history']
    row = history.find { |h| h['date'] == 2.days.ago.to_date.to_s }
    expect(row['leads_count']).to eq(4)
    expect(row['value_sum']).to eq(4000.0)
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/controllers/api/v1/accounts/ramon_dashboard_controller_spec.rb -e "histórico"`
Expected: FAIL — `history` é `nil`.

- [ ] **Step 3: Extend the controller**

Em `app/controllers/api/v1/accounts/ramon_dashboard_controller.rb`, adicionar `@history` ao `show` e o método privado:

```ruby
  def show
    @today = today_section
    @funnel = funnel_section
    @week = week_section
    @history = history_section
  end
```

E, na seção privada (por ex. logo após `week_section` e seus helpers):

```ruby
  # ---- Histórico (snapshots diários) ------------------------------------

  # 2 sums agregadas por dia sobre etapas abertas (estoque de pipeline vivo).
  def history_section
    scope = FunnelSnapshot.where(account_id: Current.account.id, is_won: false, is_lost: false)
                          .where(snapshot_date: 29.days.ago.to_date..)
    counts = scope.group(:snapshot_date).sum(:leads_count)
    values = scope.group(:snapshot_date).sum(:value_sum)
    counts.keys.sort.map do |date|
      { date: date, leads_count: counts[date].to_i, value_sum: values[date].to_f }
    end
  end
```

- [ ] **Step 4: Extend the jbuilder view**

Acrescentar ao fim de `app/views/api/v1/accounts/ramon_dashboard/show.json.jbuilder`:

```ruby
json.history @history do |row|
  json.date row[:date]
  json.leads_count row[:leads_count]
  json.value_sum row[:value_sum]
end
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bundle exec rspec spec/controllers/api/v1/accounts/ramon_dashboard_controller_spec.rb`
Expected: PASS (todos os exemplos, incluindo o novo).

- [ ] **Step 6: Commit**

```bash
git add app/controllers/api/v1/accounts/ramon_dashboard_controller.rb app/views/api/v1/accounts/ramon_dashboard/show.json.jbuilder spec/controllers/api/v1/accounts/ramon_dashboard_controller_spec.rb
git commit -m "feat(funil): histórico de 30 dias no endpoint do dashboard"
```

---

### Task 5: Helper de sparkline (função pura testável)

**Files:**
- Create: `app/javascript/dashboard/routes/dashboard/ramon/helpers/sparkline.js`
- Create: `app/javascript/dashboard/routes/dashboard/ramon/helpers/specs/sparkline.spec.js`

**Interfaces:**
- Produces: `sparklinePath(points, { width = 240, height = 40 } = {})` → string do atributo `d` de um `<path>` SVG (`''` se < 2 pontos). Normaliza os valores no eixo Y (min→base, max→topo).

- [ ] **Step 1: Write the failing test**

`app/javascript/dashboard/routes/dashboard/ramon/helpers/specs/sparkline.spec.js`:

```js
import { describe, it, expect } from 'vitest';
import { sparklinePath } from '../sparkline';

describe('sparklinePath', () => {
  it('retorna vazio com menos de 2 pontos', () => {
    expect(sparklinePath([])).toBe('');
    expect(sparklinePath([5])).toBe('');
  });

  it('começa com M e usa L para os demais pontos', () => {
    const d = sparklinePath([1, 2, 3], { width: 200, height: 40 });
    expect(d.startsWith('M')).toBe(true);
    expect((d.match(/L/g) || []).length).toBe(2);
  });

  it('mapeia o maior valor para o topo (y=0) e o menor para a base', () => {
    const d = sparklinePath([0, 10], { width: 100, height: 40 });
    // último ponto (valor 10 = máximo) encosta no topo: y = 0.0
    expect(d.endsWith('0.0')).toBe(true);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx vitest run app/javascript/dashboard/routes/dashboard/ramon/helpers/specs/sparkline.spec.js`
Expected: FAIL — módulo `../sparkline` não existe.

- [ ] **Step 3: Write the helper**

`app/javascript/dashboard/routes/dashboard/ramon/helpers/sparkline.js`:

```js
// Constrói o atributo `d` de um <path> SVG a partir de uma série de números.
// Y normalizado: menor valor na base, maior no topo. Vazio se < 2 pontos.
export function sparklinePath(points, { width = 240, height = 40 } = {}) {
  if (!Array.isArray(points) || points.length < 2) return '';
  const max = Math.max(...points);
  const min = Math.min(...points);
  const range = max - min || 1;
  const stepX = width / (points.length - 1);
  return points
    .map((value, i) => {
      const x = (i * stepX).toFixed(1);
      const y = (height - ((value - min) / range) * height).toFixed(1);
      return `${i === 0 ? 'M' : 'L'}${x},${y}`;
    })
    .join(' ');
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npx vitest run app/javascript/dashboard/routes/dashboard/ramon/helpers/specs/sparkline.spec.js`
Expected: PASS (3 casos).

- [ ] **Step 5: Commit**

```bash
git add app/javascript/dashboard/routes/dashboard/ramon/helpers/sparkline.js app/javascript/dashboard/routes/dashboard/ramon/helpers/specs/sparkline.spec.js
git commit -m "feat(funil): helper sparklinePath (SVG puro, sem dependência)"
```

---

### Task 6: Painel "Funil nos últimos 30 dias" no Centro de Comando

**Files:**
- Create: `app/javascript/dashboard/routes/dashboard/ramon/components/command/Sparkline.vue`
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/pages/CommandCenter.vue`
- Modify: `app/javascript/dashboard/i18n/locale/en/ramon.json`
- Modify: `app/javascript/dashboard/i18n/locale/pt_BR/ramon.json`

**Interfaces:**
- Consumes: `sparklinePath` (Task 5); `data.history` do store `ramonDashboard` (Task 4) — já disponível, pois o store guarda a resposta inteira (`SET_RAMON_DASHBOARD`). **Sem alteração de store/API.**
- Produces: uma nova `<section>` no `CommandCenter.vue` com tabela compacta (data · leads ativos · pipeline) e sparkline do `value_sum`.

- [ ] **Step 1: Write the Sparkline component**

`app/javascript/dashboard/routes/dashboard/ramon/components/command/Sparkline.vue`:

```vue
<script setup>
import { computed } from 'vue';
import { sparklinePath } from '../../helpers/sparkline';

const props = defineProps({
  points: { type: Array, default: () => [] },
  width: { type: Number, default: 240 },
  height: { type: Number, default: 40 },
});

const path = computed(() =>
  sparklinePath(props.points, { width: props.width, height: props.height })
);
</script>

<template>
  <svg
    :width="width"
    :height="height"
    :viewBox="`0 0 ${width} ${height}`"
    class="text-n-iris-9"
  >
    <path
      v-if="path"
      :d="path"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
    />
  </svg>
</template>
```

- [ ] **Step 2: Add i18n keys (en + pt_BR)**

Dentro de `RAMON.COMMAND` em `app/javascript/dashboard/i18n/locale/en/ramon.json`, ao lado de `FUNNEL`/`WEEK`:

```json
"HISTORY": {
  "TITLE": "Funnel over the last 30 days",
  "EMPTY": "No snapshots yet — the first one is captured overnight.",
  "COL_DATE": "Day",
  "COL_LEADS": "Active leads",
  "COL_VALUE": "Pipeline"
}
```

Mesmo bloco em `app/javascript/dashboard/i18n/locale/pt_BR/ramon.json` (traduzido):

```json
"HISTORY": {
  "TITLE": "Funil nos últimos 30 dias",
  "EMPTY": "Ainda sem retratos — o primeiro é capturado na virada do dia.",
  "COL_DATE": "Dia",
  "COL_LEADS": "Leads ativos",
  "COL_VALUE": "Pipeline"
}
```

> Atenção: adicionar vírgula após o bloco anterior (`WEEK`) para o JSON continuar válido.

- [ ] **Step 3: Wire the section into CommandCenter**

Em `app/javascript/dashboard/routes/dashboard/ramon/pages/CommandCenter.vue`:

1. Importar o componente (junto aos outros imports de `components/command`):

```js
import Sparkline from '../components/command/Sparkline.vue';
```

2. Adicionar os computed (perto de `funnel`/`week`):

```js
const history = computed(() => data.value?.history || []);
const historyPoints = computed(() => history.value.map(h => Number(h.value_sum) || 0));
```

3. Adicionar a seção no template, logo após a `<!-- Bloco Semana -->`:

```html
      <!-- Bloco Histórico (Organismo, Onda 0) -->
      <section>
        <h2 class="mb-3 text-sm tracking-widest uppercase text-n-slate-9">
          {{ t('RAMON.COMMAND.HISTORY.TITLE') }}
        </h2>
        <div
          v-if="history.length"
          class="p-4 border rounded-xl border-n-weak bg-n-solid-2"
        >
          <Sparkline :points="historyPoints" :width="320" :height="48" />
          <table class="w-full mt-4 text-sm">
            <thead>
              <tr class="text-xs uppercase text-n-slate-10">
                <th class="py-1 font-normal text-left">
                  {{ t('RAMON.COMMAND.HISTORY.COL_DATE') }}
                </th>
                <th class="py-1 font-normal text-right">
                  {{ t('RAMON.COMMAND.HISTORY.COL_LEADS') }}
                </th>
                <th class="py-1 font-normal text-right">
                  {{ t('RAMON.COMMAND.HISTORY.COL_VALUE') }}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="row in history"
                :key="row.date"
                class="border-t border-n-weak text-n-slate-12"
              >
                <td class="py-1 text-left">{{ row.date }}</td>
                <td class="py-1 text-right">{{ row.leads_count }}</td>
                <td class="py-1 text-right">{{ brl(row.value_sum) }}</td>
              </tr>
            </tbody>
          </table>
        </div>
        <p v-else class="text-sm text-n-slate-10">
          {{ t('RAMON.COMMAND.HISTORY.EMPTY') }}
        </p>
      </section>
```

- [ ] **Step 4: Lint the touched frontend files**

Run: `npx eslint app/javascript/dashboard/routes/dashboard/ramon/pages/CommandCenter.vue app/javascript/dashboard/routes/dashboard/ramon/components/command/Sparkline.vue`
Expected: sem erros (ignorar avisos `Delete ␍`/CRLF de arquivos não tocados — são do checkout Windows, o CI Linux passa limpo).

- [ ] **Step 5: Commit**

```bash
git add app/javascript/dashboard/routes/dashboard/ramon/components/command/Sparkline.vue app/javascript/dashboard/routes/dashboard/ramon/pages/CommandCenter.vue app/javascript/dashboard/i18n/locale/en/ramon.json app/javascript/dashboard/i18n/locale/pt_BR/ramon.json
git commit -m "feat(funil): painel 'Funil nos últimos 30 dias' no Centro de Comando"
```

---

## Deploy e verificação (pós-merge, só com OK do Eduardo)

1. **Migrar antes da imagem** (a migração cria a tabela): `docker compose exec chatwoot-web bundle exec rails db:migrate` no `/opt/intranet-ramon` da VPS.
2. **Subir a imagem** do CI (GHCR): `docker pull ghcr.io/doods-maker/ramon-hub:sha-<7> && docker tag ... :v4.15.1-ramon && docker compose up -d --no-build chatwoot-web chatwoot-worker`.
3. **Dia 0 na hora** (não esperar as 00:05): `docker compose exec chatwoot-web bundle exec rails runner "Ramon::DailyFunnelSnapshotJob.perform_now"`.
4. **Smoke técnico**: hub 200; `GET /api/v1/accounts/<id>/ramon_dashboard` retorna `history` com o dia de hoje.
5. **Smoke visual (Eduardo)**: Centro de Comando mostra a seção "Funil nos últimos 30 dias" com o dia de hoje (1 ponto — a linha ganha forma nos próximos dias).

## Fora de escopo (confirmando a spec)

- Catálogo canônico de `source` (próxima fatia da Onda 0).
- Filtro por tese no painel e endpoint dedicado (Onda 4 — Placar do Dono; o dado gravado já suporta a quebra por tese).
- Reconstrução de dias passados (impossível com fidelidade — é o motivo de começar já).

## Self-review

- **Cobertura da spec:** tabela/modelo (T1) · serviço agregado idempotente (T2) · job + agendamento diário (T3) · leitura mínima com `history` (T4) · sparkline (T5) · painel no Centro de Comando + i18n (T6). Todas as seções §4.1–§4.4 da spec têm task. Deploy/dia-0 cobertos na seção de verificação. ✔
- **Placeholders:** nenhum — todo passo traz código/comando real. ✔
- **Consistência de tipos:** `history` = `{ date, leads_count, value_sum }` no controller (T4), na jbuilder (T4) e consumido no CommandCenter (T6); `sparklinePath(points, {width,height})` definido em T5 e chamado em T5/T6 com a mesma assinatura; `FunnelSnapshot` com as mesmas colunas em T1/T2/T4. ✔
