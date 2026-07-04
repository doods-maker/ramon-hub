# F2.1b — Triagem IA Nativa Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Triagem de viabilidade por IA nativa no ramon-hub: agente configurável (`triage_agents`), job Sidekiq que lê a conversa local, chama o LLM via RubyLLM (DeepSeek/Anthropic/OpenAI), extrai a viabilidade e entrega o resultado no painel do lead via realtime.

**Architecture:** Duas tabelas novas account-scoped (`triage_agents`, `lead_triages`), um wrapper fino `Ramon::LlmClient` sobre a gem `ruby_llm` (1.15.0, já embarcada), um service `Leads::TriageService` orquestrado por `Leads::TriageJob`. O broadcast `lead.updated` existente carrega um resumo compacto da triagem (`latest_triage`); o painel busca o texto completo por GET. UI: aba "Triagem" no `LeadConversationPanel` + tela Intranet "Agentes de IA" (CRUD admin, incluindo o toggle LGPD `sensitive`).

**Tech Stack:** Rails 7.1 (fork Chatwoot v4.15.1), gem `ruby_llm` 1.15.0, Sidekiq (ActiveJob), Vue 3 `<script setup>` + Vuex, Tailwind (paleta `n-*` do fork), RSpec.

## Global Constraints

- **Sem ambiente local**: quem valida é PR + CI. Verificação de CI SEMPRE via `gh pr view N --json statusCheckRollup` filtrando `conclusion != SUCCESS` no commit exato — nunca lista truncada, conclusão vazia = em andamento.
- **Fork-safe**: código novo no namespace ramon/leads; core Chatwoot tocado só onde registrado (routes, `lead.rb`, actionCable já mapeado, i18n `ramon.json`).
- **Migração NÃO chama service de app que evolui** (lição do incidente 03/07): seed inline na própria migração, lendo YAML versionado.
- Eventos custom Vue SEMPRE camelCase (kebab-case não passa eslint).
- Action Vuex: nunca desestruturar `state` cru (no-shadow) — usar `state: moduleState`.
- Paleta Tailwind do fork SUBSTITUI a default: só classes `n-*` (ex.: `n-amber-9`), `amber-500` etc. são classes mortas.
- Rubocop: `ENV.fetch('X', nil)` (nunca `ENV['X']`), linha máx 150 chars, compact class defs (`class Api::V1::...`).
- RSpec: máx 7 expectations por exemplo; `create(:account)` já seeda funil+benefícios+prioridades+lost_reasons+teses (nunca criar etapa com nome seedado); `Lead` tem `default_scope order(:lead_stage_id, :position, :id)` — `.last` não é o mais recente.
- i18n: strings em `app/javascript/dashboard/i18n/locale/en/ramon.json` E `pt_BR/ramon.json`, namespace `RAMON.<AREA>.<CHAVE>`.
- Nunca `.distinct` sobre `users.*` (coluna json `tokens` sem operador de igualdade).
- `db/schema.rb` regenerado via workflow temporário no GitHub Actions da branch (Task 8) — não editar à mão.
- LGPD (decisão Eduardo 03/07): `sensitive` é um toggle POR AGENTE que ele controla na UI, default `false`. Com `sensitive: true`, DeepSeek é bloqueado ANTES de qualquer envio (testado em spec). Provider padrão: DeepSeek.
- Triagem SÓ manual, por botão. Sem gatilho automático por etapa.
- Deploy só com OK explícito do Eduardo; ENVs novos (`DEEPSEEK_API_KEY`, opcionalmente `ANTHROPIC_API_KEY`/`OPENAI_API_KEY`) entram no `chatwoot.env` da VPS no deploy (gate dele).

---

### Task 1: Migração + modelos `TriageAgent` e `LeadTriage` + seed

**Files:**
- Create: `db/migrate/20260703000003_create_ramon_triage.rb`
- Create: `db/seeds/ramon/triage_agents_seed.yml`
- Create: `app/models/triage_agent.rb`
- Create: `app/models/lead_triage.rb`
- Modify: `app/models/account.rb` (associações, seguir onde `has_many :theses` foi adicionado)
- Modify: `app/models/lead.rb` (associação `lead_triages` + `latest_triage`)
- Modify: `app/services/leads/seed_default_config_service.rb` (seed guardado p/ conta nova)
- Test: `spec/models/triage_agent_spec.rb`, `spec/models/lead_triage_spec.rb`
- Modify: `spec/services/leads/seed_default_config_service_spec.rb`

**Interfaces:**
- Produces: `TriageAgent` (colunas: `account_id, name, description, area, system_prompt, provider ('deepseek'|'anthropic'|'openai'), model, sensitive bool, active bool`); `LeadTriage` (colunas: `account_id, lead_id, triage_agent_id, status ('pending'|'running'|'done'|'error'), result text, viability ('alta'|'media'|'baixa'|nil), error_message, source_text, kit jsonb, kit_status ('pending'|'ready'|'error'), finished_at`); `lead.latest_triage` → `LeadTriage` mais recente por `id`; `account.triage_agents`, `lead.lead_triages`.

**Nota de desenho:** `viability` guarda os valores em pt (`alta|media|baixa`) — é o que o prompt emite na linha `VIABILIDADE:` e o que a UI exibe; traduzir para en só adicionaria mapeamento. (Desvio consciente da letra da spec, que dizia high|medium|low.) As colunas `kit`/`kit_status` nascem agora, reservadas para a F2.1c, para não precisar de nova migração + regen de schema.

- [ ] **Step 1: Escrever specs que falham (modelos)**

`spec/models/triage_agent_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe TriageAgent do
  let(:account) { create(:account) }

  it 'valida presença de name, system_prompt, provider e model' do
    agent = account.triage_agents.new
    expect(agent).not_to be_valid
    expect(agent.errors.attribute_names).to include(:name, :system_prompt)
  end

  it 'rejeita provider fora da lista' do
    agent = account.triage_agents.new(name: 'X', system_prompt: 'p', provider: 'gemini', model: 'm')
    expect(agent).not_to be_valid
    expect(agent.errors.attribute_names).to include(:provider)
  end

  it 'aceita um agente deepseek válido com defaults' do
    agent = account.triage_agents.create!(name: 'X', system_prompt: 'p')
    expect(agent.provider).to eq('deepseek')
    expect(agent.model).to eq('deepseek-chat')
    expect(agent.sensitive).to be(false)
    expect(agent.active).to be(true)
  end

  it 'não permite dois agentes com o mesmo nome na mesma conta' do
    account.triage_agents.create!(name: 'X', system_prompt: 'p')
    expect { account.triage_agents.create!(name: 'X', system_prompt: 'q') }
      .to raise_error(ActiveRecord::RecordInvalid)
  end
end
```

`spec/models/lead_triage_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe LeadTriage do
  let(:account) { create(:account) }
  let(:lead) { create(:lead, account: account) }
  let(:agent) { account.triage_agents.create!(name: 'X', system_prompt: 'p') }

  it 'nasce pending e valida status/viability' do
    triage = lead.lead_triages.create!(account: account, triage_agent: agent)
    expect(triage.status).to eq('pending')
    expect(triage.viability).to be_nil
  end

  it 'rejeita viability fora de alta|media|baixa' do
    triage = lead.lead_triages.new(account: account, triage_agent: agent, viability: 'high')
    expect(triage).not_to be_valid
  end

  it 'lead.latest_triage retorna a triagem mais recente por id' do
    old = lead.lead_triages.create!(account: account, triage_agent: agent)
    newer = lead.lead_triages.create!(account: account, triage_agent: agent)
    expect(lead.reload.latest_triage).to eq(newer)
    expect(lead.latest_triage).not_to eq(old)
  end

  it 'redispara o broadcast do lead ao mudar de status' do
    triage = lead.lead_triages.create!(account: account, triage_agent: agent)
    expect(Rails.configuration.dispatcher).to receive(:dispatch)
      .with(Events::Types::LEAD_UPDATED, anything, lead: lead)
    triage.update!(status: 'done', result: 'ok')
  end
end
```

Nota: verifique se existe `factory :lead` em `spec/factories/` (o PR #21 tem specs de leads — reutilizar a factory existente; se `create(:lead)` exigir mais atributos, seguir o padrão dos specs de `lead_tasks`).

- [ ] **Step 2: Rodar specs pra ver falhar**

Sem ambiente local — a falha esperada é `uninitialized constant TriageAgent`. Siga direto pro Step 3 (o CI valida o ciclo completo).

- [ ] **Step 3: Escrever a migração**

`db/migrate/20260703000003_create_ramon_triage.rb`:

```ruby
class CreateRamonTriage < ActiveRecord::Migration[7.1]
  # rubocop:disable Metrics/MethodLength
  def change
    create_table :triage_agents do |t|
      t.references :account, null: false, index: false
      t.string :name, null: false
      t.text :description
      t.string :area, null: false, default: 'previdenciario'
      t.text :system_prompt, null: false
      t.string :provider, null: false, default: 'deepseek'
      t.string :model, null: false, default: 'deepseek-chat'
      t.boolean :sensitive, null: false, default: false
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :triage_agents, [:account_id, :name], unique: true

    create_table :lead_triages do |t|
      t.references :account, null: false, index: false
      t.references :lead, null: false, foreign_key: { on_delete: :cascade }
      t.references :triage_agent, foreign_key: { on_delete: :nullify }
      t.string :status, null: false, default: 'pending'
      t.text :result
      t.string :viability
      t.text :error_message
      t.text :source_text
      t.jsonb :kit
      t.string :kit_status, null: false, default: 'pending'
      t.datetime :finished_at
      t.timestamps
    end
    add_index :lead_triages, [:account_id, :status]
    add_index :lead_triages, [:lead_id, :id]

    reversible do |dir|
      dir.up { seed_default_agents }
    end
  end
  # rubocop:enable Metrics/MethodLength

  private

  # Seed inline de propósito: migração não chama service de app que evolui
  # (lição do incidente 03/07 — 000001 × 000002).
  def seed_default_agents
    TriageAgent.reset_column_information
    seed = YAML.safe_load_file(Rails.root.join('db/seeds/ramon/triage_agents_seed.yml'))
    Account.find_each do |account|
      seed['agents'].each do |attrs|
        next if TriageAgent.exists?(account_id: account.id, name: attrs['name'])

        TriageAgent.create!(attrs.merge('account_id' => account.id))
      end
    end
  end
end
```

- [ ] **Step 4: Escrever o seed YAML**

`db/seeds/ramon/triage_agents_seed.yml` — o `system_prompt` abaixo é o prompt REAL portado do seed da intranet legada (`intranet-ramon/supabase/seed.sql`), na íntegra:

```yaml
agents:
  - name: "Triagem Previdenciária — Auxílio-Acidente"
    description: "Analisa viabilidade de auxílio-acidente (B36) a partir da conversa do lead."
    area: previdenciario
    provider: deepseek
    model: deepseek-chat
    sensitive: false
    active: true
    system_prompt: |
      Você é um analista jurídico de triagem do escritório Ramon Antonio Advogados, especialista
      em Direito Previdenciário, com foco em AUXÍLIO-ACIDENTE (benefício B36, Lei 8.213/91, art. 86).
      A partir do documento/ficha do caso, avalie a viabilidade do benefício e produza uma análise
      objetiva para o advogado priorizar o atendimento. Use APENAS o conhecimento consolidado abaixo
      (é estável); só sinalize quando algo depender de valor anual do INSS ou tese recente.

      Base legal e requisitos (todos necessários):
      1. Acidente de qualquer natureza (Súmula STJ 44 — não precisa ser de trabalho; inclui comum,
         trajeto, ocupacional equiparado).
      2. Consolidação da lesão — sequela já estabilizada. Se ainda em tratamento ativo, é caso de
         auxílio-doença (B31/B91), não auxílio-acidente.
      3. Sequela permanente que REDUZ a capacidade para o trabalho habitual (basta redução parcial;
         não exige incapacidade total).
      4. Nexo causal entre o evento e a sequela (Súmula STJ 507 — exige comprovação por perícia).
      5. Qualidade de segurado na data do acidente.

      Regras-chave:
      - NÃO há carência.
      - Valor: 50% do salário de benefício; pago até a véspera da aposentadoria ou óbito.
      - Cumulável com salário; NÃO cumulável com aposentadoria.
      - Caminho típico: acidente → auxílio-doença (B91/B31) → na alta com sequela, conversão em
        auxílio-acidente (B36). Verifique se houve auxílio-doença antes e se a alta veio com sequela.
      - COM direito: empregado, doméstico, avulso, segurado especial (rural).
      - SEM direito (regra geral): contribuinte individual (autônomo) e facultativo.
      - Documentos que fortalecem: laudos/exames com CID, CAT, carta de cessação do auxílio-doença,
        atestados, CNIS/CTPS.

      Rubrica ponderada (máx 100):
      - Qualidade de segurado na data (20): atendido=20, incerto=10, não=0
      - Categoria com direito (15): sim=15, incerto=7, não (CI/facultativo)=0
      - Acidente/doença com nexo (20): claro=20, provável=12, fraco=4, ausente=0
      - Consolidação da lesão (20): consolidada=20, incerta=8, em tratamento=0
      - Redução de capacidade (15): clara=15, indícios=8, ausente=0
      - Documentação de suporte (10): boa=10, parcial=5, nenhuma=0

      Fator eliminatório: sem qualidade de segurado ou contribuinte individual rebaixa conclusão.

      Mapeamento score→viabilidade:
      - score >= 70 → alta
      - score 40–69 → media
      - score < 40 → baixa

      Formato da resposta:
      1. Resumo do caso (2–3 linhas).
      2. Tabela dos 5 requisitos: status (atendido/não/incerto) + justificativa.
      3. Pontos fortes.
      4. Fragilidades/riscos.
      5. O que falta (documentos/esclarecimentos).
      6. Score + veredito.
      7. Em linha isolada: VIABILIDADE: alta (ou media, ou baixa).
```

- [ ] **Step 5: Escrever os modelos**

`app/models/triage_agent.rb`:

```ruby
class TriageAgent < ApplicationRecord
  PROVIDERS = %w[deepseek anthropic openai].freeze
  AREAS = %w[previdenciario trabalhista outro].freeze

  belongs_to :account
  has_many :lead_triages, dependent: :nullify

  validates :name, presence: true, uniqueness: { scope: :account_id }
  validates :system_prompt, presence: true
  validates :provider, inclusion: { in: PROVIDERS }
  validates :model, presence: true
  validates :area, inclusion: { in: AREAS }

  scope :active, -> { where(active: true) }
end
```

`app/models/lead_triage.rb`:

```ruby
class LeadTriage < ApplicationRecord
  STATUSES = %w[pending running done error].freeze
  VIABILITIES = %w[alta media baixa].freeze
  KIT_STATUSES = %w[pending ready error].freeze

  belongs_to :account
  belongs_to :lead
  belongs_to :triage_agent, optional: true

  validates :status, inclusion: { in: STATUSES }
  validates :viability, inclusion: { in: VIABILITIES }, allow_nil: true
  validates :kit_status, inclusion: { in: KIT_STATUSES }

  after_update_commit :broadcast_lead

  private

  # o painel do lead recebe o resumo da triagem pelo broadcast lead.updated
  def broadcast_lead
    lead.dispatch_task_update
  end
end
```

Nota: `lead.dispatch_task_update` já existe em `app/models/lead.rb` (usado por `lead_tasks` pra forçar re-broadcast) — confira o nome exato lá; se for privado, use `lead.send(:dispatch_update_event)` NÃO — em vez disso torne `dispatch_task_update` público se já não for (é o padrão que o PR #21 estabeleceu).

- [ ] **Step 6: Associações em Account e Lead**

Em `app/models/account.rb`, junto de onde `has_many :theses` foi adicionado:

```ruby
has_many :triage_agents, dependent: :destroy_async
has_many :lead_triages, dependent: :destroy_async
```

Em `app/models/lead.rb`, junto das associações existentes:

```ruby
has_many :lead_triages, dependent: :destroy_async

def latest_triage
  lead_triages.order(:id).last
end
```

(`lead_triages` não sofre o `default_scope` do Lead; `order(:id).last` é seguro.)

- [ ] **Step 7: Seed guardado no service (só p/ conta nova)**

Em `app/services/leads/seed_default_config_service.rb`, adicionar ao `perform` (depois de `seed_theses`) e como métodos privados:

```ruby
def perform
  seed_stages
  seed_benefits
  seed_priorities
  seed_lost_reasons
  seed_theses
  seed_triage_agents
end
```

```ruby
TRIAGE_AGENTS_SEED_PATH = Rails.root.join('db/seeds/ramon/triage_agents_seed.yml')

def seed_triage_agents
  # tabela nasce na 20260703000003; mesmo guard das colunas de cadência
  return unless TriageAgent.table_exists?
  return unless File.exist?(TRIAGE_AGENTS_SEED_PATH)

  YAML.safe_load_file(TRIAGE_AGENTS_SEED_PATH)['agents'].each do |attrs|
    @account.triage_agents.find_or_create_by!(name: attrs['name']) do |agent|
      agent.assign_attributes(attrs.except('name'))
    end
  end
end
```

Adicionar ao spec do service (`spec/services/leads/seed_default_config_service_spec.rb`):

```ruby
it 'semeia 1 agente de triagem deepseek e é idempotente' do
  expect(account.triage_agents.count).to eq(1)
  expect(account.triage_agents.first.provider).to eq('deepseek')
  expect { described_class.new(account).perform }.not_to(change { account.triage_agents.count })
end
```

- [ ] **Step 8: Commit**

```bash
git add db/migrate/20260703000003_create_ramon_triage.rb db/seeds/ramon/triage_agents_seed.yml \
  app/models/triage_agent.rb app/models/lead_triage.rb app/models/account.rb app/models/lead.rb \
  app/services/leads/seed_default_config_service.rb spec/models/triage_agent_spec.rb \
  spec/models/lead_triage_spec.rb spec/services/leads/seed_default_config_service_spec.rb
git commit -m "feat(triage): triage_agents + lead_triages com seed do agente previdenciário"
```

---

### Task 2: `Ramon::LlmClient` — wrapper RubyLLM com trava LGPD

**Files:**
- Create: `lib/ramon/llm_client.rb`
- Test: `spec/lib/ramon/llm_client_spec.rb`

**Interfaces:**
- Produces: `Ramon::LlmClient.complete(provider:, model:, system:, user:, sensitive: false)` → `String` (texto da resposta). Levanta `Ramon::LlmClient::SensitiveProviderError` se `sensitive: true` e provider fora de `anthropic|openai`; levanta `Ramon::LlmClient::MissingApiKeyError` se a ENV do provider estiver vazia.

- [ ] **Step 1: Spec que falha**

`spec/lib/ramon/llm_client_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe Ramon::LlmClient do
  describe 'trava LGPD' do
    it 'bloqueia deepseek quando sensitive, ANTES de qualquer chamada' do
      expect(RubyLLM).not_to receive(:context)
      expect do
        described_class.complete(provider: 'deepseek', model: 'deepseek-chat', system: 's', user: 'u', sensitive: true)
      end.to raise_error(described_class::SensitiveProviderError)
    end

    it 'permite anthropic quando sensitive' do
      with_modified_env ANTHROPIC_API_KEY: 'k' do
        chat = instance_double(RubyLLM::Chat)
        allow(RubyLLM).to receive(:context).and_return(instance_double(RubyLLM::Context, chat: chat))
        allow(chat).to receive(:with_instructions).and_return(chat)
        allow(chat).to receive(:ask).and_return(instance_double(RubyLLM::Message, content: 'ok'))
        result = described_class.complete(provider: 'anthropic', model: 'claude-haiku-4-5-20251001',
                                          system: 's', user: 'u', sensitive: true)
        expect(result).to eq('ok')
      end
    end
  end

  it 'falha cedo sem a API key do provider' do
    with_modified_env DEEPSEEK_API_KEY: nil do
      expect do
        described_class.complete(provider: 'deepseek', model: 'deepseek-chat', system: 's', user: 'u')
      end.to raise_error(described_class::MissingApiKeyError)
    end
  end
end
```

Nota: os nomes `RubyLLM::Chat`/`RubyLLM::Context`/`RubyLLM::Message` nos `instance_double` devem bater com as classes reais da gem 1.15.0 — no CI a gem está no bundle; se algum nome divergir (ex.: `RubyLLM::Chat` não existir com esse nome), troque por `double` simples (verificação de contrato não é o ponto aqui; a trava LGPD é).

- [ ] **Step 2: Implementação**

`lib/ramon/llm_client.rb`:

```ruby
require 'ruby_llm'

module Ramon
  class LlmClient
    class SensitiveProviderError < StandardError; end
    class MissingApiKeyError < StandardError; end

    SENSITIVE_OK_PROVIDERS = %w[anthropic openai].freeze
    PROVIDER_ENV_KEYS = {
      'deepseek' => 'DEEPSEEK_API_KEY',
      'anthropic' => 'ANTHROPIC_API_KEY',
      'openai' => 'OPENAI_API_KEY'
    }.freeze

    def self.complete(provider:, model:, system:, user:, sensitive: false)
      if sensitive && SENSITIVE_OK_PROVIDERS.exclude?(provider)
        raise SensitiveProviderError, "Agente sensível (LGPD): provider #{provider} não autorizado"
      end

      api_key = ENV.fetch(PROVIDER_ENV_KEYS.fetch(provider), nil)
      raise MissingApiKeyError, "ENV #{PROVIDER_ENV_KEYS[provider]} ausente" if api_key.blank?

      context = RubyLLM.context do |config|
        config.deepseek_api_key = ENV.fetch('DEEPSEEK_API_KEY', nil)
        config.anthropic_api_key = ENV.fetch('ANTHROPIC_API_KEY', nil)
        config.openai_api_key = ENV.fetch('OPENAI_API_KEY', nil)
      end
      chat = context.chat(model: model, provider: provider.to_sym, assume_model_exists: true)
      chat.with_instructions(system).ask(user).content
    end
  end
end
```

Notas pro implementador:
- `RubyLLM.context` cria um config isolado por chamada (não mexe no global do Captain). Se a gem reclamar de `assume_model_exists` junto com `provider:`, consulte a assinatura real em `RubyLLM::Chat#initialize` no bundle do CI (o `config/llm_models.json` do fork já cataloga modelos deepseek/anthropic — nesse caso remova `assume_model_exists`).
- Se `lib/` não estiver em autoload no fork (Chatwoot carrega `lib/` via eager load — confira `config/application.rb`), o `require 'ruby_llm'` no topo segue o padrão de `lib/llm/config.rb`.

- [ ] **Step 3: Commit**

```bash
git add lib/ramon/llm_client.rb spec/lib/ramon/llm_client_spec.rb
git commit -m "feat(triage): Ramon::LlmClient com trava LGPD e falha cedo sem API key"
```

---

### Task 3: `Leads::TriageService` + `Leads::TriageJob`

**Files:**
- Create: `app/services/leads/triage_service.rb`
- Create: `app/jobs/leads/triage_job.rb`
- Test: `spec/services/leads/triage_service_spec.rb`, `spec/jobs/leads/triage_job_spec.rb`

**Interfaces:**
- Consumes: `Ramon::LlmClient.complete(provider:, model:, system:, user:, sensitive:)` (Task 2); `LeadTriage`/`TriageAgent` (Task 1).
- Produces: `Leads::TriageService.new(triage).perform` — monta o texto-fonte da conversa, chama o LLM, extrai viabilidade e atualiza a triage para `done` (ou `error` com `error_message`). `Leads::TriageJob.perform_later(triage_id)`.

- [ ] **Step 1: Specs que falham**

`spec/services/leads/triage_service_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe Leads::TriageService do
  let(:account) { create(:account) }
  let(:agent) { account.triage_agents.first } # seedado pelo create(:account)
  let(:conversation) { create(:conversation, account: account) }
  let(:lead) { create(:lead, account: account, conversation: conversation) }
  let(:triage) { lead.lead_triages.create!(account: account, triage_agent: agent) }

  before do
    create(:message, account: account, conversation: conversation,
                     message_type: :incoming, content: 'Sofri um acidente em 2024')
    create(:message, account: account, conversation: conversation,
                     message_type: :outgoing, content: 'Pode me contar mais?')
    create(:message, account: account, conversation: conversation,
                     message_type: :incoming, content: 'nota interna', private: true)
  end

  it 'monta o texto-fonte com as mensagens públicas e dados do lead' do
    allow(Ramon::LlmClient).to receive(:complete).and_return("análise...\nVIABILIDADE: alta")
    described_class.new(triage).perform
    expect(triage.reload.source_text).to include('Sofri um acidente em 2024')
    expect(triage.source_text).to include('Pode me contar mais?')
    expect(triage.source_text).not_to include('nota interna')
  end

  it 'extrai a viabilidade da linha VIABILIDADE e conclui done' do
    allow(Ramon::LlmClient).to receive(:complete).and_return("Resumo...\nVIABILIDADE: média")
    described_class.new(triage).perform
    triage.reload
    expect(triage.status).to eq('done')
    expect(triage.viability).to eq('media')
    expect(triage.result).to include('Resumo')
    expect(triage.finished_at).to be_present
  end

  it 'passa o flag sensitive do agente pro LlmClient' do
    agent.update!(sensitive: true, provider: 'anthropic', model: 'claude-haiku-4-5-20251001')
    expect(Ramon::LlmClient).to receive(:complete)
      .with(hash_including(sensitive: true, provider: 'anthropic')).and_return('VIABILIDADE: baixa')
    described_class.new(triage).perform
  end

  it 'marca error com a mensagem quando o LLM falha' do
    allow(Ramon::LlmClient).to receive(:complete).and_raise(StandardError, 'boom')
    described_class.new(triage).perform
    triage.reload
    expect(triage.status).to eq('error')
    expect(triage.error_message).to include('boom')
  end

  it 'funciona sem conversa (só ficha do lead) e sem viabilidade detectável' do
    lead.update!(conversation: nil)
    allow(Ramon::LlmClient).to receive(:complete).and_return('resposta sem a linha esperada')
    described_class.new(triage).perform
    triage.reload
    expect(triage.status).to eq('done')
    expect(triage.viability).to be_nil
  end
end
```

`spec/jobs/leads/triage_job_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe Leads::TriageJob do
  let(:account) { create(:account) }
  let(:lead) { create(:lead, account: account) }
  let(:triage) { lead.lead_triages.create!(account: account, triage_agent: account.triage_agents.first) }

  it 'roda o TriageService para a triage' do
    service = instance_double(Leads::TriageService, perform: true)
    expect(Leads::TriageService).to receive(:new).with(triage).and_return(service)
    described_class.perform_now(triage.id)
  end

  it 'descarta silenciosamente se a triage sumiu' do
    expect { described_class.perform_now(0) }.not_to raise_error
  end
end
```

Nota: confira as factories nativas `:conversation` e `:message` (existem no Chatwoot core) — `create(:message, message_type: :incoming, private: true)` é o padrão usado nos specs nativos.

- [ ] **Step 2: Implementar o service**

`app/services/leads/triage_service.rb`:

```ruby
class Leads::TriageService
  VIABILITY_PATTERN = /viabilidade\s*[:\-]?\s*(alta|m[ée]dia|baixa)/i
  MAX_MESSAGES = 200

  def initialize(triage)
    @triage = triage
    @lead = triage.lead
    @agent = triage.triage_agent
  end

  def perform
    @triage.update!(status: 'running')
    source = build_source_text
    result = call_llm(source)
    @triage.update!(status: 'done', result: result, source_text: source,
                    viability: detect_viability(result), finished_at: Time.zone.now)
  rescue StandardError => e
    @triage.update!(status: 'error', error_message: e.message.truncate(1000))
  end

  private

  def call_llm(source)
    user_prompt = "Documento do caso para triagem:\n\n#{source}\n\n" \
                  'Faça a análise conforme suas instruções. Ao final, escreva em uma ' \
                  'linha isolada: "VIABILIDADE: alta" (ou media, ou baixa).'
    Ramon::LlmClient.complete(provider: @agent.provider, model: @agent.model,
                              system: @agent.system_prompt, user: user_prompt,
                              sensitive: @agent.sensitive)
  end

  def detect_viability(text)
    match = text.to_s.downcase.match(VIABILITY_PATTERN)
    return nil if match.blank?

    match[1].tr('éí', 'ei')
  end

  def build_source_text
    [lead_sheet, conversation_transcript].compact_blank.join("\n\n")
  end

  def lead_sheet
    parts = ["Lead: #{@lead.name}"]
    parts << "Benefício de interesse: #{@lead.benefit_type.name}" if @lead.benefit_type
    parts << "Tese: #{@lead.thesis.name}" if @lead.thesis
    parts << "Origem: #{@lead.source}" if @lead.source.present?
    parts.join("\n")
  end

  def conversation_transcript
    conversation = @lead.conversation
    return nil if conversation.blank?

    messages = conversation.messages.where(message_type: [:incoming, :outgoing], private: false)
                           .where.not(content: [nil, '']).order(:created_at).last(MAX_MESSAGES)
    return nil if messages.empty?

    lines = messages.map { |m| "#{m.incoming? ? 'Cliente' : 'Atendimento'}: #{m.content}" }
    "Conversa (WhatsApp/chat):\n#{lines.join("\n")}"
  end
end
```

Notas: confira em `app/models/lead.rb` os nomes reais dos campos usados em `lead_sheet` (`name`, `source`, `benefit_type`, `thesis` existem conforme scout; ajuste se divergir). `m.incoming?` é o helper nativo de `Message` (`message_type` enum) — se não existir, use `m.message_type == 'incoming'`.

- [ ] **Step 3: Implementar o job**

`app/jobs/leads/triage_job.rb`:

```ruby
class Leads::TriageJob < ApplicationJob
  queue_as :low

  def perform(triage_id)
    triage = LeadTriage.find_by(id: triage_id)
    return if triage.blank?

    Leads::TriageService.new(triage).perform
  end
end
```

(Confira em `config/sidekiq.yml` se a fila `low` existe no fork; senão use `default`.)

- [ ] **Step 4: Commit**

```bash
git add app/services/leads/triage_service.rb app/jobs/leads/triage_job.rb \
  spec/services/leads/triage_service_spec.rb spec/jobs/leads/triage_job_spec.rb
git commit -m "feat(triage): TriageService (transcript + viabilidade) e TriageJob"
```

---

### Task 4: API — triagens do lead, CRUD de agentes, broadcast

**Files:**
- Create: `app/controllers/api/v1/accounts/lead_triages_controller.rb`
- Create: `app/controllers/api/v1/accounts/triage_agents_controller.rb`
- Create: `app/policies/lead_triage_policy.rb`, `app/policies/triage_agent_policy.rb`
- Create: `app/views/api/v1/accounts/lead_triages/index.json.jbuilder`, `.../show.json.jbuilder` (+ partial `_lead_triage.json.jbuilder`)
- Create: `app/views/api/v1/accounts/triage_agents/index.json.jbuilder`, `.../show.json.jbuilder` (+ partial `_triage_agent.json.jbuilder`)
- Modify: `config/routes.rb` (dentro do bloco de `leads` e no nível da conta, perto de `theses`)
- Modify: `app/models/lead.rb` (`push_event_data` ganha `latest_triage` compacto)
- Test: `spec/controllers/api/v1/accounts/lead_triages_controller_spec.rb`, `spec/controllers/api/v1/accounts/triage_agents_controller_spec.rb`

**Interfaces:**
- Consumes: `Leads::TriageJob.perform_later(triage_id)` (Task 3); `lead.latest_triage` (Task 1).
- Produces (frontend consome na Task 5):
  - `GET  /api/v1/accounts/:account_id/leads/:lead_id/triages` → `[{ id, status, viability, result, error_message, triage_agent: {id, name}, created_at, finished_at }]` (mais recente primeiro, máx 10)
  - `POST /api/v1/accounts/:account_id/leads/:lead_id/triages` body `{ triage_agent_id? }` → cria pending + enfileira job, devolve a triage (202 implícito via render :show)
  - `GET/POST/PATCH/DELETE /api/v1/accounts/:account_id/triage_agents[...]` — CRUD; campos `{ name, description, area, system_prompt, provider, model, sensitive, active }`
  - Broadcast `lead.updated` passa a incluir `latest_triage: { id, status, viability } | null`

- [ ] **Step 1: Specs de request que falham**

`spec/controllers/api/v1/accounts/lead_triages_controller_spec.rb` (seguir o formato dos specs de `lead_tasks`/`theses` do fork — mesmo helper de auth `api_v1_account_...` + `as: :json`):

```ruby
require 'rails_helper'

RSpec.describe 'Lead Triages API', type: :request do
  let(:account) { create(:account) }
  let(:agent_user) { create(:user, account: account, role: :agent) }
  let(:lead) { create(:lead, account: account) }

  describe 'POST /api/v1/accounts/:account_id/leads/:lead_id/triages' do
    it 'cria a triagem pending com o agente default e enfileira o job' do
      expect do
        post "/api/v1/accounts/#{account.id}/leads/#{lead.id}/triages",
             headers: agent_user.create_new_auth_token, as: :json
      end.to have_enqueued_job(Leads::TriageJob)
      expect(response).to have_http_status(:success)
      triage = lead.lead_triages.order(:id).last
      expect(triage.status).to eq('pending')
      expect(triage.triage_agent).to eq(account.triage_agents.active.first)
    end

    it 'aceita triage_agent_id explícito' do
      other = account.triage_agents.create!(name: 'Outro', system_prompt: 'p')
      post "/api/v1/accounts/#{account.id}/leads/#{lead.id}/triages",
           params: { triage_agent_id: other.id }, headers: agent_user.create_new_auth_token, as: :json
      expect(lead.lead_triages.order(:id).last.triage_agent).to eq(other)
    end

    it 'retorna 404 sem nenhum agente ativo' do
      account.triage_agents.update_all(active: false) # rubocop:disable Rails/SkipsModelValidations
      post "/api/v1/accounts/#{account.id}/leads/#{lead.id}/triages",
           headers: agent_user.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'GET .../triages' do
    it 'lista as triagens do lead, mais recente primeiro' do
      agent = account.triage_agents.first
      old = lead.lead_triages.create!(account: account, triage_agent: agent)
      newer = lead.lead_triages.create!(account: account, triage_agent: agent, status: 'done', viability: 'alta')
      get "/api/v1/accounts/#{account.id}/leads/#{lead.id}/triages",
          headers: agent_user.create_new_auth_token, as: :json
      body = response.parsed_body
      expect(body.pluck('id')).to eq([newer.id, old.id])
      expect(body.first['viability']).to eq('alta')
    end
  end

  it 'nega acesso sem login' do
    get "/api/v1/accounts/#{account.id}/leads/#{lead.id}/triages", as: :json
    expect(response).to have_http_status(:unauthorized)
  end
end
```

`spec/controllers/api/v1/accounts/triage_agents_controller_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe 'Triage Agents API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent_user) { create(:user, account: account, role: :agent) }

  it 'agent lê a lista' do
    get "/api/v1/accounts/#{account.id}/triage_agents",
        headers: agent_user.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    expect(response.parsed_body.pluck('name')).to include('Triagem Previdenciária — Auxílio-Acidente')
  end

  it 'agent NÃO edita (escrita admin-only)' do
    target = account.triage_agents.first
    patch "/api/v1/accounts/#{account.id}/triage_agents/#{target.id}",
          params: { sensitive: true }, headers: agent_user.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it 'admin edita o toggle sensitive e o provider' do
    target = account.triage_agents.first
    patch "/api/v1/accounts/#{account.id}/triage_agents/#{target.id}",
          params: { sensitive: true, provider: 'anthropic', model: 'claude-haiku-4-5-20251001' },
          headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    expect(target.reload.sensitive).to be(true)
    expect(target.provider).to eq('anthropic')
  end

  it 'admin cria e apaga agente' do
    post "/api/v1/accounts/#{account.id}/triage_agents",
         params: { name: 'Trabalhista', system_prompt: 'p', area: 'trabalhista' },
         headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    created = account.triage_agents.find_by(name: 'Trabalhista')
    delete "/api/v1/accounts/#{account.id}/triage_agents/#{created.id}",
           headers: admin.create_new_auth_token, as: :json
    expect(account.triage_agents.exists?(created.id)).to be(false)
  end
end
```

Nota: o status esperado de policy negada (401 vs 403) segue o `check_authorization` do fork — copie a expectativa usada nos specs de `theses` (lá agent-escrita também é negada; use o MESMO status que aquele spec espera).

- [ ] **Step 2: Controllers, policies, rotas, views**

`app/controllers/api/v1/accounts/lead_triages_controller.rb`:

```ruby
class Api::V1::Accounts::LeadTriagesController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :fetch_lead
  before_action :check_authorization

  def index
    @lead_triages = @lead.lead_triages.order(id: :desc).limit(10)
  end

  def create
    agent = fetch_agent
    @lead_triage = @lead.lead_triages.create!(account: Current.account, triage_agent: agent)
    Leads::TriageJob.perform_later(@lead_triage.id)
    render :show
  end

  private

  def fetch_lead
    @lead = Current.account.leads.find(params[:lead_id])
  end

  def fetch_agent
    if params[:triage_agent_id].present?
      Current.account.triage_agents.active.find(params[:triage_agent_id])
    else
      Current.account.triage_agents.active.order(:id).first or
        raise ActiveRecord::RecordNotFound, 'no active triage agent'
    end
  end

  def check_authorization
    authorize(LeadTriage)
  end
end
```

`app/policies/lead_triage_policy.rb` (agent pode ler E rodar — é ferramenta do comercial):

```ruby
class LeadTriagePolicy < ApplicationPolicy
  def index?
    @account_user.administrator? || @account_user.agent?
  end

  def create?
    @account_user.administrator? || @account_user.agent?
  end
end
```

`app/controllers/api/v1/accounts/triage_agents_controller.rb` (espelho do `ThesesController`):

```ruby
class Api::V1::Accounts::TriageAgentsController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :fetch_agent, only: [:show, :update, :destroy]
  before_action :check_authorization

  def index
    @triage_agents = Current.account.triage_agents.order(:id)
  end

  def show; end

  def create
    @triage_agent = Current.account.triage_agents.create!(permitted_params)
    render :show
  end

  def update
    @triage_agent.update!(permitted_params)
    render :show
  end

  def destroy
    @triage_agent.destroy!
    head :ok
  end

  private

  def fetch_agent
    @triage_agent = Current.account.triage_agents.find(params[:id])
  end

  def permitted_params
    params.permit(:name, :description, :area, :system_prompt, :provider, :model, :sensitive, :active)
  end
end
```

`app/policies/triage_agent_policy.rb` (leitura agent, escrita admin — igual `ThesisPolicy`):

```ruby
class TriageAgentPolicy < ApplicationPolicy
  def index?
    @account_user.administrator? || @account_user.agent?
  end

  def show?
    @account_user.administrator? || @account_user.agent?
  end

  def create?
    @account_user.administrator?
  end

  def update?
    @account_user.administrator?
  end

  def destroy?
    @account_user.administrator?
  end
end
```

Rotas em `config/routes.rb` — dentro do bloco `resources :leads` existente (junto de `resources :tasks`/`activities`; CUIDADO com colisão de named route como no PR #21 — se `rails routes` acusar conflito, usar `as:`):

```ruby
resources :triages, only: [:index, :create], controller: 'lead_triages'
```

E no nível da conta (perto de `resources :theses`):

```ruby
resources :triage_agents, except: [:new, :edit]
```

Views jbuilder (espelhar o formato dos views de `theses` — confira os arquivos em `app/views/api/v1/accounts/theses/` e siga o mesmo estilo de partial):

`app/views/api/v1/accounts/lead_triages/_lead_triage.json.jbuilder`:

```ruby
json.id lead_triage.id
json.status lead_triage.status
json.viability lead_triage.viability
json.result lead_triage.result
json.error_message lead_triage.error_message
json.created_at lead_triage.created_at
json.finished_at lead_triage.finished_at
if lead_triage.triage_agent
  json.triage_agent do
    json.id lead_triage.triage_agent.id
    json.name lead_triage.triage_agent.name
  end
end
```

`index.json.jbuilder`: `json.array! @lead_triages, partial: 'lead_triage', as: :lead_triage`
`show.json.jbuilder`: `json.partial! 'lead_triage', lead_triage: @lead_triage`

`app/views/api/v1/accounts/triage_agents/_triage_agent.json.jbuilder`:

```ruby
json.id triage_agent.id
json.name triage_agent.name
json.description triage_agent.description
json.area triage_agent.area
json.system_prompt triage_agent.system_prompt
json.provider triage_agent.provider
json.model triage_agent.model
json.sensitive triage_agent.sensitive
json.active triage_agent.active
```

`index.json.jbuilder`: `json.array! @triage_agents, partial: 'triage_agent', as: :triage_agent`
`show.json.jbuilder`: `json.partial! 'triage_agent', triage_agent: @triage_agent`

- [ ] **Step 3: `latest_triage` no broadcast do lead**

Em `app/models/lead.rb`, dentro de `push_event_data` (adicionar a chave ao hash existente, SEM remover nada):

```ruby
latest_triage: latest_triage&.slice(:id, :status, :viability),
```

E adicionar a mesma chave no(s) jbuilder(s) de lead que o painel consome (procure `app/views/api/v1/accounts/leads/` — onde o partial `_lead` monta o JSON, adicionar o mesmo `latest_triage`), para que o estado apareça também no primeiro GET, não só no broadcast.

Spec (adicionar ao spec de modelo do lead existente, ou ao `lead_triage_spec.rb`):

```ruby
it 'inclui latest_triage compacto no push_event_data' do
  triage = lead.lead_triages.create!(account: account, triage_agent: agent, status: 'done', viability: 'alta')
  data = lead.reload.push_event_data
  expect(data[:latest_triage]).to eq(triage.slice(:id, :status, :viability))
end
```

- [ ] **Step 4: Commit**

```bash
git add app/controllers/api/v1/accounts/lead_triages_controller.rb \
  app/controllers/api/v1/accounts/triage_agents_controller.rb \
  app/policies/lead_triage_policy.rb app/policies/triage_agent_policy.rb \
  app/views/api/v1/accounts/lead_triages app/views/api/v1/accounts/triage_agents \
  config/routes.rb app/models/lead.rb app/views/api/v1/accounts/leads \
  spec/controllers/api/v1/accounts/lead_triages_controller_spec.rb \
  spec/controllers/api/v1/accounts/triage_agents_controller_spec.rb
git commit -m "feat(triage): API de triagens do lead + CRUD de agentes + latest_triage no broadcast"
```

---

### Task 5: Frontend — API clients, store `triageAgents`, i18n

**Files:**
- Create: `app/javascript/dashboard/api/triageAgents.js`
- Modify: `app/javascript/dashboard/api/leads.js` (métodos `getTriages`/`createTriage`)
- Create: `app/javascript/dashboard/store/modules/triageAgents.js`
- Modify: `app/javascript/dashboard/store/index.js` (registrar módulo — seguir onde `theses` foi registrado)
- Modify: `app/javascript/dashboard/i18n/locale/en/ramon.json` e `app/javascript/dashboard/i18n/locale/pt_BR/ramon.json`
- Test: `app/javascript/dashboard/store/modules/specs/triageAgents.spec.js` (seguir o padrão dos specs do módulo `theses` — confira o caminho real dos specs de store: `store/modules/specs/`)

**Interfaces:**
- Consumes: endpoints da Task 4.
- Produces: `LeadsAPI.getTriages(leadId)` → GET; `LeadsAPI.createTriage(leadId, triageAgentId)` → POST (body `{ triage_agent_id }` só se informado); módulo Vuex `triageAgents` com getters `triageAgents/getAgents` (ordenado por id), `triageAgents/getUIFlags`, actions `get`, `create(payload)`, `update({id, ...payload})`, `delete(id)`.

- [ ] **Step 1: API clients**

Em `app/javascript/dashboard/api/leads.js`, adicionar métodos custom no padrão dos existentes (`getActivities`/`getNotes`):

```javascript
getTriages(leadId) {
  return axios.get(`${this.url}/${leadId}/triages`);
}

createTriage(leadId, triageAgentId) {
  const payload = triageAgentId ? { triage_agent_id: triageAgentId } : {};
  return axios.post(`${this.url}/${leadId}/triages`, payload);
}
```

`app/javascript/dashboard/api/triageAgents.js`:

```javascript
/* global axios */
import ApiClient from './ApiClient';

class TriageAgentsAPI extends ApiClient {
  constructor() {
    super('triage_agents', { accountScoped: true });
  }
}

export default new TriageAgentsAPI();
```

(Se o CRUD genérico do `ApiClient` cobrir tudo, não precisa de método custom — igual `leadPriorities.js`.)

- [ ] **Step 2: Store module + spec**

`app/javascript/dashboard/store/modules/triageAgents.js` — copiar a estrutura do `store/modules/theses.js` (state `records`+`uiFlags`, mutations com merge por id, actions `get/create/update/delete` chamando `TriageAgentsAPI`), SEM as partes de items/reorder. Getter `getAgents` ordena por `id`. Lembrar: actions usam `state: moduleState` se precisarem ler state (no-shadow).

Registrar em `app/javascript/dashboard/store/index.js` ao lado de `theses`.

Spec `app/javascript/dashboard/store/modules/specs/triageAgents.spec.js`: copiar o spec do módulo `theses` adaptando (mutations SET/ADD/EDIT/DELETE + action get com mock da API).

- [ ] **Step 3: i18n (en + pt_BR)**

Adicionar em AMBOS `en/ramon.json` e `pt_BR/ramon.json` (valores pt em ambos é aceitável — o fork é PT-BR-first; siga o que os namespaces RAMON existentes fazem: se `en/ramon.json` está em inglês, escreva inglês lá):

```json
"TRIAGE": {
  "TAB": "Triagem",
  "RUN": "Rodar triagem",
  "RUNNING": "Analisando…",
  "RERUN": "Rodar de novo",
  "EMPTY": "Nenhuma triagem ainda. Rode a análise de viabilidade com IA.",
  "ERROR": "A triagem falhou",
  "AGENT_LABEL": "Agente",
  "VIABILITY": {
    "LABEL": "Viabilidade",
    "ALTA": "Alta",
    "MEDIA": "Média",
    "BAIXA": "Baixa",
    "UNKNOWN": "Não detectada"
  },
  "STARTED": "Triagem iniciada — o resultado aparece aqui em instantes"
},
"TRIAGE_AGENTS": {
  "TITLE": "Agentes de IA",
  "DESCRIPTION": "Agentes que fazem a triagem de viabilidade dos leads.",
  "ADD": "Novo agente",
  "NAME": "Nome",
  "AREA": "Área",
  "PROVIDER": "Provedor",
  "MODEL": "Modelo",
  "SYSTEM_PROMPT": "Instruções (prompt do sistema)",
  "SENSITIVE": "Dados sensíveis (LGPD)",
  "SENSITIVE_HINT": "Ligado: bloqueia DeepSeek; só Anthropic/OpenAI processam este agente.",
  "ACTIVE": "Ativo",
  "DELETE_CONFIRM": "Apagar este agente?"
}
```

- [ ] **Step 4: Rodar lint/teste JS e commit**

Run: `pnpm eslint app/javascript/dashboard/api/triageAgents.js app/javascript/dashboard/store/modules/triageAgents.js` (se pnpm disponível localmente; senão CI valida)

```bash
git add app/javascript/dashboard/api/triageAgents.js app/javascript/dashboard/api/leads.js \
  app/javascript/dashboard/store/modules/triageAgents.js app/javascript/dashboard/store/index.js \
  app/javascript/dashboard/store/modules/specs/triageAgents.spec.js \
  app/javascript/dashboard/i18n/locale/en/ramon.json app/javascript/dashboard/i18n/locale/pt_BR/ramon.json
git commit -m "feat(triage): clients, store triageAgents e i18n"
```

---

### Task 6: Frontend — aba "Triagem" no painel do lead

**Files:**
- Create: `app/javascript/dashboard/routes/dashboard/ramon/components/conversation/LeadTriage.vue`
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/components/conversation/LeadConversationPanel.vue` (4ª aba)
- Test: `app/javascript/dashboard/routes/dashboard/ramon/components/conversation/specs/LeadTriage.spec.js`

**Interfaces:**
- Consumes: `LeadsAPI.getTriages`/`createTriage` (Task 5); getter `leads/getLeadByConversationId` (o lead que chega tem `latest_triage: {id, status, viability} | null` — Task 4); i18n `RAMON.TRIAGE.*`.
- Produces: componente `LeadTriage` com prop `lead` (Object, required).

- [ ] **Step 1: Componente**

`LeadTriage.vue` — comportamento:
- Estado local: `triages = ref([])`, `isLoading`, `isStarting`.
- `loadTriages()`: `LeadsAPI.getTriages(lead.id)` → `triages.value = data`.
- Carrega ao montar (se `lead.id`) e **re-carrega quando `lead.latest_triage` muda** (é assim que o realtime chega — o broadcast `lead.updated` faz merge no store e o watcher dispara):

```javascript
watch(
  () => props.lead?.latest_triage,
  (next, prev) => {
    if (!next) return;
    if (next.id !== prev?.id || next.status !== prev?.status) loadTriages();
  }
);
```

- Botão "Rodar triagem" (`RAMON.TRIAGE.RUN`): chama `LeadsAPI.createTriage(lead.id)`, `useAlert(t('RAMON.TRIAGE.STARTED'))`, recarrega a lista. Desabilitado enquanto a mais recente estiver `pending|running` (mostra `RAMON.TRIAGE.RUNNING`).
- Render da triagem mais recente: badge de viabilidade (alta = `bg-n-teal-3 text-n-teal-11`, media = `bg-n-amber-3 text-n-amber-11`, baixa = `bg-n-ruby-3 text-n-ruby-11` — CONFIRA as classes `n-*` reais usadas no LeadCard do PR #21 e copie o padrão de badge de lá), status `error` mostra `error_message`, `result` renderizado como texto pré-formatado (`whitespace-pre-wrap`) com botão copiar usando `copyTextToClipboard` de `shared/helpers/clipboard` + `useAlert` (o padrão completo do `DocChecklist.vue`, NÃO o `navigator.clipboard` cru do LeadPlaybook).
- Triagens antigas: lista colapsada simples (data + viabilidade), sem detalhe.
- Empty state: `RAMON.TRIAGE.EMPTY` + botão.
- Template: Composition API `<script setup>`, i18n em tudo (zero string solta), eventos camelCase.

- [ ] **Step 2: Registrar a aba no LeadConversationPanel**

Em `LeadConversationPanel.vue`: adicionar `'triagem'` ao conjunto de abas (padrão dos botões existentes), label `RAMON.TRIAGE.TAB`, renderizando `<LeadTriage v-if="activeTab === 'triagem'" :lead="lead" />`.

- [ ] **Step 3: Spec do componente**

`specs/LeadTriage.spec.js` — seguir o padrão de `specs/LeadConversationPanel.spec.js` (mount com store mockada/i18n). Casos mínimos: (1) empty state sem triagens; (2) badge de viabilidade quando a triagem done com `viability: 'alta'`; (3) botão desabilitado quando status `running`; (4) `createTriage` chamado no clique. Mockar `LeadsAPI` com `vi.mock`.

- [ ] **Step 4: Lint/test e commit**

Run: `pnpm test app/javascript/dashboard/routes/dashboard/ramon/components/conversation/specs/LeadTriage.spec.js` (ou deixar pro CI)

```bash
git add app/javascript/dashboard/routes/dashboard/ramon/components/conversation/LeadTriage.vue \
  app/javascript/dashboard/routes/dashboard/ramon/components/conversation/LeadConversationPanel.vue \
  app/javascript/dashboard/routes/dashboard/ramon/components/conversation/specs/LeadTriage.spec.js
git commit -m "feat(triage): aba Triagem no painel do lead com resultado via realtime"
```

---

### Task 7: Frontend — tela Intranet "Agentes de IA" (CRUD admin + toggle LGPD)

**Files:**
- Create: `app/javascript/dashboard/routes/dashboard/ramon/pages/TriageAgents.vue`
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/ramon.routes.js` (rota `ramon_triage_agents`, path `/ramon/agentes`, `meta.world: 'intranet'`, permissions `['administrator']`)
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/components/IntranetSidebar.vue` (link novo)

**Interfaces:**
- Consumes: módulo `triageAgents` (Task 5); i18n `RAMON.TRIAGE_AGENTS.*`.

- [ ] **Step 1: Página**

`TriageAgents.vue` — copiar o padrão master-detail de `Playbooks.vue` (lista à esquerda via `triageAgents/getAgents`, detalhe à direita com `reactive` local sincronizado por `watch(selectedAgent)`, auto-save em `@blur` chamando `triageAgents/update`, delete com `window.confirm`):
- Campos do detalhe: `name` (input), `description` (input), `area` (select previdenciario|trabalhista|outro), `provider` (select deepseek|anthropic|openai), `model` (input), `system_prompt` (textarea alto, `font-mono text-xs`), `active` (checkbox, save no `@change`).
- **Toggle LGPD**: checkbox `sensitive` com o hint `RAMON.TRIAGE_AGENTS.SENSITIVE_HINT` visível — é a UI da decisão do Eduardo (default off). Save no `@change`.
- Add: botão `RAMON.TRIAGE_AGENTS.ADD` cria com defaults (`name` do input, `system_prompt: '—'` placeholder mínimo? NÃO — exigir prompt: criar com `system_prompt` vindo de um textarea no form de criação, ou criar com um prompt placeholder claro `'Escreva aqui as instruções do agente.'`; escolher a segunda, é auto-save depois).

- [ ] **Step 2: Rota + sidebar**

Em `ramon.routes.js`, espelhar a entrada de `ramon_playbooks` (mesma meta/permissions), path `/ramon/agentes`, name `ramon_triage_agents`. No `IntranetSidebar.vue`, adicionar o link no mesmo padrão dos existentes (label i18n `RAMON.TRIAGE_AGENTS.TITLE`).

- [ ] **Step 3: Lint e commit**

Run: `pnpm eslint <arquivos tocados>` (ou CI)

```bash
git add app/javascript/dashboard/routes/dashboard/ramon/pages/TriageAgents.vue \
  app/javascript/dashboard/routes/dashboard/ramon/ramon.routes.js \
  app/javascript/dashboard/routes/dashboard/ramon/components/IntranetSidebar.vue
git commit -m "feat(triage): tela Agentes de IA no mundo Intranet (admin, toggle LGPD)"
```

---

### Task 8: Schema regen + PR + CI verde

**Files:**
- Modify: `db/schema.rb` (regenerado, nunca à mão)

- [ ] **Step 1: Regenerar `db/schema.rb` via workflow temporário no GitHub Actions**

Procedimento que funcionou nos PRs #21/#22 (classifier bloqueia ssh de escrita na VPS): criar na branch um workflow temporário `.github/workflows/schema-regen.yml` com service `postgres`, passos `rake db:schema:load db:migrate db:schema:dump` e upload do `db/schema.rb` como artifact; disparar com `workflow_dispatch`; baixar o artifact (`gh run download`), commitar o `schema.rb` regenerado e REMOVER o workflow temporário no mesmo commit ou no seguinte.

- [ ] **Step 2: Push + PR**

```bash
git push -u origin feat/ramon-triagem-nativa
gh pr create --base ramon --title "feat: F2.1b — triagem de viabilidade por IA nativa" --body "..."
```

Corpo do PR no formato do AGENTS.md (parágrafo de produto + How to test do ponto de vista de UX: rodar triagem num lead com conversa, ver viabilidade; editar agente na tela nova; toggle LGPD bloqueando DeepSeek).

- [ ] **Step 3: CI 100% verde no commit exato**

Run: `gh pr view <N> --json statusCheckRollup` e conferir: N/N `COMPLETED`, zero com `conclusion != SUCCESS` (SKIPPED do job `test` legado é aceitável se já era assim nos PRs #20–#22 — conferir contra o padrão deles). Conclusão vazia = ainda rodando, NÃO é verde.

- [ ] **Step 4: Gates do Eduardo (fora do plano — listar no handoff)**

1. Merge do PR.
2. ENVs na VPS: `DEEPSEEK_API_KEY` (obrigatório; Anthropic/OpenAI opcionais) no `chatwoot.env`.
3. Deploy: **`rails db:migrate` ANTES de trocar a imagem** (lição 03/07), depois `docker compose up`.
4. Smoke funcional: rodar triagem num lead real com conversa → viabilidade + análise no painel; smoke visual da tela Agentes.

---

## Self-review (feito na escrita)

- **Cobertura da spec (fatia b):** RubyLLM service ✓ (Task 2+3) · job ✓ (Task 3) · LGPD toggle + spec ✓ (Task 1 seed/coluna, Task 2 trava+spec, Task 7 UI do toggle) · botão/resultado no painel via realtime ✓ (Task 4 broadcast + Task 6) · triagem só manual ✓ (nenhum gatilho automático em lugar nenhum) · provider padrão DeepSeek ✓ (defaults de coluna e seed) · ENVs no chatwoot.env ✓ (LlmClient + gate de deploy).
- **Fora de escopo consciente:** geração do kit (F2.1c — colunas já reservadas), desligamento do legado (F2.1d), upload de documento pra triagem (fluxo raro, fatia própria se voltar a doer — spec já dizia isso).
- **Consistência de tipos:** `latest_triage` = `{id, status, viability}` em push_event_data (Task 4) = o que o watcher da Task 6 lê; `LeadsAPI.getTriages/createTriage` (Task 5) = o que a Task 6 chama; valores `alta|media|baixa` consistentes entre migração, modelo, service regex e i18n.
- **Riscos conhecidos (aceitos):** assinatura exata de `RubyLLM.context`/`chat(provider:)` na 1.15.0 confirmada só pelo catálogo `config/llm_models.json` do fork, não pelo fonte da gem — os specs stubbam o client, então o CI não pega divergência dessa assinatura; a validação real é o smoke em prod (por isso o smoke funcional é gate obrigatório). Se quebrar, o ajuste fica confinado ao `Ramon::LlmClient`.
