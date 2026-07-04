# F2.1c — Kit do Closer nativo — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 2ª passada de IA sobre uma triagem concluída gera o "Kit do Closer" (JSON estruturado em `lead_triages.kit`), exibido no painel do lead em blocos que variam pela etapa do funil (sdr/closer/encerrado), com botão de copiar por bloco.

**Architecture:** Porta a lógica da intranet legada (`lib/kit-closer.ts` + `lib/painel-lead.ts`) para Rails/Vue nativos. Backend: `Leads::KitService` (prompt fixo + parse tolerante) chamado por `Leads::KitJob` (Sidekiq, fila low), disparado por `POST /leads/:lead_id/triages/:id/kit`. As colunas `kit` (jsonb) e `kit_status` (string) JÁ EXISTEM em `lead_triages` — **sem migração nesta fatia**. Resultado chega na UI pelo broadcast `lead.updated` já existente (via `LeadTriage#broadcast_lead`). Frontend: aba nova "Kit" no `LeadConversationPanel`, helper puro `kitBlocks.js` decide os blocos pela etapa.

**Tech Stack:** Rails 7 (fork Chatwoot 4.15.1), RubyLLM via `Ramon::LlmClient` (já existe), Vue 3 `<script setup>`, Tailwind, RSpec, Vitest.

## Global Constraints

- Fork-safe: código novo em namespaces próprios (`Leads::`, `dashboard/routes/dashboard/ramon/`); NUNCA tocar `enterprise/`.
- Evento custom Vue SEMPRE camelCase.
- Ruby: rubocop 150 chars, `ENV.fetch`, máx 7 expectations por exemplo RSpec.
- `Lead` tem `default_scope order(:lead_stage_id, :position, :id)` — `.last` NÃO é o mais recente.
- Action Vuex: nunca desestruturar `state` cru (no-shadow) — usar `state: moduleState` se precisar.
- i18n: sem string crua em template; chaves novas em `pt_BR/ramon.json` E `en/ramon.json`.
- Specs: `create(:account)` já seeda o funil padrão (Novo…Perdido) — nunca criar etapa com nome seedado.
- Sem teste Ruby local (sem Postgres): escrever specs e deixar o CI validar. Vitest TAMBÉM não roda local (sem pnpm) — mesma regra.
- Commits: Conventional Commits, sem referência a Claude.

## Referência portada (da intranet legada, para fidelidade do port)

System prompt do kit (usar VERBATIM, constante `SYSTEM_PROMPT` do service):

```text
Você transforma uma análise jurídica de viabilidade em um "Kit do Closer": material em linguagem simples para um vendedor SEM formação jurídica usar numa conversa de WhatsApp com o cliente.

Responda APENAS com um objeto JSON válido (sem texto fora do JSON, sem cercas de código), nesta forma exata:
{
  "resumo_leigo": "3-4 linhas, sem juridiquês, do que se trata e por que vale a pena",
  "roteiro_perguntas": ["pergunta 1 exata pro WhatsApp", "pergunta 2"],
  "documentos": [{"documento": "nome", "porque": "motivo curto"}],
  "venda_objecoes": {"pitch": "como explicar a viabilidade em linguagem de venda", "objecoes": [{"objecao": "...", "resposta": "..."}]},
  "proximo_passo": "frase curta de fechamento: assinar contrato e agendar reunião com o jurídico"
}
Não invente fatos fora da análise. Português do Brasil.
```

Modos por etapa (nomes do seed `Leads::SeedDefaultConfigService::STAGES`):
- `encerrado`: lead com `won_at` OU `lost_at` preenchido → nenhum bloco.
- `closer`: etapas 'Reunião agendada', 'Reunião realizada', 'Negociação', 'Última chance' → blocos `['resumo', 'venda_objecoes', 'documentos', 'proximo_passo']`.
- `sdr` (default, inclui 'Novo'/'Qualificação'/etapa desconhecida) → blocos `['roteiro', 'proximo_passo']`.

---

### Task 1: Backend — `Leads::KitService` (prompt, chamada, parse tolerante) + `Leads::KitJob` + status `running`

**Files:**
- Create: `app/services/leads/kit_service.rb`
- Create: `app/jobs/leads/kit_job.rb`
- Modify: `app/models/lead_triage.rb` (linha `KIT_STATUSES`)
- Test: `spec/services/leads/kit_service_spec.rb`

**Interfaces:**
- Consumes: `Ramon::LlmClient.complete(provider:, model:, system:, user:, sensitive:)` → String (já existe); `LeadTriage` (campos `result`, `viability`, `kit`, `kit_status`, `error_message`, assoc `lead`, `triage_agent`).
- Produces: `Leads::KitService.new(triage).perform` — gera e grava `kit` (Hash com chaves string `resumo_leigo`, `roteiro_perguntas`, `documentos`, `venda_objecoes`, `proximo_passo`) e `kit_status: 'ready'`; em falha grava `kit_status: 'error'` e `kit: { 'error' => <msg> }`. `Leads::KitJob.perform_later(triage_id)`.

- [ ] **Step 1: Adicionar `running` aos KIT_STATUSES do model**

Em `app/models/lead_triage.rb`, trocar:

```ruby
  KIT_STATUSES = %w[pending ready error].freeze
```

por:

```ruby
  KIT_STATUSES = %w[pending running ready error].freeze
```

- [ ] **Step 2: Escrever specs do service (falham — arquivo não existe)**

Criar `spec/services/leads/kit_service_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe Leads::KitService do
  let(:account) { create(:account) }
  let(:agent) do
    create(:triage_agent, account: account, provider: 'deepseek', model: 'deepseek-chat', area: 'previdenciario')
  end
  let(:lead) { create(:lead, account: account, name: 'João') }
  let(:triage) do
    create(:lead_triage, account: account, lead: lead, triage_agent: agent,
                         status: 'done', viability: 'alta', result: 'Análise: caso viável pela Súmula 47.')
  end

  def kit_json
    {
      resumo_leigo: 'Caso bom.',
      roteiro_perguntas: ['Você se machucou no trabalho?'],
      documentos: [{ documento: 'CAT', porque: 'prova o acidente' }],
      venda_objecoes: { pitch: 'Vale a pena.', objecoes: [{ objecao: 'É caro?', resposta: 'Só paga no fim.' }] },
      proximo_passo: 'Assinar contrato.'
    }.to_json
  end

  it 'gera o kit e grava ready' do
    allow(Ramon::LlmClient).to receive(:complete).and_return(kit_json)
    described_class.new(triage).perform
    triage.reload
    expect(triage.kit_status).to eq('ready')
    expect(triage.kit['resumo_leigo']).to eq('Caso bom.')
    expect(triage.kit['roteiro_perguntas']).to eq(['Você se machucou no trabalho?'])
    expect(triage.kit['documentos'].first['documento']).to eq('CAT')
    expect(triage.kit['venda_objecoes']['pitch']).to eq('Vale a pena.')
    expect(triage.kit['proximo_passo']).to eq('Assinar contrato.')
  end

  it 'monta o prompt do usuário com viabilidade e análise e repassa a trava LGPD' do
    expect(Ramon::LlmClient).to receive(:complete) do |provider:, model:, system:, user:, sensitive:|
      expect(provider).to eq('deepseek')
      expect(model).to eq('deepseek-chat')
      expect(system).to include('Kit do Closer')
      expect(user).to include('Viabilidade apurada: alta')
      expect(user).to include('Súmula 47')
      expect(sensitive).to be(false)
      kit_json
    end
    described_class.new(triage).perform
  end

  it 'tolera cercas ```json e texto em volta' do
    allow(Ramon::LlmClient).to receive(:complete)
      .and_return("Claro! Aqui está:\n```json\n#{kit_json}\n```\nEspero ter ajudado.")
    described_class.new(triage).perform
    expect(triage.reload.kit_status).to eq('ready')
  end

  it 'marca error quando a resposta não tem JSON utilizável' do
    allow(Ramon::LlmClient).to receive(:complete).and_return('não consigo')
    described_class.new(triage).perform
    triage.reload
    expect(triage.kit_status).to eq('error')
    expect(triage.kit['error']).to be_present
  end

  it 'marca error quando o JSON vem sem resumo_leigo' do
    allow(Ramon::LlmClient).to receive(:complete).and_return('{"roteiro_perguntas": []}')
    described_class.new(triage).perform
    expect(triage.reload.kit_status).to eq('error')
  end

  it 'marca error quando o LlmClient levanta exceção' do
    allow(Ramon::LlmClient).to receive(:complete)
      .and_raise(Ramon::LlmClient::MissingApiKeyError, 'ENV DEEPSEEK_API_KEY ausente')
    described_class.new(triage).perform
    triage.reload
    expect(triage.kit_status).to eq('error')
    expect(triage.kit['error']).to include('DEEPSEEK_API_KEY')
  end

  it 'não sobrescreve status nem result da triagem' do
    allow(Ramon::LlmClient).to receive(:complete).and_return(kit_json)
    described_class.new(triage).perform
    triage.reload
    expect(triage.status).to eq('done')
    expect(triage.result).to include('Súmula 47')
  end
end
```

Nota: conferir em `spec/factories` se a factory `:lead_triage` existe (a F2.1b criou specs de triagem — reusar o padrão de lá; se a factory não existir, criar `spec/factories/lead_triages.rb` com `factory :lead_triage do account; lead; status { 'pending' }; kit_status { 'pending' } end`).

- [ ] **Step 3: Implementar o service**

Criar `app/services/leads/kit_service.rb`:

```ruby
class Leads::KitService
  SYSTEM_PROMPT = <<~PROMPT.freeze
    Você transforma uma análise jurídica de viabilidade em um "Kit do Closer": material em linguagem simples para um vendedor SEM formação jurídica usar numa conversa de WhatsApp com o cliente.

    Responda APENAS com um objeto JSON válido (sem texto fora do JSON, sem cercas de código), nesta forma exata:
    {
      "resumo_leigo": "3-4 linhas, sem juridiquês, do que se trata e por que vale a pena",
      "roteiro_perguntas": ["pergunta 1 exata pro WhatsApp", "pergunta 2"],
      "documentos": [{"documento": "nome", "porque": "motivo curto"}],
      "venda_objecoes": {"pitch": "como explicar a viabilidade em linguagem de venda", "objecoes": [{"objecao": "...", "resposta": "..."}]},
      "proximo_passo": "frase curta de fechamento: assinar contrato e agendar reunião com o jurídico"
    }
    Não invente fatos fora da análise. Português do Brasil.
  PROMPT

  def initialize(triage)
    @triage = triage
    @lead = triage.lead
    @agent = triage.triage_agent
  end

  def perform
    @triage.update!(kit_status: 'running')
    raw = call_llm
    @triage.update!(kit: parse_kit(raw), kit_status: 'ready')
  rescue StandardError => e
    mark_error(e)
  end

  private

  def mark_error(error)
    @triage.update!(kit_status: 'error', kit: { 'error' => error.message.truncate(500) })
  rescue StandardError => e
    Rails.logger.error("KitService: falha ao gravar erro do kit da triage #{@triage.id}: #{e.message}")
  end

  def call_llm
    Ramon::LlmClient.complete(provider: @agent.provider, model: @agent.model,
                              system: SYSTEM_PROMPT, user: user_prompt,
                              sensitive: @agent.sensitive)
  end

  def user_prompt
    [
      "Cliente: #{@lead.name}",
      @agent.area.present? ? "Área: #{@agent.area}" : nil,
      "Viabilidade apurada: #{@triage.viability.presence || 'não informada'}",
      '',
      'Análise jurídica da triagem:',
      @triage.result
    ].compact.join("\n")
  end

  # Porta o parse tolerante de lib/kit-closer.ts: aceita cercas ```json e
  # texto em volta; valida resumo_leigo; coage arrays/strings item a item.
  def parse_kit(raw)
    body = raw.to_s.gsub(/```json/i, '').gsub('```', '')
    ini = body.index('{')
    fim = body.rindex('}')
    raise ArgumentError, 'Resposta da IA não contém JSON do kit.' if ini.nil? || fim.nil? || fim <= ini

    obj = JSON.parse(body[ini..fim])
    raise ArgumentError, 'Kit sem resumo_leigo.' if obj['resumo_leigo'].to_s.strip.empty?

    normalize(obj)
  rescue JSON::ParserError
    raise ArgumentError, 'JSON do kit inválido.'
  end

  def normalize(obj)
    venda = obj['venda_objecoes'].is_a?(Hash) ? obj['venda_objecoes'] : {}
    {
      'resumo_leigo' => obj['resumo_leigo'].to_s.strip,
      'roteiro_perguntas' => string_list(obj['roteiro_perguntas']),
      'documentos' => pair_list(obj['documentos'], 'documento', 'porque'),
      'venda_objecoes' => {
        'pitch' => venda['pitch'].to_s,
        'objecoes' => pair_list(venda['objecoes'], 'objecao', 'resposta')
      },
      'proximo_passo' => obj['proximo_passo'].to_s.strip
    }
  end

  def string_list(value)
    Array(value).map(&:to_s).reject(&:empty?)
  end

  def pair_list(value, key_field, value_field)
    Array(value).filter_map do |item|
      next unless item.is_a?(Hash)

      pair = { key_field => item[key_field].to_s, value_field => item[value_field].to_s }
      pair[key_field].empty? ? nil : pair
    end
  end
end
```

- [ ] **Step 4: Implementar o job**

Criar `app/jobs/leads/kit_job.rb`:

```ruby
class Leads::KitJob < ApplicationJob
  queue_as :low

  def perform(triage_id)
    triage = LeadTriage.find_by(id: triage_id)
    return if triage.blank?

    Leads::KitService.new(triage).perform
  end
end
```

- [ ] **Step 5: Rubocop no que foi tocado**

Run: `bundle exec rubocop -a app/services/leads/kit_service.rb app/jobs/leads/kit_job.rb app/models/lead_triage.rb spec/services/leads/kit_service_spec.rb` — se não houver bundle local, apenas revisar manualmente contra as regras (150 chars, frozen constants). CI valida.

- [ ] **Step 6: Commit**

```bash
git add app/services/leads/kit_service.rb app/jobs/leads/kit_job.rb app/models/lead_triage.rb spec/services/leads/kit_service_spec.rb spec/factories
git commit -m "feat(ramon): kit closer service and job (2nd LLM pass over triage)"
```

---

### Task 2: API — rota `POST /triages/:id/kit`, controller, jbuilder com kit, broadcast com kit_status

**Files:**
- Modify: `config/routes.rb` (linha ~296, resources :triages)
- Modify: `app/controllers/api/v1/accounts/lead_triages_controller.rb`
- Modify: `app/views/api/v1/accounts/lead_triages/_lead_triage.json.jbuilder`
- Modify: `app/models/lead.rb` (linha do `latest_triage:` no `push_event_data`)
- Test: `spec/controllers/api/v1/accounts/lead_triages_controller_spec.rb` (ou o request spec equivalente que a F2.1b criou — seguir o padrão existente; procurar com `grep -rl "triages" spec/`)
- Test: `spec/models/lead_spec.rb` (ajustar/estender o exemplo do push_event_data se ele citar latest_triage)

**Interfaces:**
- Consumes: `Leads::KitJob.perform_later(id)` (Task 1); `LeadTriage` com `kit`, `kit_status`.
- Produces: `POST /api/v1/accounts/:account_id/leads/:lead_id/triages/:id/kit` → 200 com o jbuilder `show` da triagem (agora incluindo `kit` e `kit_status`); `push_event_data[:latest_triage]` passa a incluir `:kit_status`.

- [ ] **Step 1: Spec do endpoint (falha)**

No spec de triagens existente (achar com `grep -rl "lead_triages\|triages" spec/requests spec/controllers`), adicionar contexto:

```ruby
  describe 'POST /api/v1/accounts/{account.id}/leads/{lead.id}/triages/{triage.id}/kit' do
    let(:triage) do
      create(:lead_triage, account: account, lead: lead, triage_agent: agent, status: 'done', result: 'ok')
    end

    it 'enfileira o KitJob, marca running e devolve a triagem' do
      expect do
        post "/api/v1/accounts/#{account.id}/leads/#{lead.id}/triages/#{triage.id}/kit",
             headers: admin.create_new_auth_token, as: :json
      end.to have_enqueued_job(Leads::KitJob).with(triage.id)
      expect(response).to have_http_status(:success)
      expect(triage.reload.kit_status).to eq('running')
      expect(response.parsed_body['kit_status']).to eq('running')
    end

    it 'recusa quando a triagem não está done' do
      pending_triage = create(:lead_triage, account: account, lead: lead, status: 'running')
      post "/api/v1/accounts/#{account.id}/leads/#{lead.id}/triages/#{pending_triage.id}/kit",
           headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
```

(Adaptar `admin`/`agent`/`lead` aos lets do arquivo existente; se o spec existente for de controller e não request, seguir o estilo do arquivo.)

- [ ] **Step 2: Rota**

Em `config/routes.rb`, trocar:

```ruby
            resources :triages, only: [:index, :create], controller: 'lead_triages'
```

por:

```ruby
            resources :triages, only: [:index, :create], controller: 'lead_triages' do
              member do
                post :kit
              end
            end
```

- [ ] **Step 3: Action no controller**

Em `app/controllers/api/v1/accounts/lead_triages_controller.rb`, adicionar após `create`:

```ruby
  def kit
    @lead_triage = @lead.lead_triages.find(params[:id])
    return render_could_not_create_error('Triagem ainda não concluída') unless @lead_triage.status == 'done'

    @lead_triage.update!(kit_status: 'running')
    Leads::KitJob.perform_later(@lead_triage.id)
    render :show
  end
```

(`render_could_not_create_error` é helper do BaseController do Chatwoot e devolve 422; confirmar o nome com `grep -rn "render_could_not_create_error" app/controllers/api/v1/accounts | head -2` — se o fork usar outro helper, seguir o padrão local.)

- [ ] **Step 4: jbuilder com kit**

Em `_lead_triage.json.jbuilder`, adicionar após `json.viability`:

```ruby
json.kit lead_triage.kit
json.kit_status lead_triage.kit_status
```

- [ ] **Step 5: kit_status no broadcast**

Em `app/models/lead.rb`, trocar:

```ruby
      latest_triage: latest_triage&.slice(:id, :status, :viability)
```

por:

```ruby
      latest_triage: latest_triage&.slice(:id, :status, :viability, :kit_status)
```

Se `spec/models/lead_spec.rb` tiver exemplo cobrindo latest_triage, estender a expectativa com `kit_status`; senão, adicionar:

```ruby
  it 'push_event_data expõe kit_status na latest_triage' do
    lead = create(:lead, account: account)
    create(:lead_triage, account: account, lead: lead, status: 'done', kit_status: 'ready')
    expect(lead.push_event_data[:latest_triage][:kit_status]).to eq('ready')
  end
```

- [ ] **Step 6: Commit**

```bash
git add config/routes.rb app/controllers/api/v1/accounts/lead_triages_controller.rb app/views/api/v1/accounts/lead_triages/_lead_triage.json.jbuilder app/models/lead.rb spec/
git commit -m "feat(ramon): kit generation endpoint and kit_status in lead broadcast"
```

---

### Task 3: Frontend base — API JS + helper puro de blocos por etapa

**Files:**
- Modify: `app/javascript/dashboard/api/leads.js`
- Create: `app/javascript/dashboard/routes/dashboard/ramon/helpers/kitBlocks.js`
- Test: `app/javascript/dashboard/routes/dashboard/ramon/helpers/specs/kitBlocks.spec.js`

**Interfaces:**
- Produces: `LeadsAPI.createKit(leadId, triageId)` → POST `/leads/:leadId/triages/:triageId/kit`; `stageMode(lead)` → `'sdr' | 'closer' | 'encerrado'`; `kitBlocks(mode)` → array ordenado de `'resumo' | 'roteiro' | 'documentos' | 'venda_objecoes' | 'proximo_passo'`.

- [ ] **Step 1: Spec do helper (falha)**

Criar `app/javascript/dashboard/routes/dashboard/ramon/helpers/specs/kitBlocks.spec.js`:

```js
import { stageMode, kitBlocks } from '../kitBlocks';

describe('stageMode', () => {
  it('é encerrado quando o lead tem won_at ou lost_at', () => {
    expect(stageMode({ won_at: '2026-07-04', stage_name: 'Fechado' })).toBe('encerrado');
    expect(stageMode({ lost_at: '2026-07-04', stage_name: 'Perdido' })).toBe('encerrado');
  });

  it('é closer da reunião agendada até a última chance', () => {
    ['Reunião agendada', 'Reunião realizada', 'Negociação', 'Última chance'].forEach(stage => {
      expect(stageMode({ stage_name: stage })).toBe('closer');
    });
  });

  it('é sdr por padrão (Novo, Qualificação, etapa desconhecida, sem etapa)', () => {
    expect(stageMode({ stage_name: 'Novo' })).toBe('sdr');
    expect(stageMode({ stage_name: 'Qualificação' })).toBe('sdr');
    expect(stageMode({ stage_name: 'Etapa custom' })).toBe('sdr');
    expect(stageMode({})).toBe('sdr');
  });
});

describe('kitBlocks', () => {
  it('sdr vê roteiro e próximo passo', () => {
    expect(kitBlocks('sdr')).toEqual(['roteiro', 'proximo_passo']);
  });

  it('closer vê resumo, venda/objeções, documentos e próximo passo', () => {
    expect(kitBlocks('closer')).toEqual(['resumo', 'venda_objecoes', 'documentos', 'proximo_passo']);
  });

  it('encerrado não vê nada', () => {
    expect(kitBlocks('encerrado')).toEqual([]);
  });
});
```

- [ ] **Step 2: Implementar o helper**

Criar `app/javascript/dashboard/routes/dashboard/ramon/helpers/kitBlocks.js`:

```js
// Porta lib/painel-lead.ts da intranet legada: o que o Kit do Closer mostra
// depende do momento da venda. SDR (qualificando) ≠ Closer (fechando).
const CLOSER_STAGES = [
  'Reunião agendada',
  'Reunião realizada',
  'Negociação',
  'Última chance',
];

export function stageMode(lead) {
  if (lead?.won_at || lead?.lost_at) return 'encerrado';
  if (CLOSER_STAGES.includes(lead?.stage_name)) return 'closer';
  return 'sdr';
}

export function kitBlocks(mode) {
  switch (mode) {
    case 'closer':
      return ['resumo', 'venda_objecoes', 'documentos', 'proximo_passo'];
    case 'encerrado':
      return [];
    default:
      return ['roteiro', 'proximo_passo'];
  }
}
```

- [ ] **Step 3: API JS**

Em `app/javascript/dashboard/api/leads.js`, adicionar após `createTriage`:

```js
  createKit(leadId, triageId) {
    return axios.post(`${this.url}/${leadId}/triages/${triageId}/kit`);
  }
```

- [ ] **Step 4: Commit**

```bash
git add app/javascript/dashboard/api/leads.js app/javascript/dashboard/routes/dashboard/ramon/helpers/
git commit -m "feat(ramon): kit closer API client and stage-mode helper"
```

---

### Task 4: Frontend UI — componente `LeadKit.vue` + aba "Kit" no painel + i18n

**Files:**
- Create: `app/javascript/dashboard/routes/dashboard/ramon/components/conversation/LeadKit.vue`
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/components/conversation/LeadConversationPanel.vue`
- Modify: `app/javascript/dashboard/i18n/locale/pt_BR/ramon.json`
- Modify: `app/javascript/dashboard/i18n/locale/en/ramon.json`
- Test: `app/javascript/dashboard/routes/dashboard/ramon/components/conversation/specs/LeadKit.spec.js`
- Test: `app/javascript/dashboard/routes/dashboard/ramon/components/conversation/specs/LeadConversationPanel.spec.js` (aba nova)

**Interfaces:**
- Consumes: `LeadsAPI.getTriages(leadId)` (existente — a triagem mais recente vem primeiro e agora carrega `kit`/`kit_status`), `LeadsAPI.createKit(leadId, triageId)` (Task 3), `stageMode`/`kitBlocks` (Task 3), `copyTextToClipboard` de `shared/helpers/clipboard`, `useAlert` de `dashboard/composables`.
- Produces: componente `LeadKit` (prop `lead` obrigatória) e aba "Kit" no painel.

- [ ] **Step 1: i18n**

Em `pt_BR/ramon.json`, adicionar bloco irmão de `TRIAGE` (dentro de `RAMON`):

```json
    "KIT": {
      "TAB": "Kit",
      "GENERATE": "Gerar Kit do Closer",
      "REGENERATE": "Gerar novamente",
      "GENERATING": "Gerando kit…",
      "STARTED": "Geração do kit iniciada",
      "ERROR": "Falha ao gerar o kit",
      "EMPTY": "Rode uma triagem primeiro — o kit nasce da análise dela.",
      "NEED_DONE": "A triagem precisa terminar antes de gerar o kit.",
      "CLOSED": "Lead encerrado — sem kit para esta etapa.",
      "COPY_BLOCK": "Copiar",
      "MODE_LABEL": "Modo",
      "MODE": { "SDR": "Qualificação (SDR)", "CLOSER": "Fechamento (Closer)" },
      "BLOCKS": {
        "RESUMO": "Resumo em linguagem simples",
        "ROTEIRO": "Roteiro de perguntas",
        "DOCUMENTOS": "Documentos a pedir",
        "VENDA_OBJECOES": "Venda e objeções",
        "PROXIMO_PASSO": "Próximo passo"
      }
    },
```

Em `en/ramon.json`, o equivalente:

```json
    "KIT": {
      "TAB": "Kit",
      "GENERATE": "Generate Closer Kit",
      "REGENERATE": "Regenerate",
      "GENERATING": "Generating kit…",
      "STARTED": "Kit generation started",
      "ERROR": "Kit generation failed",
      "EMPTY": "Run a triage first — the kit is built from its analysis.",
      "NEED_DONE": "The triage must finish before generating the kit.",
      "CLOSED": "Lead closed — no kit for this stage.",
      "COPY_BLOCK": "Copy",
      "MODE_LABEL": "Mode",
      "MODE": { "SDR": "Qualifying (SDR)", "CLOSER": "Closing (Closer)" },
      "BLOCKS": {
        "RESUMO": "Plain-language summary",
        "ROTEIRO": "Question script",
        "DOCUMENTOS": "Documents to request",
        "VENDA_OBJECOES": "Pitch and objections",
        "PROXIMO_PASSO": "Next step"
      }
    },
```

- [ ] **Step 2: Specs do componente (falham)**

Criar `specs/LeadKit.spec.js` seguindo o padrão de `specs/LeadTriage.spec.js` (mesmos mocks de `LeadsAPI`, `useAlert`, i18n com `$t` retornando a chave). Casos:

```js
// mounts com lead { id: 3, stage_name: 'Qualificação', latest_triage: {...} }
it('mostra o vazio quando não há triagem done', ...);          // getTriages → [] → texto RAMON.KIT.EMPTY
it('gera o kit da triagem mais recente done', ...);            // clica [data-testid="kit-generate"] → createKit(3, triageId) + alert STARTED
it('renderiza só os blocos do modo sdr', ...);                 // triagem com kit ready + stage Qualificação → data-testid kit-block-roteiro e kit-block-proximo_passo presentes; kit-block-resumo ausente
it('renderiza os blocos do modo closer', ...);                 // stage_name 'Negociação' → resumo, venda_objecoes, documentos, proximo_passo
it('não mostra nada além do aviso quando encerrado', ...);     // lead won_at → texto RAMON.KIT.CLOSED, sem botão gerar
it('copia o texto do bloco', ...);                             // clica [data-testid="kit-copy-roteiro"] → clipboard chamado com as perguntas
it('recarrega quando latest_triage.kit_status muda', ...);     // setProps lead com kit_status ready → getTriages chamado de novo
```

Escrever os 7 casos completos no arquivo (usar os mocks exatamente como em LeadTriage.spec.js; para clipboard, `vi.mock('shared/helpers/clipboard', () => ({ copyTextToClipboard: vi.fn() }))`).

- [ ] **Step 3: Implementar `LeadKit.vue`**

```vue
<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import LeadsAPI from 'dashboard/api/leads';
import {
  stageMode,
  kitBlocks,
} from 'dashboard/routes/dashboard/ramon/helpers/kitBlocks';

const props = defineProps({
  lead: { type: Object, required: true },
});
defineOptions({ name: 'LeadKit' });

const { t } = useI18n();
const triages = ref([]);
const isLoading = ref(false);
const isStarting = ref(false);

const loadTriages = async () => {
  isLoading.value = true;
  try {
    const { data } = await LeadsAPI.getTriages(props.lead.id);
    triages.value = data;
  } finally {
    isLoading.value = false;
  }
};

onMounted(() => {
  if (props.lead?.id) loadTriages();
});

watch(
  () => [props.lead?.id, props.lead?.latest_triage],
  ([leadId, next], [prevLeadId, prev] = []) => {
    if (leadId !== prevLeadId) {
      triages.value = [];
      if (leadId) loadTriages();
      return;
    }
    if (!next) return;
    if (next.id !== prev?.id || next.kit_status !== prev?.kit_status) {
      loadTriages();
    }
  }
);

const doneTriage = computed(
  () => triages.value.find(triage => triage.status === 'done') || null
);
const kit = computed(() =>
  doneTriage.value?.kit_status === 'ready' ? doneTriage.value.kit : null
);
const kitError = computed(() =>
  doneTriage.value?.kit_status === 'error'
    ? doneTriage.value.kit?.error
    : null
);
const isGenerating = computed(
  () => doneTriage.value?.kit_status === 'running'
);

const mode = computed(() => stageMode(props.lead));
const blocks = computed(() =>
  kit.value ? kitBlocks(mode.value).filter(hasContent) : []
);

function hasContent(block) {
  const value = kit.value?.[blockKey(block)];
  if (block === 'venda_objecoes') {
    return Boolean(value?.pitch || value?.objecoes?.length);
  }
  return Array.isArray(value) ? value.length > 0 : Boolean(value);
}

function blockKey(block) {
  return block === 'roteiro' ? 'roteiro_perguntas' : blockField(block);
}
function blockField(block) {
  return block === 'resumo' ? 'resumo_leigo' : block;
}

const blockText = block => {
  const value = kit.value?.[blockKey(block)];
  if (block === 'roteiro') return (value || []).join('\n');
  if (block === 'documentos') {
    return (value || [])
      .map(doc => `${doc.documento} — ${doc.porque}`)
      .join('\n');
  }
  if (block === 'venda_objecoes') {
    const objecoes = (value?.objecoes || [])
      .map(item => `${item.objecao} → ${item.resposta}`)
      .join('\n');
    return [value?.pitch, objecoes].filter(Boolean).join('\n\n');
  }
  return value || '';
};

const generateKit = async () => {
  if (!doneTriage.value) return;
  isStarting.value = true;
  try {
    await LeadsAPI.createKit(props.lead.id, doneTriage.value.id);
    useAlert(t('RAMON.KIT.STARTED'));
    await loadTriages();
  } catch (error) {
    useAlert(t('RAMON.KIT.ERROR'));
  } finally {
    isStarting.value = false;
  }
};

const copyBlock = async block => {
  try {
    await copyTextToClipboard(blockText(block));
  } catch (error) {
    useAlert(t('RAMON.DOCS.COPY_FAILED'));
    return;
  }
  useAlert(t('RAMON.PLAYBOOK.COPIED'));
};

const blockLabelKey = block => `RAMON.KIT.BLOCKS.${block.toUpperCase()}`;
</script>

<template>
  <div class="flex flex-col gap-4 p-1" data-testid="lead-kit">
    <p
      v-if="mode === 'encerrado'"
      class="text-sm text-n-slate-10"
      data-testid="kit-closed"
    >
      {{ $t('RAMON.KIT.CLOSED') }}
    </p>

    <template v-else>
      <p
        v-if="!isLoading && !doneTriage"
        class="text-sm text-n-slate-10"
        data-testid="kit-empty"
      >
        {{ $t('RAMON.KIT.EMPTY') }}
      </p>

      <template v-else-if="doneTriage">
        <div class="flex items-center justify-between gap-2">
          <button
            type="button"
            data-testid="kit-generate"
            class="px-3 py-1.5 text-xs rounded-lg bg-n-alpha-1 text-n-slate-12 border border-n-weak disabled:opacity-40 disabled:cursor-not-allowed"
            :disabled="isGenerating || isStarting"
            @click="generateKit"
          >
            {{
              isGenerating
                ? $t('RAMON.KIT.GENERATING')
                : $t(kit ? 'RAMON.KIT.REGENERATE' : 'RAMON.KIT.GENERATE')
            }}
          </button>
          <span class="text-xs text-n-slate-10">
            {{ $t('RAMON.KIT.MODE_LABEL') }}:
            {{ $t(`RAMON.KIT.MODE.${mode.toUpperCase()}`) }}
          </span>
        </div>

        <p
          v-if="kitError"
          class="text-sm text-n-ruby-11"
          data-testid="kit-error"
        >
          {{ $t('RAMON.KIT.ERROR') }}: {{ kitError }}
        </p>

        <div
          v-for="block in blocks"
          :key="block"
          :data-testid="`kit-block-${block}`"
          class="flex flex-col gap-2 p-3 rounded-lg bg-n-alpha-1 border border-n-weak"
        >
          <div class="flex items-center justify-between gap-2">
            <h4 class="text-xs uppercase tracking-widest text-n-slate-9">
              {{ $t(blockLabelKey(block)) }}
            </h4>
            <button
              type="button"
              :data-testid="`kit-copy-${block}`"
              class="px-2 py-0.5 text-xs rounded-lg bg-n-alpha-1 text-n-slate-12 border border-n-weak"
              @click="copyBlock(block)"
            >
              {{ $t('RAMON.KIT.COPY_BLOCK') }}
            </button>
          </div>

          <p
            v-if="block === 'resumo' || block === 'proximo_passo'"
            class="text-sm whitespace-pre-wrap text-n-slate-12"
          >
            {{ blockText(block) }}
          </p>

          <ul
            v-else-if="block === 'roteiro'"
            class="flex flex-col gap-1 text-sm text-n-slate-12 list-disc ps-4"
          >
            <li v-for="(pergunta, i) in kit.roteiro_perguntas" :key="i">
              {{ pergunta }}
            </li>
          </ul>

          <ul
            v-else-if="block === 'documentos'"
            class="flex flex-col gap-1 text-sm text-n-slate-12"
          >
            <li v-for="doc in kit.documentos" :key="doc.documento">
              <span class="font-medium">{{ doc.documento }}</span>
              <span class="text-n-slate-10"> — {{ doc.porque }}</span>
            </li>
          </ul>

          <div
            v-else-if="block === 'venda_objecoes'"
            class="flex flex-col gap-2 text-sm text-n-slate-12"
          >
            <p v-if="kit.venda_objecoes.pitch" class="whitespace-pre-wrap">
              {{ kit.venda_objecoes.pitch }}
            </p>
            <div
              v-for="objecao in kit.venda_objecoes.objecoes"
              :key="objecao.objecao"
              class="p-2 rounded-lg bg-n-alpha-2"
            >
              <p class="font-medium">{{ objecao.objecao }}</p>
              <p class="text-n-slate-11">{{ objecao.resposta }}</p>
            </div>
          </div>
        </div>

        <p
          v-if="!kit && !kitError && !isGenerating"
          class="text-xs text-n-slate-10"
        >
          {{ $t('RAMON.KIT.NEED_DONE') }}
        </p>
      </template>
    </template>
  </div>
</template>
```

Atenção eslint do fork: sem CSS custom, só Tailwind; eventos camelCase (não há emits aqui); `useAlert`/`t` como nos vizinhos.

- [ ] **Step 4: Aba no painel**

Em `LeadConversationPanel.vue`:

Import (junto dos outros):

```js
import LeadKit from 'dashboard/routes/dashboard/ramon/components/conversation/LeadKit.vue';
```

Botão de aba (após o botão da triagem, antes do botão de fechar):

```html
      <button
        :class="{ 'font-semibold': activeTab === 'kit' }"
        data-testid="tab-kit"
        @click="activeTab = 'kit'"
      >
        {{ $t('RAMON.KIT.TAB') }}
      </button>
```

Conteúdo (após a linha do LeadTriage):

```html
      <LeadKit v-else-if="activeTab === 'kit'" :lead="lead" />
```

Na spec do painel (`specs/LeadConversationPanel.spec.js`), adicionar:

```js
  it('switches to the Kit tab and renders LeadKit', async () => {
    const wrapper = mountPanel();
    await flushPromises();
    await wrapper.find('[data-testid="tab-kit"]').trigger('click');
    expect(wrapper.findComponent({ name: 'LeadKit' }).exists()).toBe(true);
  });
```

(Conferir se o mount da spec faz stub dos filhos; seguir o que ela já faz com LeadTriage/LeadPlaybook.)

- [ ] **Step 5: Commit**

```bash
git add app/javascript/dashboard/routes/dashboard/ramon/components/conversation/ app/javascript/dashboard/i18n/locale/
git commit -m "feat(ramon): closer kit tab with stage-aware blocks and copy"
```

---

### Task 5: Registro do fork + push + PR

**Files:**
- Modify: `docs/FORK-PONTOS-DE-REGISTRO.md` (adicionar a fatia F2.1c na seção correspondente à F2.1b, mesmo formato das entradas vizinhas)

**Interfaces:** —

- [ ] **Step 1: Registrar pontos de fork**

Adicionar em `docs/FORK-PONTOS-DE-REGISTRO.md`, seguindo o formato existente, os pontos tocados de core: `config/routes.rb` (member :kit), `app/models/lead.rb` (kit_status no latest_triage), `app/controllers/api/v1/accounts/lead_triages_controller.rb` (action kit), jbuilder. Arquivos novos em namespace próprio não precisam de entrada detalhada (citar em bloco).

- [ ] **Step 2: Conferir diff completo e commitar**

```bash
git add docs/FORK-PONTOS-DE-REGISTRO.md
git commit -m "docs(ramon): register F2.1c fork touchpoints"
git push -u origin feat/ramon-kit-closer
```

- [ ] **Step 3: Abrir PR**

```bash
gh pr create --repo doods-maker/ramon-hub --base ramon --title "feat(ramon): F2.1c — Kit do Closer nativo" --body "..."
```

Corpo do PR: parágrafo de produto (kit em linguagem leiga gerado da triagem, blocos por etapa sdr/closer, copiar por bloco), How to test (rodar triagem → aba Kit → gerar → blocos conforme etapa do lead), What changed (service+job+endpoint+aba, sem migração).

---

## Self-Review (feito na escrita)

1. **Spec coverage:** 2ª passada (Task 1) ✓ · endpoint+broadcast (Task 2) ✓ · blocos por etapa + copiar (Tasks 3–4) ✓ · sem migração (colunas já existem) ✓ · LGPD herdada via `sensitive` do agente (Task 1, spec dedicada) ✓ · registro do fork (Task 5) ✓.
2. **Placeholders:** nenhum "TBD"; specs completas nos Tasks 1–3; Task 4 Step 2 lista os 7 casos com instrução de escrevê-los completos no padrão do arquivo vizinho (o implementador tem o LeadTriage.spec.js como referência concreta).
3. **Type consistency:** `createKit(leadId, triageId)` igual nos Tasks 2/3/4; `kit_status` valores `pending|running|ready|error` iguais nos Tasks 1/2/4; blocos `resumo|roteiro|documentos|venda_objecoes|proximo_passo` iguais nos Tasks 3/4.
