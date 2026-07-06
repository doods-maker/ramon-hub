# Higiene Técnica do Backend de IA — Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Item 6 (parte de código) do pacote especialista CRM: (1) persistir custo de tokens do LLM em `lead_triages`, (2) retry com backoff nos jobs de triagem/kit para falhas transitórias, (3) tornar o prompt do Kit do Closer editável no banco como o de triagem já é.

**Architecture:** `Ramon::LlmClient.complete` para de descartar o `RubyLLM::Message` e passa a retornar um `Result(content, input_tokens, output_tokens)`; ganha uma exceção `TransientError` para erros de rede/429/5xx. Os dois services (`triage_service`, `kit_service`) gravam os tokens acumulados e deixam `TransientError` subir; os dois jobs ganham `retry_on`. O prompt do kit vira coluna `kit_system_prompt` no mesmo `TriageAgent` (o kit já usa `triage.triage_agent`).

**Tech Stack:** Rails 7.1 (fork Chatwoot v4.15), RubyLLM gem, Sidekiq/ActiveJob, Vue 3 `<script setup>`, RSpec.

## Global Constraints

- Sem Ruby/Postgres local → specs rodam só na CI; escrever spec primeiro (TDD na escrita), implementar, relatar "execução na CI".
- Rubocop: `ENV.fetch` (não `ENV[]`); linha máx 150 chars; `Metrics/AbcSize` Max 26, `MethodLength` (extrair helper se estourar; padrão do fork usa `# rubocop:disable` em `lead.rb#push_event_data`); cop `Performance/BigDecimalWithNumericArgument` (BigDecimal com inteiro, não string, nos specs). RSpec máx 7 expectations por exemplo.
- `create(:account)` seeda o funil e pode seedar agente — spec nunca cria etapa/agente com nome seedado; `Lead`/`LeadTriage` podem ter `default_scope` (checar antes de usar `.last`).
- `db/schema.rb` NUNCA editado à mão — regenerado via workflow temporário do Actions (Task 5, orquestrador). O arquivo do workflow é recuperável de `git show 49efa71bb:.github/workflows/schema-regen.yml`.
- i18n: só `en.json` (frontend) / `en.yml` (backend). Strings do fork em inglês (o bloco `RAMON` do en.json é todo inglês). Tailwind only, sem CSS custom. Eventos Vue camelCase.
- Título do PR = Conventional Commits (check "Validate PR title"); ex.: `feat: higiene tecnica do backend de IA`.
- Commits sem referência a Claude na mensagem (regra do AGENTS.md do fork); trailer `Co-Authored-By` é permitido pelo ambiente da sessão — manter.
- Verificação de CI: `gh pr view N --json statusCheckRollup` filtrando conclusion != SUCCESS/SKIPPED/NEUTRAL — nunca lista truncada.

---

### Task 1: `Ramon::LlmClient` — retorno com usage + `TransientError`

**Files:**
- Modify: `lib/ramon/llm_client.rb`
- Test: `spec/lib/ramon/llm_client_spec.rb`

**Interfaces:**
- Produces: `Ramon::LlmClient::Result = Data.define(:content, :input_tokens, :output_tokens)`; `Ramon::LlmClient::TransientError < StandardError`. `complete(...)` agora retorna um `Result` (antes: `String`). Erros de rede/timeout (sem status HTTP) e status `429`/`5xx` viram `TransientError`; `SensitiveProviderError`/`MissingApiKeyError`/`400`/`401` continuam subindo como estão.

- [ ] **Step 1: Escrever os specs (falhando)**

Ler o spec atual (`spec/lib/ramon/llm_client_spec.rb`) e adaptar. O mock hoje é `instance_double(RubyLLM::Message, content: 'ok')` — passa a precisar de `input_tokens`/`output_tokens`. Casos novos:

```ruby
it 'returns a Result with content and token usage' do
  message = instance_double(RubyLLM::Message, content: 'analise', input_tokens: 120, output_tokens: 45)
  # ... stub da cadeia context.chat(...).with_instructions(...).ask(...) => message
  result = described_class.complete(provider: 'deepseek', model: 'deepseek-chat', system: 's', user: 'u')
  expect(result.content).to eq('analise')
  expect(result.input_tokens).to eq(120)
  expect(result.output_tokens).to eq(45)
end

it 'wraps a 429 from the provider as TransientError' do
  # stub ask para levantar o erro do RubyLLM com status 429 (ver Step 3 p/ a classe/atributo reais)
  expect { described_class.complete(provider: 'deepseek', model: 'm', system: 's', user: 'u') }
    .to raise_error(Ramon::LlmClient::TransientError)
end

it 'wraps a network timeout (no status) as TransientError' do
  # stub ask para levantar erro de rede sem status
  expect { described_class.complete(provider: 'deepseek', model: 'm', system: 's', user: 'u') }
    .to raise_error(Ramon::LlmClient::TransientError)
end

it 'does not wrap a 400 bad request' do
  # stub ask para levantar erro com status 400
  expect { described_class.complete(provider: 'deepseek', model: 'm', system: 's', user: 'u') }
    .to raise_error(an_instance_of(<classe original>).or(satisfy { |e| !e.is_a?(Ramon::LlmClient::TransientError) }))
end
```

Ajustar os stubs da cadeia `context.chat(...).with_instructions(...).ask(...)` ao que o spec atual já faz.

- [ ] **Step 2: Rodar e ver falhar** (CI). Localmente sem Ruby — declarar no report.

- [ ] **Step 3: Implementar**

O implementador DEVE inspecionar a gem RubyLLM (`bundle show ruby_llm` / ler `RubyLLM::Error`) para descobrir a classe base de erro da API e como o status HTTP é exposto (provável `RubyLLM::Error` com `#response` ou `#status`; erros de rede podem ser `Faraday::Error`/timeouts sem status). Implementar o mapeamento por STATUS, não por enumeração frágil de classes:

```ruby
require 'ruby_llm'

class Ramon::LlmClient
  class SensitiveProviderError < StandardError; end
  class MissingApiKeyError < StandardError; end
  class TransientError < StandardError; end

  Result = Data.define(:content, :input_tokens, :output_tokens)

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

    env_key = PROVIDER_ENV_KEYS.fetch(provider)
    api_key = ENV.fetch(env_key, nil)
    raise MissingApiKeyError, "ENV #{env_key} ausente" if api_key.blank?

    message = ask(provider: provider, model: model, system: system, user: user)
    Result.new(content: message.content, input_tokens: message.input_tokens,
               output_tokens: message.output_tokens)
  end

  def self.ask(provider:, model:, system:, user:)
    context = RubyLLM.context do |config|
      config.deepseek_api_key = ENV.fetch('DEEPSEEK_API_KEY', nil)
      config.anthropic_api_key = ENV.fetch('ANTHROPIC_API_KEY', nil)
      config.openai_api_key = ENV.fetch('OPENAI_API_KEY', nil)
    end
    chat = context.chat(model: model, provider: provider.to_sym, assume_model_exists: true)
    chat.with_instructions(system).ask(user)
  rescue StandardError => e
    raise TransientError, e.message if transient?(e)

    raise
  end

  # Transitório = sem status HTTP (rede/timeout) OU 429/5xx. Ajustar o modo de ler
  # o status conforme a API real do erro do RubyLLM (ver bundle show ruby_llm).
  def self.transient?(error)
    status = extract_status(error)
    status.nil? ? network_error?(error) : (status == 429 || status >= 500)
  end
  private_class_method :ask, :transient?
  # extract_status / network_error?: implementar conforme a gem (status via
  # error.response[:status] ou error.status; network via Faraday::TimeoutError etc.)
end
```

Nota: as nossas exceções (`SensitiveProviderError`/`MissingApiKeyError`) são levantadas ANTES de `ask`, então nunca passam por `transient?`.

- [ ] **Step 4: Rodar specs (CI), ver passar.**

- [ ] **Step 5: Commit** — `git commit -m "feat(ramon): LlmClient retorna usage de tokens e classifica erro transitorio"`

---

### Task 2: Persistir custo de tokens em `lead_triages`

**Files:**
- Create: `db/migrate/20260706100001_add_token_usage_to_lead_triages.rb`
- Modify: `app/services/leads/triage_service.rb`, `app/services/leads/kit_service.rb`
- Test: `spec/services/leads/triage_service_spec.rb`, `spec/services/leads/kit_service_spec.rb`

**Interfaces:**
- Consumes: `Ramon::LlmClient::Result` (Task 1).
- Produces: colunas `lead_triages.input_tokens :integer` e `lead_triages.output_tokens :integer` (default 0, null: false), ACUMULADAS entre a chamada da triagem e a do kit para o mesmo registro.

- [ ] **Step 1: Migração**

```ruby
class AddTokenUsageToLeadTriages < ActiveRecord::Migration[7.1]
  def change
    add_column :lead_triages, :input_tokens, :integer, default: 0, null: false
    add_column :lead_triages, :output_tokens, :integer, default: 0, null: false
  end
end
```

- [ ] **Step 2: Specs (falhando)** — no `triage_service_spec.rb`, o mock de `Ramon::LlmClient.complete` agora deve retornar um `Result`. Adaptar os stubs existentes de `complete` para `Ramon::LlmClient::Result.new(content: '...VIABILIDADE: alta', input_tokens: 100, output_tokens: 30)` e adicionar:

```ruby
it 'accumulates token usage from the LLM response' do
  # stub complete => Result.new(content: 'analise VIABILIDADE: alta', input_tokens: 100, output_tokens: 30)
  service.perform
  triage.reload
  expect(triage.input_tokens).to eq(100)
  expect(triage.output_tokens).to eq(30)
end
```

No `kit_service_spec.rb`, o mock de `complete` também passa a retornar `Result` (com `content` = JSON do kit). Adicionar:

```ruby
it 'accumulates kit token usage on top of existing triage usage' do
  triage.update!(input_tokens: 100, output_tokens: 30)
  # stub complete => Result.new(content: '{"resumo_leigo":"..."}', input_tokens: 40, output_tokens: 20)
  service.perform
  triage.reload
  expect(triage.input_tokens).to eq(140)
  expect(triage.output_tokens).to eq(50)
end
```

- [ ] **Step 3: Implementar — triage_service**

`call_llm` retorna agora um `Result`. Ajustar `perform`:

```ruby
def perform
  @triage.update!(status: 'running')
  source = build_source_text
  result = call_llm(source)
  @triage.update!(status: 'done', result: result.content, source_text: source,
                  viability: detect_viability(result.content), finished_at: Time.zone.now)
  record_usage(result)
rescue StandardError => e
  mark_error(e)
end
```

`call_llm` não muda a chamada (só o tipo de retorno). Adicionar privado:

```ruby
def record_usage(result)
  @triage.increment!(:input_tokens, result.input_tokens.to_i)
  @triage.increment!(:output_tokens, result.output_tokens.to_i)
end
```

(`increment!` é atômico e trata o valor atual; kit roda só após triagem `done`, sem concorrência no mesmo registro.)

- [ ] **Step 4: Implementar — kit_service**

`call_llm` retorna `Result`. Em `perform`:

```ruby
def perform
  @triage.update!(kit_status: 'running')
  result = call_llm
  @triage.update!(kit: parse_kit(result.content), kit_status: 'ready')
  record_usage(result)
rescue StandardError => e
  mark_error(e)
end
```

Adicionar o mesmo `record_usage` privado (idêntico ao do triage_service — duplicação de 3 linhas triviais entre dois services independentes; extrair um concern para isso é over-engineering nesta fase). `# ponytail: record_usage duplicado nos 2 services; extrair concern se surgir um 3º consumidor.`

- [ ] **Step 5: Rodar specs (CI), ver passar.**

- [ ] **Step 6: Commit** — `git commit -m "feat(ramon): persiste custo de tokens da triagem e do kit em lead_triages"`

---

### Task 3: Retry com backoff nos jobs de triagem/kit

**Files:**
- Modify: `app/services/leads/triage_service.rb`, `app/services/leads/kit_service.rb` (deixar `TransientError` subir)
- Modify: `app/jobs/leads/triage_job.rb`, `app/jobs/leads/kit_job.rb`
- Test: `spec/jobs/leads/triage_job_spec.rb`, `spec/jobs/leads/kit_job_spec.rb` (criar se não existirem, no padrão de outros job specs do fork)

**Interfaces:**
- Consumes: `Ramon::LlmClient::TransientError` (Task 1).
- Produces: em falha transitória, o service re-levanta `TransientError`; o job re-tenta 3× com backoff e, ao esgotar, marca o registro como erro. Falhas definitivas continuam virando status `error` dentro do service (sem retry).

- [ ] **Step 1: Services deixam `TransientError` subir**

Em `triage_service.rb` e `kit_service.rb`, colocar um rescue específico ANTES do `rescue StandardError`:

```ruby
rescue Ramon::LlmClient::TransientError
  raise
rescue StandardError => e
  mark_error(e)
end
```

- [ ] **Step 2: Specs dos jobs (falhando)** — verificar se `spec/jobs/leads/` já tem specs; criar no padrão do fork. Exemplos:

```ruby
# triage_job_spec.rb
it 'retries on TransientError' do
  allow_any_instance_of(Leads::TriageService).to receive(:perform)
    .and_raise(Ramon::LlmClient::TransientError)
  expect(described_class).to receive(:retry_job).at_least(:once) # ou assert via perform_enqueued_jobs
  # padrão real conforme os job specs existentes do fork
end

it 'marks the triage as error after retries are exhausted' do
  # com attempts esgotadas, o registro fica status 'error'
end
```

Adaptar ao helper de job do fork (provável `perform_enqueued_jobs` / `ActiveJob::TestHelper`). Se o padrão de assert de retry do fork for outro, seguir os specs de jobs vizinhos.

- [ ] **Step 3: Implementar — triage_job**

```ruby
class Leads::TriageJob < ApplicationJob
  queue_as :low

  retry_on Ramon::LlmClient::TransientError, wait: :polynomially_longer, attempts: 3 do |job, error|
    triage = LeadTriage.find_by(id: job.arguments.first)
    triage&.update(status: 'error', error_message: error.message.truncate(1000))
  end

  def perform(triage_id)
    triage = LeadTriage.find_by(id: triage_id)
    return if triage.blank?

    Leads::TriageService.new(triage).perform
  end
end
```

- [ ] **Step 4: Implementar — kit_job** (mesmo padrão, mas marca `kit_status`):

```ruby
class Leads::KitJob < ApplicationJob
  queue_as :low

  retry_on Ramon::LlmClient::TransientError, wait: :polynomially_longer, attempts: 3 do |job, error|
    triage = LeadTriage.find_by(id: job.arguments.first)
    triage&.update(kit_status: 'error', error_message: error.message.truncate(1000))
  end

  def perform(triage_id)
    triage = LeadTriage.find_by(id: triage_id)
    return if triage.blank?

    Leads::KitService.new(triage).perform
  end
end
```

Nota: `:polynomially_longer` é o nome no Rails 7.1 (`:exponentially_longer` foi deprecado). Se a CI reclamar, usar `:exponentially_longer`.

- [ ] **Step 5: Rodar specs (CI), ver passar.**

- [ ] **Step 6: Commit** — `git commit -m "feat(ramon): retry com backoff em falha transitoria de LLM nos jobs de triagem e kit"`

---

### Task 4: Prompt do Kit editável no banco (`TriageAgent#kit_system_prompt`)

**Files:**
- Create: `db/migrate/20260706100002_add_kit_system_prompt_to_triage_agents.rb`
- Modify: `app/services/leads/kit_service.rb` (renomear constante + ler do agente)
- Modify: `app/controllers/api/v1/accounts/triage_agents_controller.rb` (`permitted_params`)
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/pages/TriageAgents.vue`
- Modify: `app/javascript/dashboard/i18n/locale/en/ramon.json`
- Modify: seed do TriageAgent (procurar `db/seeds/ramon/` ou `Leads::SeedDefaultConfigService` — o seed que cria o agente semente)
- Test: `spec/services/leads/kit_service_spec.rb`

**Interfaces:**
- Produces: coluna `triage_agents.kit_system_prompt :text`; `Leads::KitService::KIT_SYSTEM_PROMPT_DEFAULT` (constante renomeada de `SYSTEM_PROMPT`); o kit usa `@agent.kit_system_prompt.presence || KIT_SYSTEM_PROMPT_DEFAULT`.

- [ ] **Step 1: Migração com backfill dos agentes existentes**

```ruby
class AddKitSystemPromptToTriageAgents < ActiveRecord::Migration[7.1]
  def up
    add_column :triage_agents, :kit_system_prompt, :text
    TriageAgent.reset_column_information
    TriageAgent.where(kit_system_prompt: nil)
               .update_all(kit_system_prompt: Leads::KitService::KIT_SYSTEM_PROMPT_DEFAULT)
  end

  def down
    remove_column :triage_agents, :kit_system_prompt
  end
end
```

(Backfill usa a constante do service — aceitável aqui porque o valor default vive no código e não muda por migração.)

- [ ] **Step 2: Spec (falhando)** — no `kit_service_spec.rb`:

```ruby
it 'uses the agent kit_system_prompt when present' do
  agent.update!(kit_system_prompt: 'PROMPT CUSTOM DO KIT')
  expect(Ramon::LlmClient).to receive(:complete)
    .with(hash_including(system: 'PROMPT CUSTOM DO KIT'))
    .and_return(Ramon::LlmClient::Result.new(content: '{"resumo_leigo":"x"}', input_tokens: 1, output_tokens: 1))
  service.perform
end

it 'falls back to the default kit prompt when the agent has none' do
  agent.update_column(:kit_system_prompt, nil)
  expect(Ramon::LlmClient).to receive(:complete)
    .with(hash_including(system: Leads::KitService::KIT_SYSTEM_PROMPT_DEFAULT))
    .and_return(Ramon::LlmClient::Result.new(content: '{"resumo_leigo":"x"}', input_tokens: 1, output_tokens: 1))
  service.perform
end
```

- [ ] **Step 3: Implementar — kit_service**

Renomear `SYSTEM_PROMPT` → `KIT_SYSTEM_PROMPT_DEFAULT` (mesmo texto). Em `call_llm`:

```ruby
def call_llm
  Ramon::LlmClient.complete(provider: @agent.provider, model: @agent.model,
                            system: @agent.kit_system_prompt.presence || KIT_SYSTEM_PROMPT_DEFAULT,
                            user: user_prompt, sensitive: @agent.sensitive)
end
```

- [ ] **Step 4: Seed** — no seed que cria o agente semente, incluir `kit_system_prompt: Leads::KitService::KIT_SYSTEM_PROMPT_DEFAULT` (para agentes novos já nascerem com o texto editável). Ler o seed antes; se ele usa `find_or_create_by`/atributos explícitos, adicionar o campo no mesmo estilo.

- [ ] **Step 5: Controller** — em `permitted_params` de `triage_agents_controller.rb`, adicionar `:kit_system_prompt` à lista `params.permit(...)`.

- [ ] **Step 6: UI — TriageAgents.vue**

Espelhar o campo `system_prompt` (linha ~261 tem o textarea com `v-model="detail.system_prompt"`; `openDetail` popula em ~linha 43; `save` despacha em ~linha 76-83). Adicionar:
- No estado `detail`: `kit_system_prompt`.
- No `openDetail`/populate: `detail.kit_system_prompt = agent.kit_system_prompt || ''`.
- Um `<textarea v-model="detail.kit_system_prompt">` com label i18n, logo após o de `system_prompt`, mesmas classes Tailwind.
- No `store.dispatch('triageAgents/update', {...})`: incluir `kit_system_prompt: detail.kit_system_prompt`.
- Conferir se o create (não só update) também manda o campo, se a tela cria agentes.

i18n em `en.json` (bloco do agente, seguir a chave do `SYSTEM_PROMPT` existente):

```json
"KIT_SYSTEM_PROMPT_LABEL": "Kit prompt (Closer)"
```

(String em inglês, consistente com o arquivo. Ajustar a chave exata ao namespace real onde vive o label do system_prompt.)

- [ ] **Step 7: Rodar specs (CI) + `npx prettier --write` nos arquivos JS/Vue tocados.**

- [ ] **Step 8: Commit** — `git commit -m "feat(ramon): prompt do Kit do Closer editavel por agente no banco"`

---

### Task 5 (ORQUESTRADOR — não delegar): schema.rb, PR e CI

- [ ] **Step 1: Regenerar `db/schema.rb`** via workflow temporário do Actions: restaurar `git show 49efa71bb:.github/workflows/schema-regen.yml` na branch, push, `gh workflow run schema-regen.yml --ref <branch>`, aguardar, `gh run download` do artifact, copiar `schema.rb`, `git rm` do workflow, commitar schema + remoção juntos. (Duas migrações nesta branch: `20260706100001` e `20260706100002`.)
- [ ] **Step 2: Abrir PR** com título `feat: higiene tecnica do backend de IA` e `--body-file` (aspas em here-string quebram o parsing no PowerShell).
- [ ] **Step 3: CI verde de verdade** — check-runs do COMMIT exato via `gh pr view N --json statusCheckRollup`, contar completed + zero não-success (SKIPPED/NEUTRAL ok).
- [ ] **Step 4: Gate do Eduardo** — merge + deploy (imagem GHCR `sha-<7>` do workflow "Publica imagem do fork (GHCR)" → tag `v4.15.1-ramon` → `up -d --no-build`), com `rails db:migrate` ANTES de trocar a imagem (2 migrações). Smoke: rodar triagem+kit num lead → ver `input_tokens`/`output_tokens` gravados; editar o prompt do kit na tela Agentes e ver o kit usar o texto novo.

---

## Fora deste plano (item 6, partes com gate — registrar, não codar)

- **Templates HSM de retomada na Meta:** exige textos aprovados pelo Eduardo + submissão à Meta (dias de espera). Gate do Eduardo — fora daqui.
- **Meta Lead Ads → endpoint público (webhook leadgen):** a própria spec diz "não fazer agora" (só quando o tráfego escalar).

## Decisões de arquitetura registradas

- **Tokens acumulados (2 colunas totais), não separados triagem/kit:** o objetivo é medir custo de IA por lead; granularidade por etapa é YAGNI. Upgrade: colunas separadas se surgir a necessidade.
- **`kit_system_prompt` no mesmo `TriageAgent`, não um "agente do kit" separado:** o kit já usa `triage.triage_agent`; fase de 1 agente semente. Upgrade: entidade própria se o kit precisar de provider/model/sensitive diferentes da triagem.
- **Retry por status HTTP (429/5xx/rede), não por enumeração de classes:** mais robusto a mudanças da gem. `expire_orphan_triages` (pending/running > 10min → error) segue como rede de segurança independente.
