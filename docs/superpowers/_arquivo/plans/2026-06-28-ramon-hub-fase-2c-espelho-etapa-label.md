# Fase 2C — Espelho etapa ↔ label `fase-*` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Espelhar bidirecionalmente a etapa do `Lead` no funil e uma etiqueta `fase-*` na conversa do Chatwoot (mover no Kanban etiqueta a conversa; etiquetar a conversa move o lead).

**Architecture:** Mapa canônico fixo numa coluna `lead_stages.label`; as `fase-*` são Labels nativas do Chatwoot semeadas junto das etapas. Um serviço puro `Ramon::StageLabelSync` faz os dois sentidos com guarda de igualdade (anti-loop); dois ganchos no `RamonLeadListener` (já registrado no `AsyncDispatcher`) disparam cada sentido. Backfill aplica nas conversas dos leads existentes no deploy.

**Tech Stack:** Rails 7.1, acts_as_taggable_on (labels do Chatwoot), Wisper (eventos/listeners), RSpec. Fork `ramon-hub` (Chatwoot v4.15.1), branch `ramon`.

## Global Constraints

- **Sem ambiente local** (sem Ruby/Postgres/Docker na máquina do Eduardo). Verificação = feature branch → PR → CI `run_foss_spec` (rspec+vitest+rubocop+eslint). Os comandos `bundle exec rspec` abaixo rodam **no CI**, não localmente.
- **Título de Label do Chatwoot:** validado por `\A[\p{L}\p{N}]+[\p{L}\p{N}_-]+\Z` e **forçado a minúsculas**. Separador = **hífen** (`fase-novo`); `:` é inválido.
- **Edições de fork merge-safe:** preferir arquivos novos no namespace `ramon/`; só editar pontos de registro já mapeados (`SeedDefaultConfigService`, `RamonLeadListener`). Nunca tocar `enterprise/`.
- **CI carrega schema via `db:schema:load`** (não roda migrations) → **commitar `db/schema.rb` regenerado** (via banco scratch na VPS; produção intacta). Imagem do fork é slim (usar `sh`, não `bash`).
- **Build GHCR não roda lint** → rodar `npx prettier@3.3.3 --write` em arquivos novos e zerar errors de rubocop/eslint antes do PR.
- **Regra de aprovação:** Claude redige/propõe; push/merge/deploy são do Eduardo (ou Claude com "ok" explícito dele, como nas fases anteriores).

## File Structure

- `app/services/leads/seed_default_config_service.rb` — **modificar**: STAGES ganha `label:`+`color:`; `perform` grava/atualiza `label` nas etapas e cria as Labels `fase-*`.
- `app/services/ramon/stage_label_sync.rb` — **criar**: serviço puro, dois sentidos + guarda de igualdade + exclusividade.
- `app/services/ramon/stage_label_backfill.rb` — **criar**: aplica `fase-*` nas conversas dos leads existentes.
- `app/listeners/ramon_lead_listener.rb` — **modificar**: `lead_created`/`lead_updated` → `apply_to_conversation`; `conversation_updated` → `apply_to_lead`.
- `db/migrate/20260628000003_add_label_to_lead_stages.rb` — **criar**: coluna+índice; re-roda o seed pra backfillar labels das etapas e criar as Labels.
- `db/migrate/20260628000004_backfill_lead_conversation_labels.rb` — **criar**: chama o backfill nas conversas.
- `db/schema.rb` — **regenerar** (via scratch DB).
- Specs: `spec/services/leads/seed_default_config_service_spec.rb` (modificar), `spec/services/ramon/stage_label_sync_spec.rb` (criar), `spec/services/ramon/stage_label_backfill_spec.rb` (criar), `spec/listeners/ramon_lead_listener_spec.rb` (modificar).

---

### Task 1: Coluna canônica `lead_stages.label` + Labels semeadas

**Files:**
- Modify: `app/services/leads/seed_default_config_service.rb`
- Create: `db/migrate/20260628000003_add_label_to_lead_stages.rb`
- Test: `spec/services/leads/seed_default_config_service_spec.rb`

**Interfaces:**
- Consumes: nada novo.
- Produces:
  - `Leads::SeedDefaultConfigService::STAGES` — array de hashes com `:name, :label, :color, :is_won, :is_lost`.
  - `Leads::SeedDefaultConfigService#perform` — idempotente; grava/atualiza `lead_stages.label` e cria `Label` `fase-*` (title=label, color, show_on_sidebar:true).
  - `lead_stages.label` (string, nullable) com índice único `(account_id, label)`.

- [ ] **Step 1: Escrever os testes que falham** (adicionar ao spec existente, dentro do `RSpec.describe Leads::SeedDefaultConfigService`)

```ruby
  it 'grava a label canônica em cada etapa semeada' do
    account = create(:account)
    expect(account.lead_stages.find_by(name: 'Novo').label).to eq('fase-novo')
    expect(account.lead_stages.find_by(name: 'Qualificação').label).to eq('fase-qualificacao')
    expect(account.lead_stages.find_by(name: 'Última chance').label).to eq('fase-ultima-chance')
  end

  it 'cria as Labels nativas fase-* (uma por etapa)' do
    account = create(:account)
    titles = account.labels.pluck(:title)
    expect(titles).to include('fase-novo', 'fase-qualificacao', 'fase-fechado', 'fase-perdido')
    expect(account.labels.find_by(title: 'fase-novo').show_on_sidebar).to be(true)
  end

  it 'é idempotente (re-rodar não duplica labels nem etapas)' do
    account = create(:account)
    expect { described_class.new(account).perform }
      .to not_change { account.lead_stages.count }.and not_change { account.labels.count }
  end
```

- [ ] **Step 2: Rodar e ver falhar**

Run (CI): `bundle exec rspec spec/services/leads/seed_default_config_service_spec.rb`
Expected: FAIL — `label` é `nil` / Labels `fase-*` não existem.

- [ ] **Step 3: Modificar o `SeedDefaultConfigService`**

Substituir a constante `STAGES` e o método `perform`, adicionando `ensure_stage_labels`:

```ruby
class Leads::SeedDefaultConfigService
  STAGES = [
    { name: 'Novo', label: 'fase-novo', color: '#6b7280', is_won: false, is_lost: false },
    { name: 'Qualificação', label: 'fase-qualificacao', color: '#3b82f6', is_won: false, is_lost: false },
    { name: 'Reunião agendada', label: 'fase-reuniao-agendada', color: '#8b5cf6', is_won: false, is_lost: false },
    { name: 'Reunião realizada', label: 'fase-reuniao-realizada', color: '#06b6d4', is_won: false, is_lost: false },
    { name: 'Negociação', label: 'fase-negociacao', color: '#f59e0b', is_won: false, is_lost: false },
    { name: 'Última chance', label: 'fase-ultima-chance', color: '#ef4444', is_won: false, is_lost: false },
    { name: 'Fechado', label: 'fase-fechado', color: '#22c55e', is_won: true, is_lost: false },
    { name: 'Perdido', label: 'fase-perdido', color: '#71717a', is_won: false, is_lost: true }
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
    seed_stages
    ensure_stage_labels
    seed_benefits
    seed_priorities
  end

  # Cria as Labels nativas do Chatwoot para cada etapa que tem `label`.
  # Pública para o backfill da migração reusar em contas já existentes.
  def ensure_stage_labels
    @account.lead_stages.where.not(label: [nil, '']).find_each do |stage|
      @account.labels.find_or_create_by!(title: stage.label) do |label|
        label.color = self.class.color_for(stage.label)
        label.show_on_sidebar = true
      end
    end
  end

  def self.color_for(label)
    STAGES.find { |s| s[:label] == label }&.dig(:color) || '#1f93ff'
  end

  private

  def seed_stages
    STAGES.each_with_index do |attrs, i|
      stage = @account.lead_stages.find_or_create_by!(name: attrs[:name]) do |s|
        s.position = i
        s.is_won = attrs[:is_won]
        s.is_lost = attrs[:is_lost]
        s.label = attrs[:label]
      end
      stage.update!(label: attrs[:label]) if stage.label != attrs[:label]
    end
  end

  def seed_benefits
    BENEFITS.each_with_index do |name, i|
      @account.benefit_types.find_or_create_by!(name: name) { |b| b.position = i }
    end
  end

  def seed_priorities
    PRIORITIES.each_with_index do |attrs, i|
      @account.lead_priorities.find_or_create_by!(name: attrs[:name]) do |p|
        p.weight = attrs[:weight]
        p.position = i
      end
    end
  end
end
```

- [ ] **Step 4: Criar a migração**

`db/migrate/20260628000003_add_label_to_lead_stages.rb`:

```ruby
class AddLabelToLeadStages < ActiveRecord::Migration[7.1]
  def up
    add_column :lead_stages, :label, :string
    add_index :lead_stages, [:account_id, :label], unique: true, name: 'index_lead_stages_on_account_id_and_label'

    # Backfill: grava labels nas etapas existentes e cria as Labels fase-*.
    # perform é idempotente (find_or_create + update do label).
    Account.find_each { |account| Leads::SeedDefaultConfigService.new(account).perform }
  end

  def down
    remove_index :lead_stages, name: 'index_lead_stages_on_account_id_and_label'
    remove_column :lead_stages, :label
  end
end
```

- [ ] **Step 5: Rodar e ver passar**

Run (CI): `bundle exec rspec spec/services/leads/seed_default_config_service_spec.rb`
Expected: PASS (3 novos exemplos verdes).

- [ ] **Step 6: Commit**

```bash
git add app/services/leads/seed_default_config_service.rb \
        db/migrate/20260628000003_add_label_to_lead_stages.rb \
        spec/services/leads/seed_default_config_service_spec.rb
git commit -m "feat(2c): coluna canônica lead_stages.label + Labels fase-* semeadas"
```

---

### Task 2: Serviço de sincronia `Ramon::StageLabelSync`

**Files:**
- Create: `app/services/ramon/stage_label_sync.rb`
- Test: `spec/services/ramon/stage_label_sync_spec.rb`

**Interfaces:**
- Consumes: `Lead#conversation`, `Lead#lead_stage`, `LeadStage#label` (Task 1); `Conversation#label_list`, `Conversation#update_labels` (acts_as_taggable); `Account#leads`, `Account#lead_stages`.
- Produces:
  - `Ramon::StageLabelSync.apply_to_conversation(lead)` — seta a `fase-*` da etapa do lead na conversa, removendo outras `fase-*`; no-op se já igual / sem conversa / sem label.
  - `Ramon::StageLabelSync.apply_to_lead(conversation, added_labels)` — move o lead da conversa pra etapa da `fase-*` adicionada (última, se várias) e remove outras `fase-*`; no-op se nenhuma `fase-*` adicionada / sem lead / sem stage / já igual.
  - `Ramon::StageLabelSync::FASE_PREFIX` = `'fase-'`.

- [ ] **Step 1: Escrever os testes que falham**

`spec/services/ramon/stage_label_sync_spec.rb`:

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ramon::StageLabelSync do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:novo) { account.lead_stages.find_by(label: 'fase-novo') }
  let(:qualif) { account.lead_stages.find_by(label: 'fase-qualificacao') }

  describe '.apply_to_conversation' do
    it 'aplica a fase-* da etapa na conversa' do
      lead = create(:lead, account: account, lead_stage: novo, conversation: conversation)
      described_class.apply_to_conversation(lead)
      expect(conversation.reload.label_list).to contain_exactly('fase-novo')
    end

    it 'troca a fase-* antiga pela nova, preservando labels não-fase' do
      conversation.update_labels(%w[urgente fase-novo])
      lead = create(:lead, account: account, lead_stage: qualif, conversation: conversation)
      described_class.apply_to_conversation(lead)
      expect(conversation.reload.label_list).to contain_exactly('urgente', 'fase-qualificacao')
    end

    it 'é no-op quando já está igual (guarda de igualdade)' do
      conversation.update_labels(%w[fase-novo])
      lead = create(:lead, account: account, lead_stage: novo, conversation: conversation)
      expect { described_class.apply_to_conversation(lead) }
        .not_to(change { conversation.reload.label_list.sort })
    end

    it 'é no-op quando o lead não tem conversa' do
      lead = create(:lead, account: account, lead_stage: novo, conversation: nil)
      expect { described_class.apply_to_conversation(lead) }.not_to raise_error
    end
  end

  describe '.apply_to_lead' do
    it 'move o lead pra etapa da fase-* adicionada' do
      lead = create(:lead, account: account, lead_stage: novo, conversation: conversation)
      described_class.apply_to_lead(conversation, ['fase-qualificacao'])
      expect(lead.reload.lead_stage).to eq(qualif)
    end

    it 'self-heal: remove outras fase-* deixando só a adicionada' do
      lead = create(:lead, account: account, lead_stage: novo, conversation: conversation)
      conversation.update_labels(%w[fase-novo fase-qualificacao])
      described_class.apply_to_lead(conversation, ['fase-qualificacao'])
      expect(conversation.reload.label_list).to contain_exactly('fase-qualificacao')
      expect(lead.reload.lead_stage).to eq(qualif)
    end

    it 'ignora quando nenhuma fase-* foi adicionada' do
      lead = create(:lead, account: account, lead_stage: novo, conversation: conversation)
      expect { described_class.apply_to_lead(conversation, ['urgente']) }
        .not_to(change { lead.reload.lead_stage_id })
    end

    it 'no-op quando a conversa não tem lead' do
      expect { described_class.apply_to_lead(conversation, ['fase-novo']) }.not_to raise_error
    end

    it 'é no-op quando o lead já está na etapa (guarda de igualdade)' do
      lead = create(:lead, account: account, lead_stage: qualif, conversation: conversation)
      conversation.update_labels(%w[fase-qualificacao])
      expect { described_class.apply_to_lead(conversation, ['fase-qualificacao']) }
        .not_to(change { lead.reload.updated_at })
    end
  end
end
```

- [ ] **Step 2: Rodar e ver falhar**

Run (CI): `bundle exec rspec spec/services/ramon/stage_label_sync_spec.rb`
Expected: FAIL — `uninitialized constant Ramon::StageLabelSync`.

- [ ] **Step 3: Implementar o serviço**

`app/services/ramon/stage_label_sync.rb`:

```ruby
# frozen_string_literal: true

module Ramon
  # Espelha, nos dois sentidos, a etapa do Lead e a label `fase-*` da conversa.
  # Guarda de igualdade em cada sentido evita loop: o eco da volta encontra
  # tudo igual e morre.
  class StageLabelSync
    FASE_PREFIX = 'fase-'

    # Lead -> conversa: garante que a conversa tenha exatamente a fase-* da etapa.
    def self.apply_to_conversation(lead)
      conversation = lead.conversation
      target = lead.lead_stage&.label
      return if conversation.nil? || target.blank?

      set_conversation_fase(conversation, target)
    end

    # Conversa -> lead: a fase-* adicionada (última, se várias) define a etapa.
    def self.apply_to_lead(conversation, added_labels)
      added_fase = Array(added_labels).map(&:to_s).select { |l| l.start_with?(FASE_PREFIX) }
      return if added_fase.empty?

      target = added_fase.last
      account = conversation.account
      lead = account.leads.find_by(conversation_id: conversation.id)
      return if lead.nil?

      stage = account.lead_stages.find_by(label: target)
      return if stage.nil?

      lead.update!(lead_stage: stage) unless lead.lead_stage_id == stage.id
      set_conversation_fase(conversation, target)
    end

    # Mantém na conversa as labels não-fase + exatamente `target`. No-op se já igual.
    def self.set_conversation_fase(conversation, target)
      current = conversation.label_list
      current_fase = current.select { |l| l.to_s.start_with?(FASE_PREFIX) }
      return if current_fase == [target]

      keep = current.reject { |l| l.to_s.start_with?(FASE_PREFIX) }
      conversation.update_labels(keep + [target])
    end
  end
end
```

- [ ] **Step 4: Rodar e ver passar**

Run (CI): `bundle exec rspec spec/services/ramon/stage_label_sync_spec.rb`
Expected: PASS (todos os exemplos verdes).

- [ ] **Step 5: Commit**

```bash
git add app/services/ramon/stage_label_sync.rb spec/services/ramon/stage_label_sync_spec.rb
git commit -m "feat(2c): Ramon::StageLabelSync (espelho bidirecional etapa<->fase-*)"
```

---

### Task 3: Listeners (disparam os dois sentidos)

**Files:**
- Modify: `app/listeners/ramon_lead_listener.rb`
- Test: `spec/listeners/ramon_lead_listener_spec.rb`

**Interfaces:**
- Consumes: `Ramon::StageLabelSync.apply_to_conversation` / `.apply_to_lead` (Task 2); `event.data[:lead]` (eventos `lead.created`/`lead.updated`); `event.data[:conversation]` e `event.data[:changed_attributes]` (evento `conversation.updated`, formato `{ 'label_list' => [antiga, nova], ... }`).
- Produces: `RamonLeadListener#lead_created`, `#lead_updated`, `#conversation_updated`.

- [ ] **Step 1: Escrever os testes que falham** (adicionar ao spec existente)

```ruby
  describe '#lead_updated -> etiqueta a conversa' do
    it 'aplica a fase-* da etapa do lead na conversa' do
      lead = create(:lead, account: account, lead_stage: account.lead_stages.find_by(label: 'fase-novo'),
                           conversation: conversation, contact: contact)
      lead.update!(lead_stage: account.lead_stages.find_by(label: 'fase-qualificacao'))
      ev = Events::Base.new('lead.updated', Time.zone.now, lead: lead)
      listener.lead_updated(ev)
      expect(conversation.reload.label_list).to contain_exactly('fase-qualificacao')
    end
  end

  describe '#conversation_updated -> move o lead' do
    it 'move o lead pra etapa da fase-* adicionada' do
      lead = create(:lead, account: account, lead_stage: account.lead_stages.find_by(label: 'fase-novo'),
                           conversation: conversation, contact: contact)
      ev = Events::Base.new('conversation.updated', Time.zone.now,
                            conversation: conversation,
                            changed_attributes: { 'label_list' => [[], ['fase-qualificacao']] })
      listener.conversation_updated(ev)
      expect(lead.reload.lead_stage).to eq(account.lead_stages.find_by(label: 'fase-qualificacao'))
    end

    it 'ignora quando label_list não mudou' do
      lead = create(:lead, account: account, lead_stage: account.lead_stages.find_by(label: 'fase-novo'),
                           conversation: conversation, contact: contact)
      ev = Events::Base.new('conversation.updated', Time.zone.now,
                            conversation: conversation,
                            changed_attributes: { 'status' => %w[open resolved] })
      expect { listener.conversation_updated(ev) }.not_to(change { lead.reload.lead_stage_id })
    end
  end
```

- [ ] **Step 2: Rodar e ver falhar**

Run (CI): `bundle exec rspec spec/listeners/ramon_lead_listener_spec.rb`
Expected: FAIL — `NoMethodError: undefined method 'lead_updated'`.

- [ ] **Step 3: Adicionar os métodos ao `RamonLeadListener`**

Adicionar dentro da classe (mantendo o `conversation_created` existente):

```ruby
  def lead_created(event)
    Ramon::StageLabelSync.apply_to_conversation(event.data[:lead])
  end

  def lead_updated(event)
    Ramon::StageLabelSync.apply_to_conversation(event.data[:lead])
  end

  def conversation_updated(event)
    conversation = event.data[:conversation]
    changes = event.data[:changed_attributes]
    return if changes.blank?

    label_change = changes['label_list'] || changes[:label_list]
    return if label_change.blank?

    old_labels, new_labels = label_change
    added = Array(new_labels) - Array(old_labels)
    Ramon::StageLabelSync.apply_to_lead(conversation, added)
  end
```

- [ ] **Step 4: Rodar e ver passar**

Run (CI): `bundle exec rspec spec/listeners/ramon_lead_listener_spec.rb`
Expected: PASS (exemplos antigos + 3 novos verdes).

- [ ] **Step 5: Commit**

```bash
git add app/listeners/ramon_lead_listener.rb spec/listeners/ramon_lead_listener_spec.rb
git commit -m "feat(2c): listeners de lead/conversa disparam o espelho etapa<->label"
```

---

### Task 4: Backfill das conversas existentes

**Files:**
- Create: `app/services/ramon/stage_label_backfill.rb`
- Create: `db/migrate/20260628000004_backfill_lead_conversation_labels.rb`
- Test: `spec/services/ramon/stage_label_backfill_spec.rb`

**Interfaces:**
- Consumes: `Ramon::StageLabelSync.apply_to_conversation` (Task 2); `Account#leads`.
- Produces: `Ramon::StageLabelBackfill.perform` (todas as contas) e `#perform` (uma conta).

- [ ] **Step 1: Escrever o teste que falha**

`spec/services/ramon/stage_label_backfill_spec.rb`:

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ramon::StageLabelBackfill do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }

  it 'aplica a fase-* da etapa atual em cada lead com conversa' do
    conv = create(:conversation, account: account, contact: contact)
    create(:lead, account: account, lead_stage: account.lead_stages.find_by(label: 'fase-qualificacao'),
                  conversation: conv, contact: contact)
    described_class.new(account).perform
    expect(conv.reload.label_list).to contain_exactly('fase-qualificacao')
  end

  it 'ignora leads sem conversa' do
    create(:lead, account: account, lead_stage: account.lead_stages.find_by(label: 'fase-novo'), conversation: nil)
    expect { described_class.new(account).perform }.not_to raise_error
  end
end
```

- [ ] **Step 2: Rodar e ver falhar**

Run (CI): `bundle exec rspec spec/services/ramon/stage_label_backfill_spec.rb`
Expected: FAIL — `uninitialized constant Ramon::StageLabelBackfill`.

- [ ] **Step 3: Implementar o serviço**

`app/services/ramon/stage_label_backfill.rb`:

```ruby
# frozen_string_literal: true

module Ramon
  # Aplica, uma vez, a label fase-* da etapa atual em cada lead que já tem conversa.
  class StageLabelBackfill
    def self.perform
      Account.find_each { |account| new(account).perform }
    end

    def initialize(account)
      @account = account
    end

    def perform
      @account.leads.where.not(conversation_id: nil).find_each do |lead|
        Ramon::StageLabelSync.apply_to_conversation(lead)
      end
    end
  end
end
```

- [ ] **Step 4: Criar a migração**

`db/migrate/20260628000004_backfill_lead_conversation_labels.rb`:

```ruby
class BackfillLeadConversationLabels < ActiveRecord::Migration[7.1]
  def up
    Ramon::StageLabelBackfill.perform
  end

  def down
    # Sem rollback de dados: as labels fase-* podem ser removidas manualmente se necessário.
  end
end
```

- [ ] **Step 5: Rodar e ver passar**

Run (CI): `bundle exec rspec spec/services/ramon/stage_label_backfill_spec.rb`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/services/ramon/stage_label_backfill.rb \
        db/migrate/20260628000004_backfill_lead_conversation_labels.rb \
        spec/services/ramon/stage_label_backfill_spec.rb
git commit -m "feat(2c): backfill aplica fase-* nas conversas dos leads existentes"
```

---

### Task 5: Schema, lint e PR (verificação por CI)

**Files:**
- Modify: `db/schema.rb` (regenerado via scratch DB)

**Interfaces:** nenhuma (tarefa de fechamento).

- [ ] **Step 1: Regenerar `db/schema.rb` via banco scratch na VPS** (produção intacta)

```sh
ssh -i ~/.ssh/id_ed25519 root@185.194.216.67 \
  "cd /opt/intranet-ramon && docker compose run --rm \
    -e POSTGRES_DATABASE=ramon_schema_scratch3 \
    -e DISABLE_DATABASE_ENVIRONMENT_CHECK=1 \
    chatwoot-web sh -lc \
    'bundle exec rails db:create db:schema:load db:migrate db:schema:dump'"
```
Copiar o `db/schema.rb` resultante de volta pro working tree (deve conter `lead_stages.label` + índice `index_lead_stages_on_account_id_and_label`, versão `2026_06_28_000004`). Conferir que NÃO há diffs de produção (scratch é descartável; dropar depois).

- [ ] **Step 2: Lint** (o build GHCR não roda lint)

Run: `npx prettier@3.3.3 --write app/services/ramon/ app/listeners/ramon_lead_listener.rb`
Run (CI confere): `bundle exec rubocop app/services/ramon app/services/leads/seed_default_config_service.rb app/listeners/ramon_lead_listener.rb db/migrate/20260628000003_add_label_to_lead_stages.rb db/migrate/20260628000004_backfill_lead_conversation_labels.rb`
Zerar **errors** (warnings da base do Chatwoot são aceitos). Se a migração estourar `Metrics/*`, usar `# rubocop:disable`/`enable` pontual como nas 2A/2B.

- [ ] **Step 3: Commit do schema + lint**

```bash
git add db/schema.rb app/services/ramon app/listeners/ramon_lead_listener.rb app/services/leads/seed_default_config_service.rb
git commit -m "chore(2c): regenera schema + prettier/rubocop"
```

- [ ] **Step 4: Push da branch + abrir PR pra `ramon`** (Eduardo, ou Claude com ok)

```bash
git push -u origin feat/ramon-hub-2c-espelho-etapa-label
gh pr create --base ramon --title "Fase 2C — espelho etapa <-> label fase-*" \
  --body "Espelho bidirecional etapa do funil <-> label fase-* da conversa. Ver plano 2026-06-28-ramon-hub-fase-2c."
```
Esperar o CI `run_foss_spec` (rspec+vitest+rubocop+eslint) ficar **verde**. Corrigir o que o CI achar (lição das fases: bugs que só aparecem em runtime/CI).

- [ ] **Step 5: Merge + deploy + smoke** (Eduardo, ou Claude com ok)

Após merge na `ramon` e build GHCR verde:
```sh
ssh -i ~/.ssh/id_ed25519 root@185.194.216.67 \
  "cd /opt/intranet-ramon && docker compose pull chatwoot-web chatwoot-worker && \
   docker compose run --rm chatwoot-web sh -lc 'bundle exec rails db:migrate' && \
   docker compose up -d chatwoot-web chatwoot-worker"
```
**Smoke (Eduardo):** mover um lead no Kanban → a conversa ganha o chip `fase-*` (e perde o antigo); adicionar `fase-qualificacao` numa conversa → o lead anda no Kanban e a conversa fica com uma só `fase-*`. Conferir que os leads existentes já vieram com a label da etapa atual (backfill).

---

## Self-Review

**Cobertura do spec:**
- Convenção/dados (coluna `label`, Labels nativas) → Task 1. ✔
- Mapa canônico fixo (coluna, estável a renomear) → Task 1. ✔
- Motor `StageLabelSync` (dois sentidos + exclusividade) → Task 2. ✔
- Anti-loop (guarda de igualdade) → Task 2 (`set_conversation_fase` no-op + guarda no lead) + teste de no-op. ✔
- Listeners (Lead→conversa, Conversa→lead) → Task 3. ✔
- Backfill no deploy → Task 4. ✔
- Casos de borda (sem conversa / sem lead / remover única / duas fase-*) → Tasks 2 e 3 (testes). ✔
- Testes via CI + schema scratch + prettier → Tasks 1-5. ✔
- "Remover a única fase-*" = no-op: coberto pela lógica (added vazio → no-op); sem teste dedicado de remoção no listener — **adicionado** abaixo como nota: o teste `ignora quando nenhuma fase-* foi adicionada` (Task 2) cobre o caminho do serviço; o listener só chama com `added`, então remoção (added sem fase) é no-op por construção.

**Placeholders:** nenhum TBD/TODO; todo passo tem código/comando real.

**Consistência de tipos:** `apply_to_conversation(lead)`, `apply_to_lead(conversation, added_labels)`, `set_conversation_fase(conversation, target)`, `FASE_PREFIX`, `ensure_stage_labels`, `color_for(label)`, `StageLabelBackfill.perform`/`#perform` — usados igualzinho entre tasks. ✔

## Fora de escopo (fatias futuras)
- **2D:** ao criar/renomear etapa na UI, gerar/atualizar a Label `fase-*` (gancho pelo mapa canônico).
- **2E:** campos custom do Lead.
- Chip de fase estilizado no card do Kanban.
