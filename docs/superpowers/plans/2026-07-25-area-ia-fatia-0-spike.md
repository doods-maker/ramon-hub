# Área de IA própria — Fatia 0 (spike) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Provar, ponta a ponta e o mais barato possível, que o Captain do fork roda com DeepSeek V4 e encadeia duas tools nossas do AdvBox — antes de investir nas Fatias 1–3.

**Architecture:** O Captain já existe inteiro no fork. Esta fatia (a) impede que o reconcile diário do plano community desligue o Captain, (b) ensina a camada LLM do Captain a falar com o provider `deepseek` que o RubyLLM já conhece, (c) acrescenta duas tools nativas em Ruby sobre o `Ramon::AdvboxClient` que já está em produção, e (d) deixa um roteiro de operação para ligar tudo na VPS e rodar o teste real. Nenhuma tool HTTP `CustomTool` é criada.

**Tech Stack:** Rails 7 / Ruby · RSpec · gem `ai-agents` 0.10.0 (`Agents::Tool`) · `ruby_llm` 1.15.0 · DeepSeek V4 · AdvBox API v1.

**Spec:** `docs/superpowers/specs/2026-07-25-area-ia-propria-design.md`
**Worktree:** `ramon-hub-wt-ia` · branch `feat/ramon-area-ia`

## Achados que mudaram o plano (feitos antes de escrevê-lo)

- **Risco 1 da spec está MORTO.** `config/llm_models.json` já traz quatro modelos com `provider: deepseek` — `deepseek-chat`, `deepseek-reasoner`, `deepseek-v4-flash`, `deepseek-v4-pro` — todos com `function_calling` e contexto de 1M. Os dois V4 declaram também `structured_output`. Nada a registrar.
- **Surgiu um problema menor no lugar dele.** Como o registry resolve `deepseek-*` para o provider `deepseek`, o RubyLLM vai procurar `config.deepseek_api_key` — e `lib/llm/config.rb` (a camada do Captain) só configura `openai_api_key`/`openai_api_base`. Falta uma linha. O `Ramon::LlmClient` já faz certo em `lib/ramon/llm_client.rb:46`; é copiar o padrão. Vira a Task 2.
- **Consequência boa:** não é preciso gravar `CAPTAIN_OPEN_AI_ENDPOINT` nem `CAPTAIN_OPEN_AI_API_KEY`. Só o modelo. A env `DEEPSEEK_API_KEY` já existe na VPS.
- **Modelo escolhido:** `deepseek-v4-pro` — é o V4 que o Eduardo citou, e `structured_output` é justamente o que sustenta o encadeamento de tools. `deepseek-v4-flash` tem as mesmas capabilities e é mais barato; trocar é mudar um `InstallationConfig`.

## Global Constraints

- **DeepSeek é o único provedor. Não configurar, sugerir ou codar fallback anthropic/openai.** Decisão do Eduardo em 25/07.
- Tudo em `enterprise/` continua permitido apenas onde este plano manda (Eduardo dispensou a regra para uso interno; precedente do branding, PR #82).
- Toda tool nova é **nível leitura** — nesta fatia nenhuma tool escreve em sistema algum.
- O id da tool no `config/agents/tools.yml` é resolvido por `tool_id.classify` → `Captain::Tools::{PascalCase}Tool`. **`classify` singulariza a última palavra**: usar ids cuja última palavra já seja singular (`..._advbox`, nunca `..._processos`).
- Mensagens de retorno das tools vão para o LLM: sempre `String`.
- `Ramon::AdvboxClient` levanta `RequestError` (4xx, com `code`/`body`) e `UnavailableError` (rede/TLS). Toda tool trata as duas — erro de integração **nunca** sobe como exceção para o runner do agente.
- Rodar specs com `bundle exec rspec <arquivo>`.
- Commits com `--no-verify`: o hook do husky não existe dentro de worktree (lição registrada do projeto).

---

### Task 1: Manter o Captain ligado sob o plano community

O `Internal::ReconcilePlanConfigService#reconcile_premium_features` roda no plano community e chama `account.disable_features!(*premium_features)` em **toda** conta, lendo `enterprise/config/premium_features.yml`. Com `captain_integration` nessa lista, ligar o Captain hoje significa vê-lo desligado amanhã. É o mesmo mecanismo que resetava a logo da banca (PR #82) e o fix é o mesmo: virar a fonte.

**Files:**
- Modify: `enterprise/config/premium_features.yml`
- Test: `spec/enterprise/services/internal/reconcile_plan_config_service_spec.rb`

**Interfaces:**
- Consumes: nada.
- Produces: nada em código. Efeito: contas mantêm `captain_integration` habilitado após o reconcile.

- [ ] **Step 1: Verificar se o spec do serviço já existe**

Run: `ls spec/enterprise/services/internal/reconcile_plan_config_service_spec.rb`

Se **não** existir, criar com o conteúdo do Step 2. Se existir, acrescentar apenas o bloco `describe` novo, sem tocar no resto.

- [ ] **Step 2: Escrever o teste que falha**

```ruby
require 'rails_helper'

RSpec.describe Internal::ReconcilePlanConfigService do
  describe 'captain no plano community' do
    let(:account) { create(:account) }

    before do
      allow(ChatwootHub).to receive(:pricing_plan).and_return('community')
    end

    it 'nao desliga captain_integration no reconcile diario' do
      account.enable_features!('captain_integration')
      account.save!

      described_class.new.perform

      expect(account.reload.feature_enabled?('captain_integration')).to be(true)
    end

    it 'continua desligando as demais features premium' do
      account.enable_features!('audit_logs')
      account.save!

      described_class.new.perform

      expect(account.reload.feature_enabled?('audit_logs')).to be(false)
    end
  end
end
```

- [ ] **Step 3: Rodar o teste e confirmar que falha**

Run: `bundle exec rspec spec/enterprise/services/internal/reconcile_plan_config_service_spec.rb -e "nao desliga captain_integration no reconcile diario"`
Expected: FAIL — `expected true, got false`.

O exemplo do `audit_logs` deve PASSAR já nesta rodada. Ele é a rede de segurança contra apagar a linha errada.

- [ ] **Step 4: Remover a linha do YAML**

`enterprise/config/premium_features.yml` fica exatamente assim:

```yaml
# List of the premium features in EE edition
- disable_branding
- audit_logs
- sla
- custom_roles
- csat_review_notes
- conversation_required_attributes
```

- [ ] **Step 5: Rodar o arquivo inteiro e confirmar verde**

Run: `bundle exec rspec spec/enterprise/services/internal/reconcile_plan_config_service_spec.rb`
Expected: PASS em todos os exemplos, incluindo os pré-existentes.

- [ ] **Step 6: Commit**

```bash
git add enterprise/config/premium_features.yml spec/enterprise/services/internal/reconcile_plan_config_service_spec.rb
git commit --no-verify -m "feat: mantem captain_integration ligado sob plano community"
```

---

### Task 2: `Llm::Config` fala com o provider deepseek

`lib/llm/config.rb` só configura credencial OpenAI. Como `deepseek-v4-pro` resolve para o provider `deepseek` no registry, o RubyLLM procura `config.deepseek_api_key` e não encontra. Uma linha, espelhando o que `Ramon::LlmClient` já faz.

**Files:**
- Modify: `lib/llm/config.rb`
- Test: `spec/lib/llm/config_spec.rb`

**Interfaces:**
- Consumes: `ENV['DEEPSEEK_API_KEY']` (já presente na VPS, usada por `Ramon::LlmClient`).
- Produces: após `Llm::Config.initialize!`, `RubyLLM.config.deepseek_api_key` devolve a chave. Nenhuma assinatura pública muda.

- [ ] **Step 1: Escrever o teste que falha**

Criar `spec/lib/llm/config_spec.rb` (se já existir, acrescentar o `describe`):

```ruby
require 'rails_helper'

RSpec.describe Llm::Config do
  describe '.initialize!' do
    before { described_class.reset! }

    after { described_class.reset! }

    it 'configura a credencial do deepseek a partir da env' do
      with_modified_env DEEPSEEK_API_KEY: 'chave-de-teste' do
        described_class.initialize!

        expect(RubyLLM.config.deepseek_api_key).to eq('chave-de-teste')
      end
    end

    it 'nao quebra quando a env do deepseek esta ausente' do
      with_modified_env DEEPSEEK_API_KEY: nil do
        expect { described_class.initialize! }.not_to raise_error
      end
    end
  end
end
```

`with_modified_env` é o helper já usado nos specs do repo. Se a suíte reclamar que ele não existe neste contexto, conferir como os specs de `Ramon::LlmClient` o carregam e seguir o mesmo caminho.

- [ ] **Step 2: Rodar e confirmar que falha**

Run: `bundle exec rspec spec/lib/llm/config_spec.rb`
Expected: FAIL no primeiro exemplo — `deepseek_api_key` vem `nil`.

- [ ] **Step 3: Implementar**

Em `lib/llm/config.rb`, dentro de `configure_ruby_llm`, acrescentar a linha do deepseek:

```ruby
    def configure_ruby_llm
      RubyLLM.configure do |config|
        config.openai_api_key = system_api_key if system_api_key.present?
        config.openai_api_base = openai_endpoint.chomp('/') if openai_endpoint.present?
        # O registry resolve deepseek-* para o provider :deepseek, que pede a
        # credencial propria — mesma env que Ramon::LlmClient ja usa.
        config.deepseek_api_key = ENV.fetch('DEEPSEEK_API_KEY', nil)
        config.model_registry_file = Rails.root.join('config/llm_models.json').to_s
        config.logger = Rails.logger
      end
    end
```

Nada mais no arquivo muda. `legacy_base_open_ai_service.rb` (PDF/files) fica intocado — não é usado pelo agente.

- [ ] **Step 4: Rodar o teste e confirmar verde**

Run: `bundle exec rspec spec/lib/llm/config_spec.rb`
Expected: PASS, 2 exemplos.

- [ ] **Step 5: Commit**

```bash
git add lib/llm/config.rb spec/lib/llm/config_spec.rb
git commit --no-verify -m "feat: Llm::Config configura credencial do deepseek"
```

---

### Task 3: Tool `buscar_processo_advbox`

Primeira das duas tools do encadeamento. Recebe nome **ou** CPF e devolve os processos do AdvBox, para o agente extrair o `id` que a Task 4 consome.

**Files:**
- Create: `enterprise/lib/captain/tools/buscar_processo_advbox_tool.rb`
- Modify: `config/agents/tools.yml`
- Test: `spec/enterprise/lib/captain/tools/buscar_processo_advbox_tool_spec.rb`

**Interfaces:**
- Consumes: `Ramon::AdvboxClient.lawsuits(params_hash)` → `Array<Hash>`; erros `Ramon::AdvboxClient::RequestError` (com `#code`) e `Ramon::AdvboxClient::UnavailableError`.
- Produces: `Captain::Tools::BuscarProcessoAdvboxTool#perform(tool_context, nome: nil, cpf: nil)` → `String` (JSON de array, ou frase de erro/vazio). Id de tool registrado: `buscar_processo_advbox`.

- [ ] **Step 1: Escrever o teste que falha**

Criar `spec/enterprise/lib/captain/tools/buscar_processo_advbox_tool_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe Captain::Tools::BuscarProcessoAdvboxTool, type: :model do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:tool) { described_class.new(assistant) }
  let(:tool_context) { Struct.new(:state).new({}) }

  describe '#perform' do
    it 'busca por cpf e devolve os processos em json' do
      allow(Ramon::AdvboxClient).to receive(:lawsuits)
        .with(identification: '52998224725', limit: 10)
        .and_return([{ 'id' => 42, 'process_number' => '5001234-56.2026.4.04.7200' }])

      result = tool.perform(tool_context, cpf: '529.982.247-25')

      expect(JSON.parse(result).first['id']).to eq(42)
    end

    it 'busca por nome quando nao ha cpf' do
      allow(Ramon::AdvboxClient).to receive(:lawsuits)
        .with(name: 'Maria', limit: 10)
        .and_return([])

      expect(tool.perform(tool_context, nome: 'Maria')).to eq('Nenhum processo encontrado no AdvBox.')
    end

    it 'exige ao menos um criterio' do
      expect(tool.perform(tool_context)).to eq('Informe o nome ou o CPF para buscar.')
    end

    it 'devolve mensagem quando o advbox recusa' do
      allow(Ramon::AdvboxClient).to receive(:lawsuits)
        .and_raise(Ramon::AdvboxClient::RequestError.new(422, 'erro'))

      expect(tool.perform(tool_context, nome: 'Maria')).to eq('O AdvBox recusou a consulta (HTTP 422).')
    end

    it 'devolve mensagem quando o advbox esta fora do ar' do
      allow(Ramon::AdvboxClient).to receive(:lawsuits)
        .and_raise(Ramon::AdvboxClient::UnavailableError)

      expect(tool.perform(tool_context, nome: 'Maria')).to eq('O AdvBox nao respondeu agora. Tente de novo em instantes.')
    end
  end
end
```

- [ ] **Step 2: Rodar e confirmar que falha**

Run: `bundle exec rspec spec/enterprise/lib/captain/tools/buscar_processo_advbox_tool_spec.rb`
Expected: FAIL — `uninitialized constant Captain::Tools::BuscarProcessoAdvboxTool`.

- [ ] **Step 3: Implementar a tool**

Criar `enterprise/lib/captain/tools/buscar_processo_advbox_tool.rb`:

```ruby
# Leitura pura no AdvBox: encontra os processos da pessoa para o agente poder
# pedir o dossie de um deles (consultar_dossie_advbox).
class Captain::Tools::BuscarProcessoAdvboxTool < Captain::Tools::BasePublicTool
  description 'Busca processos no AdvBox por nome do cliente ou CPF. Devolve id, numero e partes de cada processo.'
  param :nome, type: 'string', desc: 'Nome (parcial) do cliente', required: false
  param :cpf, type: 'string', desc: 'CPF do cliente, com ou sem pontuacao', required: false

  LIMITE = 10

  def perform(_tool_context, nome: nil, cpf: nil)
    filtros = montar_filtros(nome, cpf)
    return 'Informe o nome ou o CPF para buscar.' if filtros.empty?

    log_tool_usage('buscar_processo_advbox', { filtros: filtros.keys })
    processos = Ramon::AdvboxClient.lawsuits(filtros.merge(limit: LIMITE))
    return 'Nenhum processo encontrado no AdvBox.' if processos.blank?

    processos.to_json
  rescue Ramon::AdvboxClient::RequestError => e
    "O AdvBox recusou a consulta (HTTP #{e.code})."
  rescue Ramon::AdvboxClient::UnavailableError
    'O AdvBox nao respondeu agora. Tente de novo em instantes.'
  end

  private

  def montar_filtros(nome, cpf)
    filtros = {}
    filtros[:identification] = cpf.delete('^0-9') if cpf.present?
    filtros[:name] = nome if nome.present?
    filtros
  end
end
```

- [ ] **Step 4: Registrar no catálogo de tools**

Acrescentar ao final de `config/agents/tools.yml`:

```yaml
- id: buscar_processo_advbox
  title: 'Buscar processo no AdvBox'
  description: 'Busca processos no AdvBox por nome do cliente ou CPF'
  icon: 'search'
```

- [ ] **Step 5: Rodar o teste e confirmar verde**

Run: `bundle exec rspec spec/enterprise/lib/captain/tools/buscar_processo_advbox_tool_spec.rb`
Expected: PASS, 5 exemplos.

- [ ] **Step 6: Confirmar que o catálogo resolve a classe**

Run: `bundle exec rails runner "puts Captain::Assistant.built_in_tool_ids.inspect"`
Expected: a saída inclui `"buscar_processo_advbox"`.

Se **não** incluir, `load_agent_tools` não resolveu a classe — conferir o nome do arquivo contra a regra `classify` (Global Constraints) e procurar `Tool class not found for ID:` no log.

- [ ] **Step 7: Commit**

```bash
git add enterprise/lib/captain/tools/buscar_processo_advbox_tool.rb config/agents/tools.yml spec/enterprise/lib/captain/tools/buscar_processo_advbox_tool_spec.rb
git commit --no-verify -m "feat: tool buscar_processo_advbox para o agente"
```

---

### Task 4: Tool `consultar_dossie_advbox`

Segunda tool do encadeamento: recebe o `id` que a Task 3 devolveu e traz o dossiê completo numa chamada.

**Files:**
- Create: `enterprise/lib/captain/tools/consultar_dossie_advbox_tool.rb`
- Modify: `config/agents/tools.yml`
- Test: `spec/enterprise/lib/captain/tools/consultar_dossie_advbox_tool_spec.rb`

**Interfaces:**
- Consumes: `Ramon::AdvboxMcpService.dossie(processo_id)` → `Hash` com as chaves `:processo`, `:movimentacoes`, `:publicacoes`, `:tarefas`, `:historico_tarefas`. Mesmos erros da Task 3.
- Produces: `Captain::Tools::ConsultarDossieAdvboxTool#perform(tool_context, processo_id:)` → `String`. Constante pública `MAX_CHARS`. Id registrado: `consultar_dossie_advbox`.

- [ ] **Step 1: Escrever o teste que falha**

Criar `spec/enterprise/lib/captain/tools/consultar_dossie_advbox_tool_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe Captain::Tools::ConsultarDossieAdvboxTool, type: :model do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:tool) { described_class.new(assistant) }
  let(:tool_context) { Struct.new(:state).new({}) }
  let(:dossie) do
    { processo: { 'id' => 42, 'process_number' => '5001234-56.2026.4.04.7200' },
      movimentacoes: [{ 'date' => '2026-07-01' }],
      publicacoes: [], tarefas: [], historico_tarefas: [] }
  end

  describe '#perform' do
    it 'devolve o dossie do processo em json' do
      allow(Ramon::AdvboxMcpService).to receive(:dossie).with(42).and_return(dossie)

      result = tool.perform(tool_context, processo_id: 42)

      expect(JSON.parse(result).dig('processo', 'id')).to eq(42)
    end

    it 'aceita o id como string vinda do llm' do
      allow(Ramon::AdvboxMcpService).to receive(:dossie).with(42).and_return(dossie)

      expect(tool.perform(tool_context, processo_id: '42')).to include('5001234')
    end

    it 'recusa id invalido sem chamar o advbox' do
      expect(Ramon::AdvboxMcpService).not_to receive(:dossie)

      expect(tool.perform(tool_context, processo_id: 'abc')).to eq('Informe o id numerico do processo no AdvBox.')
    end

    it 'trunca dossie muito grande' do
      gigante = { processo: { 'nota' => 'x' * (described_class::MAX_CHARS + 100) } }
      allow(Ramon::AdvboxMcpService).to receive(:dossie).with(42).and_return(gigante)

      result = tool.perform(tool_context, processo_id: 42)

      expect(result.length).to be <= described_class::MAX_CHARS + 40
      expect(result).to end_with('[dossie truncado]')
    end

    it 'devolve mensagem quando o advbox recusa' do
      allow(Ramon::AdvboxMcpService).to receive(:dossie)
        .and_raise(Ramon::AdvboxClient::RequestError.new(404, 'nao encontrado'))

      expect(tool.perform(tool_context, processo_id: 42)).to eq('O AdvBox recusou a consulta (HTTP 404).')
    end

    it 'devolve mensagem quando o advbox esta fora do ar' do
      allow(Ramon::AdvboxMcpService).to receive(:dossie)
        .and_raise(Ramon::AdvboxClient::UnavailableError)

      expect(tool.perform(tool_context, processo_id: 42)).to eq('O AdvBox nao respondeu agora. Tente de novo em instantes.')
    end
  end
end
```

- [ ] **Step 2: Rodar e confirmar que falha**

Run: `bundle exec rspec spec/enterprise/lib/captain/tools/consultar_dossie_advbox_tool_spec.rb`
Expected: FAIL — `uninitialized constant Captain::Tools::ConsultarDossieAdvboxTool`.

- [ ] **Step 3: Implementar a tool**

Criar `enterprise/lib/captain/tools/consultar_dossie_advbox_tool.rb`:

```ruby
# Leitura pura no AdvBox: dossie completo do processo numa chamada so
# (processo + movimentacoes + publicacoes + tarefas + historico).
class Captain::Tools::ConsultarDossieAdvboxTool < Captain::Tools::BasePublicTool
  description 'Traz o dossie completo de um processo do AdvBox: dados do processo, ultimas movimentacoes, ' \
              'publicacoes, tarefas e historico. Use o id devolvido por buscar_processo_advbox.'
  param :processo_id, type: 'string', desc: 'Id do processo no AdvBox'

  # ponytail: teto burro de caracteres so para nao estourar o contexto num
  # processo com historico enorme. Se comecar a cortar dossie util, o upgrade
  # e limitar por secao (tarefas/historico) em vez do JSON inteiro.
  MAX_CHARS = 20_000

  def perform(_tool_context, processo_id:)
    id = Integer(processo_id.to_s, exception: false)
    return 'Informe o id numerico do processo no AdvBox.' if id.nil?

    log_tool_usage('consultar_dossie_advbox', { processo_id: id })
    truncar(Ramon::AdvboxMcpService.dossie(id).to_json)
  rescue Ramon::AdvboxClient::RequestError => e
    "O AdvBox recusou a consulta (HTTP #{e.code})."
  rescue Ramon::AdvboxClient::UnavailableError
    'O AdvBox nao respondeu agora. Tente de novo em instantes.'
  end

  private

  def truncar(json)
    return json if json.length <= MAX_CHARS

    "#{json[0, MAX_CHARS]} [dossie truncado]"
  end
end
```

- [ ] **Step 4: Registrar no catálogo de tools**

Acrescentar ao final de `config/agents/tools.yml`:

```yaml
- id: consultar_dossie_advbox
  title: 'Consultar dossie no AdvBox'
  description: 'Dossie completo de um processo do AdvBox numa chamada so'
  icon: 'document'
```

- [ ] **Step 5: Rodar o teste e confirmar verde**

Run: `bundle exec rspec spec/enterprise/lib/captain/tools/consultar_dossie_advbox_tool_spec.rb`
Expected: PASS, 6 exemplos.

- [ ] **Step 6: Confirmar que as duas tools estão no catálogo**

Run: `bundle exec rails runner "puts Captain::Assistant.built_in_tool_ids.inspect"`
Expected: a saída inclui `"buscar_processo_advbox"` **e** `"consultar_dossie_advbox"`.

- [ ] **Step 7: Rodar rubocop nos arquivos novos**

Run: `bundle exec rubocop enterprise/lib/captain/tools/buscar_processo_advbox_tool.rb enterprise/lib/captain/tools/consultar_dossie_advbox_tool.rb lib/llm/config.rb`
Expected: `no offenses detected`. Corrigir o que apontar antes de commitar — o CI roda rubocop.

- [ ] **Step 8: Commit**

```bash
git add enterprise/lib/captain/tools/consultar_dossie_advbox_tool.rb config/agents/tools.yml spec/enterprise/lib/captain/tools/consultar_dossie_advbox_tool_spec.rb
git commit --no-verify -m "feat: tool consultar_dossie_advbox para o agente"
```

---

### Task 5: Operação e teste real (VPS)

**Isto não é código.** É a parte do spike que só existe rodando contra o DeepSeek de verdade, e é o que decide se as Fatias 1–3 acontecem. Executar **depois** do merge e deploy das Tasks 1–4.

**Files:**
- Create: `comercial/docs/2026-07-25-roteiro-fatia-0-area-ia.md` (na sede, fora do repo do hub)

**Interfaces:**
- Consumes: as tools das Tasks 3 e 4 e a config da Task 2, já em produção.
- Produces: veredito escrito sobre o risco 2 da spec (encadeamento de tools).

- [ ] **Step 1: Confirmar o deploy**

Após o merge, esperar o workflow "Publica imagem do fork" e, na VPS:

```bash
ssh root@185.194.216.67
cd /opt/intranet-ramon
docker compose pull chatwoot-web chatwoot-worker && docker compose up -d
docker inspect --format='{{index .Config.Labels "org.opencontainers.image.revision"}}' chatwoot-web
```

Expected: o label bate com o SHA do merge. Havendo merges próximos, puxar `ghcr.io/doods-maker/ramon-hub:sha-<mergesha>` direto e retagear — a tag flutuante é last-writer-wins (lição registrada).

- [ ] **Step 2: Confirmar que a env do DeepSeek está no container**

```bash
docker compose exec chatwoot-web sh -c 'test -n "$DEEPSEEK_API_KEY" && echo "DEEPSEEK_API_KEY presente" || echo "AUSENTE"'
```

Expected: `DEEPSEEK_API_KEY presente`. **Nunca ecoar o valor.** Se vier AUSENTE, parar: a Task 2 depende dela.

- [ ] **Step 3: Ligar as features do Captain na conta**

```bash
docker compose exec chatwoot-web bundle exec rails runner \
  "a = Account.find(2); a.enable_features!('captain_integration', 'captain_integration_v2', 'custom_tools'); a.save!; puts a.enabled_features.keys.inspect"
```

Expected: a saída lista as três. A conta do escritório é a **2** (mesma dos seeds de teses).

- [ ] **Step 4: Gravar o modelo**

```bash
docker compose exec chatwoot-web bundle exec rails runner \
  "InstallationConfig.find_or_create_by(name: 'CAPTAIN_OPEN_AI_MODEL').update!(value: 'deepseek-v4-pro'); \
   puts InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_MODEL').value"
```

Expected: `deepseek-v4-pro`. Nada de endpoint ou chave — o registry resolve o provider e a Task 2 entrega a credencial.

- [ ] **Step 5: Provar que o modelo responde**

```bash
docker compose exec chatwoot-web bundle exec rails runner \
  "Llm::Config.initialize!; puts RubyLLM.chat(model: 'deepseek-v4-pro').ask('responda apenas: ok').content"
```

Expected: `ok`.

Falhando por credencial, revisar a Task 2. Falhando por modelo desconhecido, tentar `deepseek-v4-flash` e depois `deepseek-chat` — os três estão no registry.

- [ ] **Step 6: Criar o agente e a skill pela UI**

Na interface, em Captain:

1. **Agente** — nome "Consulta AdvBox (spike)", descrição "Agente de teste da Fatia 0".
2. **Skill (cenário)** — título "Situação do processo"; instrução:

> Quando pedirem a situação do processo de alguém, use [Buscar processo no AdvBox](tool://buscar_processo_advbox) com o nome ou o CPF informado. Pegue o `id` do processo certo no resultado e chame [Consultar dossie no AdvBox](tool://consultar_dossie_advbox) com esse id. Responda em português, resumindo a última movimentação e as tarefas em aberto. Se a busca devolver mais de um processo, pergunte qual antes de seguir.

Salvar. O `validate_instruction_tools` recusa se algum id estiver errado — se recusar, os ids não batem com o YAML.

- [ ] **Step 7: Provar o risco 2 — encadeamento no Playground**

No Playground do agente, perguntar pelo nome de um cliente real da banca que tenha processo no AdvBox.

Expected: o agente chama `buscar_processo_advbox`, extrai o id, chama `consultar_dossie_advbox` e responde em português com a última movimentação.

Registrar o veredito em um de três níveis:
- **Encadeou sozinho** → risco 2 morto, seguir para a Fatia 1.
- **Chamou a 1ª mas não a 2ª, ou inventou o id** → risco 2 parcial; apertar a instrução da skill e repetir (é dado, não código) antes de qualquer conclusão.
- **Não chamou tool nenhuma** → risco 2 confirmado. Sem fallback de provedor: a Fatia 1 muda de forma (skills de passo único, uma tool por skill). Levar ao Eduardo antes de codar.

- [ ] **Step 8: Conferir o log de execução**

```bash
docker compose logs --tail=200 chatwoot-web | grep -i "AdvboxTool"
```

Expected: as linhas de `log_tool_usage` das duas tools, na ordem. É o embrião da tela "Execuções" da Fatia 3.

- [ ] **Step 9: Escrever o roteiro de smoke do Eduardo**

Criar `comercial/docs/2026-07-25-roteiro-fatia-0-area-ia.md` contendo, nesta ordem:

1. Onde ele clica para chegar no Playground do agente "Consulta AdvBox (spike)".
2. A pergunta exata a digitar, com o nome de um cliente real da banca.
3. O que deve aparecer: duas chamadas de tool e um resumo em português com a última movimentação.
4. O que reportar por print se divergir: a resposta do agente e a aba de execução da tool.
5. O veredito do Step 7, escrito por quem executou.

---

## Definição de pronto

- Tasks 1–4 com specs verdes e rubocop limpo.
- CI verde no PR.
- Deploy conferido por label na VPS.
- Steps 5 e 7 da Task 5 executados, com veredito escrito sobre o risco 2.
- Roteiro de smoke entregue ao Eduardo.

## Fora do escopo desta fatia

Renomear a área · demais tools de leitura · qualquer tool de escrita · o agente de atendimento · as telas Execuções e Watchdog · qualquer `CustomTool` HTTP · qualquer fallback de provedor.
