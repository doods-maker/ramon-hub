# Área "Reuniões" — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tela no hub pra gravar reunião presencial pelo navegador, transcrever no faster-whisper da VPS e gerar ata (resumo + decisões + pendências) via DeepSeek.

**Architecture:** Tabela `ramon_reunioes` (modelo `Reuniao`, áudio em ActiveStorage/R2) + job que encadeia whisper → LLM + controller REST + página Vue na Intranet com MediaRecorder. Spec: `docs/superpowers/specs/2026-07-28-reunioes-gravacao-design.md`.

**Tech Stack:** Rails 7.1 (fork Chatwoot v4.15.1), ruby-openai (já no Gemfile), `Ramon::LlmClient` (RubyLLM/DeepSeek), Vue 3 `<script setup>` + Tailwind, vitest.

## Global Constraints

- **Trabalhar em worktree** (`ramon-hub-wt-reunioes`, branch `feat/ramon-reunioes` a partir de `ramon`); push com `--no-verify` (husky ausente no worktree).
- **Sem ambiente Ruby local**: specs RSpec são escritas mas validadas pelo CI no PR. O que roda local: `npx vitest run app/javascript/dashboard/routes/dashboard/ramon`, `pnpm eslint`, `npx prettier --write` nos arquivos tocados.
- **schema.rb editado à mão** (não há Postgres local) — bloco exato no Task 1.
- Vue: Composition API `<script setup>`, Tailwind only, eventos camelCase, **zero string solta em template** (`vue/no-bare-strings-in-template`) — todo texto via i18n.
- i18n do fork: `app/javascript/dashboard/i18n/locale/pt_BR/ramon.json` **e** `en/ramon.json` (os dois, sempre juntos).
- Rubocop: linha máx 150; `RSpec/ContextWording` exige contexto em inglês (`when/with/without`); specs novas aumentam o footprint do knapsack — se um shard core sem relação falhar, reduzir specs (lição 20/07).
- Commits Conventional Commits, sem mencionar Claude.
- DeepSeek: **nunca** `response_format`/json_schema (recusa — lição PR #110).
- Limite de áudio: `25_000_000` bytes decimal (mesmo teto do `Messages::AudioTranscriptionService`).

---

### Task 1: Migração, modelo `Reuniao`, associação e factory

**Files:**
- Create: `db/migrate/20260728000001_create_ramon_reunioes.rb`
- Create: `app/models/reuniao.rb`
- Modify: `db/schema.rb` (bloco novo + version)
- Modify: `app/models/account.rb:87` (perto de `has_many :calculos`)
- Create: `spec/factories/reunioes.rb`
- Test: `spec/models/reuniao_spec.rb`

**Interfaces:**
- Produces: modelo `Reuniao` (tabela `ramon_reunioes`): `account_id`, `user_id`, `titulo:string`, `duracao_segundos:integer`, `status:string` (`transcrevendo|pronta|erro`, default `transcrevendo`), `erro:string`, `transcricao:text`, `ata:text`, `has_one_attached :audio`, scope `recentes`, método `titulo_exibicao`. `Current.account.reunioes` disponível.

- [ ] **Step 1: Migração**

```ruby
class CreateRamonReunioes < ActiveRecord::Migration[7.1]
  def change
    create_table :ramon_reunioes do |t|
      t.references :account, null: false, foreign_key: true
      t.references :user, foreign_key: true
      t.string :titulo
      t.integer :duracao_segundos
      t.string :status, null: false, default: 'transcrevendo'
      t.string :erro
      t.text :transcricao
      t.text :ata
      t.timestamps
    end
    add_index :ramon_reunioes, [:account_id, :created_at]
  end
end
```

- [ ] **Step 2: Editar `db/schema.rb` à mão** — trocar a version do topo por `2026_07_28_000001` e inserir (ordem alfabética das tabelas, logo após `ramon_` anteriores ou onde couber alfabeticamente):

```ruby
  create_table "ramon_reunioes", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "user_id"
    t.string "titulo"
    t.integer "duracao_segundos"
    t.string "status", default: "transcrevendo", null: false
    t.string "erro"
    t.text "transcricao"
    t.text "ata"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "created_at"], name: "index_ramon_reunioes_on_account_id_and_created_at"
    t.index ["account_id"], name: "index_ramon_reunioes_on_account_id"
    t.index ["user_id"], name: "index_ramon_reunioes_on_user_id"
  end
```

E no bloco de foreign keys no fim: `add_foreign_key "ramon_reunioes", "accounts"` e `add_foreign_key "ramon_reunioes", "users"` (ordem alfabética).

- [ ] **Step 3: Modelo**

```ruby
# Reunião presencial gravada na área "Reuniões" da Intranet: áudio no
# ActiveStorage (R2), transcrição do faster-whisper local e ata gerada por LLM.
class Reuniao < ApplicationRecord
  self.table_name = 'ramon_reunioes'

  STATUSES = %w[transcrevendo pronta erro].freeze

  belongs_to :account
  belongs_to :user, optional: true
  has_one_attached :audio

  validates :status, inclusion: { in: STATUSES }

  scope :recentes, -> { order(created_at: :desc) }

  def titulo_exibicao
    titulo.presence || "Reunião de #{created_at.strftime('%d/%m %H:%M')}"
  end
end
```

- [ ] **Step 4: Associação no Account** — em `app/models/account.rb`, junto de `has_many :calculos`:

```ruby
  has_many :reunioes, class_name: 'Reuniao', dependent: :destroy_async
```

(class_name explícito de propósito: o inflector não pluraliza "reuniao" → "reunioes".)

- [ ] **Step 5: Factory**

```ruby
FactoryBot.define do
  factory :reuniao do
    account
    status { 'transcrevendo' }
  end
end
```

- [ ] **Step 6: Model spec**

```ruby
require 'rails_helper'

RSpec.describe Reuniao do
  it { is_expected.to belong_to(:account) }
  it { is_expected.to validate_inclusion_of(:status).in_array(described_class::STATUSES) }

  describe '#titulo_exibicao' do
    it 'uses titulo when present' do
      reuniao = build(:reuniao, titulo: 'Alinhamento')
      expect(reuniao.titulo_exibicao).to eq('Alinhamento')
    end

    it 'falls back to timestamp when blank' do
      reuniao = create(:reuniao, titulo: nil)
      expect(reuniao.titulo_exibicao).to include(reuniao.created_at.strftime('%d/%m'))
    end
  end
end
```

- [ ] **Step 7: Commit**

```bash
git add db/migrate/20260728000001_create_ramon_reunioes.rb db/schema.rb app/models/reuniao.rb app/models/account.rb spec/factories/reunioes.rb spec/models/reuniao_spec.rb
git commit --no-verify -m "feat(reunioes): modelo Reuniao com audio anexado"
```

---

### Task 2: `Ramon::ReuniaoAtaService` (whisper → DeepSeek)

**Files:**
- Create: `app/services/ramon/reuniao_ata_service.rb`
- Test: `spec/services/ramon/reuniao_ata_service_spec.rb`

**Interfaces:**
- Consumes: `Reuniao` (Task 1), `Ramon::LlmClient.complete(provider:, model:, system:, user:, sensitive:)` → `Result#content` (existente).
- Produces: `Ramon::ReuniaoAtaService.new(reuniao).perform` — transcreve (pulando se `transcricao` já existe), gera ata, grava `status: 'pronta'`. Levanta exceções do LlmClient/rede pra quem chamar tratar.

- [ ] **Step 1: Service**

```ruby
# Transcreve o áudio da reunião no faster-whisper local e gera a ata via LLM.
# Transcrição já feita é reaproveitada (Reprocessar após falha do LLM não paga
# o whisper de novo). Erros sobem pro job marcar status=erro.
class Ramon::ReuniaoAtaService
  # Mesmo destino do Messages::AudioTranscriptionService (PR #106). O whisper
  # local ignora o access_token — nenhuma credencial de chat entra aqui.
  WHISPER_ENDPOINT = 'http://whisper:8000/'.freeze
  WHISPER_MODEL = 'Systran/faster-whisper-medium'.freeze

  SYSTEM_PROMPT = <<~PROMPT.freeze
    Você é o secretário de um escritório de advocacia previdenciária.
    Recebe a transcrição bruta de uma reunião presencial e redige a ATA em
    português do Brasil, em markdown, EXATAMENTE nesta estrutura:

    ## Resumo
    (um parágrafo com o essencial da reunião)

    ## Decisões
    - (uma decisão por linha; se nenhuma, escreva "Nenhuma decisão registrada.")

    ## Pendências
    - (uma por linha, "Ação — responsável — prazo"; responsável e prazo só
      quando citados; se nenhuma, escreva "Nenhuma pendência.")

    Não invente nada que não esteja na transcrição. Não use JSON nem cerca de
    código — só o markdown acima.
  PROMPT

  def initialize(reuniao)
    @reuniao = reuniao
  end

  def perform
    transcricao = @reuniao.transcricao.presence || transcrever
    @reuniao.update!(transcricao: transcricao)
    ata = gerar_ata(transcricao)
    @reuniao.update!(ata: ata, status: 'pronta', erro: nil)
  end

  private

  def transcrever
    @reuniao.audio.blob.open do |file|
      # temperature 0.0 evita alucinação em silêncio (mesma calibração do
      # serviço de mensagens).
      response = client.audio.transcribe(
        parameters: { model: whisper_model, file: file, temperature: 0.0 }
      )
      response['text'].to_s
    end
  end

  def client
    OpenAI::Client.new(access_token: 'local-whisper', uri_base: whisper_endpoint, log_errors: false)
  end

  def whisper_endpoint
    ENV.fetch('RAMON_WHISPER_ENDPOINT', nil).presence || WHISPER_ENDPOINT
  end

  def whisper_model
    ENV.fetch('RAMON_WHISPER_MODEL', nil).presence || WHISPER_MODEL
  end

  # Conteúdo de reunião é sensível por definição; o deepseek está autorizado
  # na VPS via RAMON_LLM_SENSITIVE_OK_PROVIDERS (decisão do Eduardo 20/07).
  def gerar_ata(transcricao)
    Ramon::LlmClient.complete(
      provider: ENV.fetch('RAMON_REUNIAO_PROVIDER', 'deepseek'),
      model: ENV.fetch('RAMON_REUNIAO_MODEL', 'deepseek-chat'),
      system: SYSTEM_PROMPT, user: transcricao, sensitive: true
    ).content
  end
end
```

- [ ] **Step 2: Spec** (WebMock pro whisper; `Ramon::LlmClient` mockado — a lista sensível default não inclui deepseek, então mock evita depender de env)

```ruby
require 'rails_helper'

RSpec.describe Ramon::ReuniaoAtaService do
  let(:account) { create(:account) }
  let(:reuniao) { create(:reuniao, account: account) }
  let(:llm_result) { Ramon::LlmClient::Result.new(content: '## Resumo', input_tokens: 1, output_tokens: 1) }

  before do
    reuniao.audio.attach(io: StringIO.new('fake-audio'), filename: 'reuniao.webm', content_type: 'audio/webm')
    stub_request(:post, 'http://whisper:8000/v1/audio/transcriptions')
      .to_return(status: 200, body: { text: 'fala transcrita' }.to_json,
                 headers: { 'Content-Type' => 'application/json' })
    allow(Ramon::LlmClient).to receive(:complete).and_return(llm_result)
  end

  it 'transcreve, gera a ata e marca pronta' do
    described_class.new(reuniao).perform
    expect(reuniao.reload).to have_attributes(transcricao: 'fala transcrita', ata: '## Resumo', status: 'pronta')
    expect(Ramon::LlmClient).to have_received(:complete)
      .with(hash_including(user: 'fala transcrita', sensitive: true))
  end

  context 'when transcricao already exists' do
    it 'skips whisper and reuses it' do
      reuniao.update!(transcricao: 'ja transcrito')
      described_class.new(reuniao).perform
      expect(WebMock).not_to have_requested(:post, 'http://whisper:8000/v1/audio/transcriptions')
      expect(reuniao.reload.ata).to eq('## Resumo')
    end
  end
end
```

- [ ] **Step 3: Commit**

```bash
git add app/services/ramon/reuniao_ata_service.rb spec/services/ramon/reuniao_ata_service_spec.rb
git commit --no-verify -m "feat(reunioes): servico whisper + ata via LLM"
```

---

### Task 3: `Ramon::ReuniaoAtaJob`

**Files:**
- Create: `app/jobs/ramon/reuniao_ata_job.rb`
- Test: `spec/jobs/ramon/reuniao_ata_job_spec.rb`

**Interfaces:**
- Consumes: `Ramon::ReuniaoAtaService.new(reuniao).perform` (Task 2).
- Produces: `Ramon::ReuniaoAtaJob.perform_later(reuniao_id)` — qualquer falha termina em `status: 'erro'` + motivo em `erro` (transitória do LLM tenta 3x antes).

- [ ] **Step 1: Job**

```ruby
class Ramon::ReuniaoAtaJob < ApplicationJob
  queue_as :low
  retry_on Ramon::LlmClient::TransientError, wait: :polynomially_longer, attempts: 3 do |job, error|
    job.marcar_erro(error)
  end

  def perform(reuniao_id)
    @reuniao = Reuniao.find_by(id: reuniao_id)
    return if @reuniao.blank?

    Ramon::ReuniaoAtaService.new(@reuniao).perform
  rescue Ramon::LlmClient::TransientError
    raise
  rescue StandardError => e
    marcar_erro(e)
  end

  def marcar_erro(error)
    @reuniao&.update(status: 'erro', erro: error.message.to_s.first(255))
  end
end
```

- [ ] **Step 2: Spec**

```ruby
require 'rails_helper'

RSpec.describe Ramon::ReuniaoAtaJob do
  let(:reuniao) { create(:reuniao) }

  it 'runs the service' do
    service = instance_double(Ramon::ReuniaoAtaService, perform: true)
    allow(Ramon::ReuniaoAtaService).to receive(:new).with(reuniao).and_return(service)
    described_class.perform_now(reuniao.id)
    expect(service).to have_received(:perform)
  end

  it 'marks erro on permanent failure' do
    allow(Ramon::ReuniaoAtaService).to receive(:new).and_raise(StandardError, 'boom')
    described_class.perform_now(reuniao.id)
    expect(reuniao.reload).to have_attributes(status: 'erro', erro: 'boom')
  end

  it 'is a no-op when reuniao is gone' do
    expect { described_class.perform_now(0) }.not_to raise_error
  end
end
```

- [ ] **Step 3: Commit**

```bash
git add app/jobs/ramon/reuniao_ata_job.rb spec/jobs/ramon/reuniao_ata_job_spec.rb
git commit --no-verify -m "feat(reunioes): job de transcricao e ata"
```

---

### Task 4: Controller, policy e rotas

**Files:**
- Create: `app/controllers/api/v1/accounts/ramon_reunioes_controller.rb`
- Create: `app/policies/reuniao_policy.rb`
- Modify: `config/routes.rb:298` (logo após o bloco `resource :ramon_calculos`)
- Test: `spec/requests/api/v1/accounts/ramon_reunioes_spec.rb`

**Interfaces:**
- Consumes: `Reuniao` (Task 1), `Ramon::ReuniaoAtaJob` (Task 3).
- Produces (contrato pro front, Tasks 5–7):
  - `GET    /api/v1/accounts/:account_id/ramon_reunioes` → `{ payload: [linha] }`
  - `GET    /api/v1/accounts/:account_id/ramon_reunioes/:id` → detalhe
  - `POST   /api/v1/accounts/:account_id/ramon_reunioes` (multipart `audio`, `titulo`, `duracao_segundos`) → detalhe
  - `POST   /api/v1/accounts/:account_id/ramon_reunioes/:id/reprocessar` → detalhe
  - `DELETE /api/v1/accounts/:account_id/ramon_reunioes/:id` → 204
  - linha = `{ id, titulo, status, duracao_segundos, created_at, user_name }`; detalhe = linha + `{ transcricao, ata, erro, audio_url }`.

- [ ] **Step 1: Rotas** — em `config/routes.rb`, após o bloco `resource :ramon_calculos ... end` (linha ~298):

```ruby
          resources :ramon_reunioes, only: [:index, :show, :create, :destroy], controller: 'ramon_reunioes' do
            member { post :reprocessar }
          end
```

- [ ] **Step 2: Policy**

```ruby
class ReuniaoPolicy < ApplicationPolicy
  def index?
    @account_user.administrator? || @account_user.agent?
  end

  def show?
    index?
  end

  def create?
    index?
  end

  def destroy?
    index?
  end

  def reprocessar?
    index?
  end
end
```

- [ ] **Step 3: Controller**

```ruby
# Área "Reuniões": gravações presenciais com transcrição (whisper local) e ata (LLM).
class Api::V1::Accounts::RamonReunioesController < Api::V1::Accounts::BaseController
  # Teto decimal do endpoint de transcrição (igual ao Messages::AudioTranscriptionService).
  AUDIO_BYTE_LIMIT = 25_000_000
  LIMIT = 100

  before_action :current_account
  before_action :fetch_reuniao, only: [:show, :destroy, :reprocessar]
  before_action :check_authorization

  def index
    reunioes = Current.account.reunioes.recentes.limit(LIMIT)
    render json: { payload: reunioes.map { |reuniao| linha(reuniao) } }
  end

  def show
    render json: detalhe(@reuniao)
  end

  def create
    audio = params[:audio]
    return render_error('Áudio ausente') if audio.blank?
    return render_error('Áudio acima do limite de 25 MB') if audio.size > AUDIO_BYTE_LIMIT

    reuniao = Current.account.reunioes.create!(
      user: Current.user,
      titulo: params[:titulo].presence,
      duracao_segundos: params[:duracao_segundos].to_i
    )
    reuniao.audio.attach(audio)
    Ramon::ReuniaoAtaJob.perform_later(reuniao.id)
    render json: detalhe(reuniao)
  end

  def destroy
    @reuniao.destroy!
    head :no_content
  end

  def reprocessar
    return render_error('Reunião não está com erro') unless @reuniao.status == 'erro'

    @reuniao.update!(status: 'transcrevendo', erro: nil)
    Ramon::ReuniaoAtaJob.perform_later(@reuniao.id)
    render json: detalhe(@reuniao)
  end

  private

  def fetch_reuniao
    @reuniao = Current.account.reunioes.find(params[:id])
  end

  def check_authorization
    authorize(:reuniao, :"#{action_name}?")
  end

  def render_error(mensagem)
    render json: { error: mensagem }, status: :unprocessable_entity
  end

  def linha(reuniao)
    {
      id: reuniao.id,
      titulo: reuniao.titulo_exibicao,
      status: reuniao.status,
      duracao_segundos: reuniao.duracao_segundos,
      created_at: reuniao.created_at.iso8601,
      user_name: reuniao.user&.name
    }
  end

  def detalhe(reuniao)
    linha(reuniao).merge(
      transcricao: reuniao.transcricao,
      ata: reuniao.ata,
      erro: reuniao.erro,
      audio_url: reuniao.audio.attached? ? url_for(reuniao.audio) : nil
    )
  end
end
```

- [ ] **Step 4: Request spec**

```ruby
require 'rails_helper'

RSpec.describe 'Ramon Reunioes API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:audio) { Rack::Test::UploadedFile.new(StringIO.new('fake-audio'), 'audio/webm', original_filename: 'reuniao.webm') }

  describe 'POST /api/v1/accounts/:id/ramon_reunioes' do
    context 'when unauthenticated' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/ramon_reunioes"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated as agent' do
      it 'creates the reuniao and enqueues the job' do
        expect do
          post "/api/v1/accounts/#{account.id}/ramon_reunioes",
               params: { audio: audio, titulo: 'Alinhamento', duracao_segundos: 90 },
               headers: agent.create_new_auth_token
        end.to have_enqueued_job(Ramon::ReuniaoAtaJob)
        expect(response).to have_http_status(:success)
        body = response.parsed_body
        expect(body['status']).to eq('transcrevendo')
        expect(body['titulo']).to eq('Alinhamento')
        expect(Reuniao.last.audio).to be_attached
      end

      it 'rejects audio above the byte limit' do
        allow_any_instance_of(Rack::Test::UploadedFile).to receive(:size).and_return(26_000_000)
        post "/api/v1/accounts/#{account.id}/ramon_reunioes",
             params: { audio: audio }, headers: agent.create_new_auth_token
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'rejects missing audio' do
        post "/api/v1/accounts/#{account.id}/ramon_reunioes",
             params: {}, headers: agent.create_new_auth_token
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'GET /api/v1/accounts/:id/ramon_reunioes' do
    it 'lists reunioes' do
      create(:reuniao, account: account, titulo: 'Semanal')
      get "/api/v1/accounts/#{account.id}/ramon_reunioes", headers: agent.create_new_auth_token
      expect(response).to have_http_status(:success)
      expect(response.parsed_body['payload'].pluck('titulo')).to include('Semanal')
    end
  end

  describe 'POST /api/v1/accounts/:id/ramon_reunioes/:id/reprocessar' do
    it 'requeues when status is erro' do
      reuniao = create(:reuniao, account: account, status: 'erro', erro: 'boom')
      expect do
        post "/api/v1/accounts/#{account.id}/ramon_reunioes/#{reuniao.id}/reprocessar",
             headers: agent.create_new_auth_token
      end.to have_enqueued_job(Ramon::ReuniaoAtaJob).with(reuniao.id)
      expect(reuniao.reload).to have_attributes(status: 'transcrevendo', erro: nil)
    end

    it 'refuses when status is not erro' do
      reuniao = create(:reuniao, account: account, status: 'pronta')
      post "/api/v1/accounts/#{account.id}/ramon_reunioes/#{reuniao.id}/reprocessar",
           headers: agent.create_new_auth_token
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'DELETE /api/v1/accounts/:id/ramon_reunioes/:id' do
    it 'destroys the reuniao' do
      reuniao = create(:reuniao, account: account)
      delete "/api/v1/accounts/#{account.id}/ramon_reunioes/#{reuniao.id}",
             headers: agent.create_new_auth_token
      expect(response).to have_http_status(:no_content)
      expect(Reuniao.exists?(reuniao.id)).to be(false)
    end
  end
end
```

(Se o rubocop reclamar de `allow_any_instance_of`, trocar por construir um `UploadedFile` real de 26 MB é pior — usar `# rubocop:disable RSpec/AnyInstance` cirúrgico.)

- [ ] **Step 5: Commit**

```bash
git add app/controllers/api/v1/accounts/ramon_reunioes_controller.rb app/policies/reuniao_policy.rb config/routes.rb spec/requests/api/v1/accounts/ramon_reunioes_spec.rb
git commit --no-verify -m "feat(reunioes): API REST da area Reunioes"
```

---

### Task 5: Front — API client, rotas, sidebar e i18n

**Files:**
- Create: `app/javascript/dashboard/api/reunioes.js`
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/ramon.routes.js` (fim do array)
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/components/IntranetSidebar.vue:70` (após o item `calculos`)
- Modify: `app/javascript/dashboard/i18n/locale/pt_BR/ramon.json` e `.../en/ramon.json`

**Interfaces:**
- Consumes: endpoints do Task 4.
- Produces: `ReunioesAPI` com `get()` (index, herdado), `show(id)` (herdado), `criar(formData, onUploadProgress)`, `reprocessar(id)`, `delete(id)` (herdado); rotas `ramon_reunioes` (lista) e `ramon_reuniao` (`:reuniaoId`); chaves i18n `RAMON.NAV.REUNIOES` e `RAMON.REUNIOES.*` usadas nas Tasks 6–7.

- [ ] **Step 1: API client**

```js
/* global axios */
import ApiClient from './ApiClient';

class ReunioesAPI extends ApiClient {
  constructor() {
    super('ramon_reunioes', { accountScoped: true });
  }

  criar(formData, onUploadProgress) {
    return axios.post(this.url, formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
      onUploadProgress,
    });
  }

  reprocessar(id) {
    return axios.post(`${this.url}/${id}/reprocessar`);
  }
}

export default new ReunioesAPI();
```

- [ ] **Step 2: Rotas** — acrescentar ao array de `ramon.routes.js`:

```js
  {
    path: frontendURL('accounts/:accountId/ramon/reunioes'),
    name: 'ramon_reunioes',
    component: () => import('./pages/Reunioes.vue'),
    meta: { permissions: ['administrator', 'agent'], world: 'intranet' },
  },
  {
    path: frontendURL('accounts/:accountId/ramon/reunioes/:reuniaoId'),
    name: 'ramon_reuniao',
    component: () => import('./pages/Reunioes.vue'),
    meta: { permissions: ['administrator', 'agent'], world: 'intranet' },
  },
```

- [ ] **Step 3: Sidebar** — em `IntranetSidebar.vue`, logo após o item `calculos`:

```js
        {
          key: 'reunioes',
          label: t('RAMON.NAV.REUNIOES'),
          icon: 'i-lucide-mic',
          to: accountScopedRoute('ramon_reunioes'),
          names: ['ramon_reunioes', 'ramon_reuniao'],
        },
```

- [ ] **Step 4: i18n** — em `pt_BR/ramon.json`: adicionar `"REUNIOES": "Reuniões"` dentro de `RAMON.NAV`, e o bloco novo `RAMON.REUNIOES` (ordem alfabética das seções, arquivo é UTF-8):

```json
    "REUNIOES": {
      "TITLE": "Reuniões",
      "NEW": "Nova reunião",
      "EMPTY": "Nenhuma reunião gravada ainda.",
      "LOAD_ERROR": "Não foi possível carregar as reuniões",
      "TITLE_PLACEHOLDER": "Título (opcional)",
      "RECORD": "Gravar",
      "PAUSE": "Pausar",
      "RESUME": "Continuar",
      "STOP": "Encerrar e enviar",
      "CANCEL": "Descartar",
      "MIC_ERROR": "Não foi possível acessar o microfone — verifique a permissão do navegador",
      "UPLOADING": "Enviando áudio… {progress}%",
      "UPLOAD_ERROR": "Falha ao enviar o áudio — tente de novo",
      "LEAVE_WARNING": "Gravação em andamento",
      "STATUS_TRANSCREVENDO": "Transcrevendo…",
      "STATUS_PRONTA": "Ata pronta",
      "STATUS_ERRO": "Erro",
      "PROCESSING_HINT": "A transcrição e a ata chegam aqui em alguns minutos.",
      "ATA_TITLE": "Ata",
      "TRANSCRICAO_TITLE": "Transcrição bruta",
      "AUDIO_TITLE": "Áudio",
      "REPROCESS": "Reprocessar",
      "DELETE": "Apagar",
      "DELETE_CONFIRM": "Apagar esta reunião e o áudio? Não dá pra desfazer.",
      "RECORDED_BY": "Gravada por {name}",
      "BACK": "Voltar"
    }
```

Em `en/ramon.json`, o mesmo bloco em inglês (`"REUNIOES": "Meetings"` no NAV; traduções diretas — ex.: `"TITLE": "Meetings"`, `"NEW": "New meeting"`, `"STOP": "Stop & upload"`, `"STATUS_TRANSCREVENDO": "Transcribing…"`, `"STATUS_PRONTA": "Minutes ready"`, `"STATUS_ERRO": "Error"`, `"ATA_TITLE": "Minutes"`, `"TRANSCRICAO_TITLE": "Raw transcript"`, e assim por diante pra cada chave).

- [ ] **Step 5: Lint e commit**

```bash
pnpm eslint app/javascript/dashboard/api/reunioes.js app/javascript/dashboard/routes/dashboard/ramon/ramon.routes.js app/javascript/dashboard/routes/dashboard/ramon/components/IntranetSidebar.vue --fix
git add app/javascript/dashboard/api/reunioes.js app/javascript/dashboard/routes/dashboard/ramon/ramon.routes.js app/javascript/dashboard/routes/dashboard/ramon/components/IntranetSidebar.vue app/javascript/dashboard/i18n/locale/pt_BR/ramon.json app/javascript/dashboard/i18n/locale/en/ramon.json
git commit --no-verify -m "feat(reunioes): rotas, menu e i18n da area Reunioes"
```

---

### Task 6: Front — gravador (`ReuniaoRecorder.vue`) + página lista (`Reunioes.vue`)

**Files:**
- Create: `app/javascript/dashboard/routes/dashboard/ramon/components/reunioes/ReuniaoRecorder.vue`
- Create: `app/javascript/dashboard/routes/dashboard/ramon/pages/Reunioes.vue`
- Test: `app/javascript/dashboard/routes/dashboard/ramon/pages/specs/ReuniaoRecorder.spec.js`

**Interfaces:**
- Consumes: `ReunioesAPI` (Task 5), i18n `RAMON.REUNIOES.*` (Task 5), `RamonPageHeader` (componente existente em `../components/RamonPageHeader.vue` — conferir import nos pages vizinhos, ex. `Calculos.vue`).
- Produces: `ReuniaoRecorder` emite `created` com o payload detalhe da reunião criada. `Reunioes.vue` decide pelo `route.params.reuniaoId`: sem id = lista + gravador; com id = renderiza `ReuniaoDetalhe` (Task 7 — nesta task, deixar o bloco de detalhe com um placeholder `<div v-if="reuniaoId" />` que a Task 7 substitui).

- [ ] **Step 1: `ReuniaoRecorder.vue`**

```vue
<script setup>
import { onBeforeUnmount, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import ReunioesAPI from 'dashboard/api/reunioes';
import { useAlert } from 'dashboard/composables';

defineOptions({ name: 'ReuniaoRecorder' });
const emit = defineEmits(['created']);

const { t } = useI18n();
const estado = ref('parado'); // parado | gravando | pausado | enviando
const segundos = ref(0);
const titulo = ref('');
const progresso = ref(0);

let recorder = null;
let stream = null;
let chunks = [];
let timer = null;

// ponytail: 32 kbps opus = voz nítida e 1h ≈ 15 MB (teto do whisper é 25 MB).
const OPCOES = { audioBitsPerSecond: 32000 };
const mimeType = ['audio/webm;codecs=opus', 'audio/mp4'].find(tipo =>
  window.MediaRecorder?.isTypeSupported(tipo)
);

const formatoTempo = total => {
  const min = String(Math.floor(total / 60)).padStart(2, '0');
  const seg = String(total % 60).padStart(2, '0');
  return `${min}:${seg}`;
};

const avisoSaida = event => {
  event.preventDefault();
  // eslint-disable-next-line no-param-reassign
  event.returnValue = t('RAMON.REUNIOES.LEAVE_WARNING');
};

const limpar = () => {
  clearInterval(timer);
  window.removeEventListener('beforeunload', avisoSaida);
  stream?.getTracks().forEach(track => track.stop());
  recorder = null;
  stream = null;
  chunks = [];
  segundos.value = 0;
  progresso.value = 0;
  estado.value = 'parado';
};

const gravar = async () => {
  try {
    stream = await navigator.mediaDevices.getUserMedia({ audio: true });
  } catch {
    useAlert(t('RAMON.REUNIOES.MIC_ERROR'));
    return;
  }
  chunks = [];
  recorder = new MediaRecorder(stream, { ...OPCOES, mimeType });
  recorder.ondataavailable = event => {
    if (event.data.size) chunks.push(event.data);
  };
  recorder.start(1000);
  segundos.value = 0;
  timer = setInterval(() => {
    if (estado.value === 'gravando') segundos.value += 1;
  }, 1000);
  window.addEventListener('beforeunload', avisoSaida);
  estado.value = 'gravando';
};

const pausar = () => {
  recorder.pause();
  estado.value = 'pausado';
};

const continuar = () => {
  recorder.resume();
  estado.value = 'gravando';
};

const enviar = async () => {
  estado.value = 'enviando';
  const extensao = mimeType?.startsWith('audio/mp4') ? 'mp4' : 'webm';
  const blob = new Blob(chunks, { type: mimeType });
  const dados = new FormData();
  dados.append('audio', blob, `reuniao.${extensao}`);
  if (titulo.value.trim()) dados.append('titulo', titulo.value.trim());
  dados.append('duracao_segundos', segundos.value);
  try {
    const { data } = await ReunioesAPI.criar(dados, event => {
      progresso.value = Math.round((event.loaded / (event.total || 1)) * 100);
    });
    emit('created', data);
    titulo.value = '';
    limpar();
  } catch {
    useAlert(t('RAMON.REUNIOES.UPLOAD_ERROR'));
    estado.value = 'pausado';
  }
};

const encerrar = () => {
  if (!recorder) return;
  recorder.onstop = enviar;
  recorder.stop();
};

const descartar = () => limpar();

onBeforeUnmount(limpar);
</script>

<template>
  <div class="flex flex-col gap-3 rounded-lg border border-n-weak bg-n-solid-2 p-4">
    <input
      v-model="titulo"
      type="text"
      class="reset-base h-10 rounded-lg border border-n-weak bg-n-alpha-black2 px-3 text-sm text-n-slate-12"
      :placeholder="t('RAMON.REUNIOES.TITLE_PLACEHOLDER')"
      :disabled="estado === 'enviando'"
    />
    <div class="flex items-center gap-3">
      <span
        v-if="estado !== 'parado'"
        class="font-mono text-lg text-n-slate-12"
        data-testid="recorder-timer"
        >{{ formatoTempo(segundos) }}</span
      >
      <span
        v-if="estado === 'gravando'"
        class="size-2 animate-pulse rounded-full bg-n-ruby-9"
      />
      <button
        v-if="estado === 'parado'"
        type="button"
        class="rounded-lg bg-n-brand px-4 py-2 text-sm font-medium text-white"
        data-testid="recorder-start"
        @click="gravar"
      >
        {{ t('RAMON.REUNIOES.RECORD') }}
      </button>
      <template v-else-if="estado !== 'enviando'">
        <button
          v-if="estado === 'gravando'"
          type="button"
          class="rounded-lg border border-n-weak px-3 py-2 text-sm text-n-slate-12"
          @click="pausar"
        >
          {{ t('RAMON.REUNIOES.PAUSE') }}
        </button>
        <button
          v-else
          type="button"
          class="rounded-lg border border-n-weak px-3 py-2 text-sm text-n-slate-12"
          @click="continuar"
        >
          {{ t('RAMON.REUNIOES.RESUME') }}
        </button>
        <button
          type="button"
          class="rounded-lg bg-n-brand px-4 py-2 text-sm font-medium text-white"
          data-testid="recorder-stop"
          @click="encerrar"
        >
          {{ t('RAMON.REUNIOES.STOP') }}
        </button>
        <button
          type="button"
          class="rounded-lg px-3 py-2 text-sm text-n-slate-11"
          @click="descartar"
        >
          {{ t('RAMON.REUNIOES.CANCEL') }}
        </button>
      </template>
      <span v-else class="text-sm text-n-slate-11">
        {{ t('RAMON.REUNIOES.UPLOADING', { progress: progresso }) }}
      </span>
    </div>
  </div>
</template>
```

- [ ] **Step 2: `Reunioes.vue`** (seguir o esqueleto de `Calculos.vue` pro header/erro — raiz `w-full h-full`, padrão do fork)

```vue
<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import ReunioesAPI from 'dashboard/api/reunioes';
import RamonPageHeader from '../components/RamonPageHeader.vue';
import ReuniaoRecorder from '../components/reunioes/ReuniaoRecorder.vue';

defineOptions({ name: 'RamonReunioes' });

const { t } = useI18n();
const route = useRoute();
const router = useRouter();

const reunioes = ref([]);
const isLoading = ref(false);
const hasError = ref(false);

const reuniaoId = computed(() => route.params.reuniaoId);

const carregar = async () => {
  isLoading.value = true;
  hasError.value = false;
  try {
    const { data } = await ReunioesAPI.get();
    reunioes.value = data.payload;
  } catch {
    hasError.value = true;
  } finally {
    isLoading.value = false;
  }
};

const abrir = id => {
  router.push({ name: 'ramon_reuniao', params: { reuniaoId: id } });
};

const onCreated = reuniao => abrir(reuniao.id);

const statusLabel = status =>
  t(`RAMON.REUNIOES.STATUS_${status.toUpperCase()}`);

const formatoData = iso =>
  new Date(iso).toLocaleString('pt-BR', { dateStyle: 'short', timeStyle: 'short' });

const formatoDuracao = total => {
  if (!total) return '—';
  const min = Math.floor(total / 60);
  return `${min}min`;
};

onMounted(carregar);
</script>

<template>
  <div class="flex h-full w-full flex-col overflow-y-auto p-8">
    <template v-if="!reuniaoId">
      <RamonPageHeader :title="t('RAMON.REUNIOES.TITLE')" />
      <ReuniaoRecorder class="mb-6" @created="onCreated" />
      <div v-if="hasError" class="flex items-center gap-2 text-sm text-n-ruby-11">
        {{ t('RAMON.REUNIOES.LOAD_ERROR') }}
        <button type="button" class="underline" @click="carregar">
          {{ t('RAMON.REUNIOES.REPROCESS') }}
        </button>
      </div>
      <p v-else-if="!isLoading && !reunioes.length" class="text-sm text-n-slate-11">
        {{ t('RAMON.REUNIOES.EMPTY') }}
      </p>
      <ul v-else class="flex flex-col divide-y divide-n-weak">
        <li v-for="reuniao in reunioes" :key="reuniao.id">
          <button
            type="button"
            class="flex w-full items-center justify-between gap-4 py-3 text-start"
            @click="abrir(reuniao.id)"
          >
            <span class="min-w-0 flex-1 truncate text-sm font-medium text-n-slate-12">
              {{ reuniao.titulo }}
            </span>
            <span class="text-xs text-n-slate-11">{{ formatoDuracao(reuniao.duracao_segundos) }}</span>
            <span class="text-xs text-n-slate-11">{{ formatoData(reuniao.created_at) }}</span>
            <span
              class="rounded-full px-2 py-0.5 text-xs"
              :class="{
                'bg-n-teal-3 text-n-teal-11': reuniao.status === 'pronta',
                'bg-n-amber-3 text-n-amber-11': reuniao.status === 'transcrevendo',
                'bg-n-ruby-3 text-n-ruby-11': reuniao.status === 'erro',
              }"
            >
              {{ statusLabel(reuniao.status) }}
            </span>
          </button>
        </li>
      </ul>
    </template>
    <!-- Task 7 substitui este placeholder pelo ReuniaoDetalhe -->
    <div v-else />
  </div>
</template>
```

(Antes de commitar: conferir em `Calculos.vue` o nome/props reais do `RamonPageHeader` e as cores de badge usadas no fork — usar as mesmas classes `n-*` que já existem lá; ajustar se divergirem.)

- [ ] **Step 3: Vitest do recorder** — mock de `MediaRecorder`/`getUserMedia`; testa o ciclo gravar→encerrar→upload→emit:

```js
import { mount } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import ReuniaoRecorder from '../../components/reunioes/ReuniaoRecorder.vue';
import ReunioesAPI from 'dashboard/api/reunioes';

vi.mock('dashboard/api/reunioes', () => ({
  default: { criar: vi.fn() },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

class FakeMediaRecorder {
  constructor() {
    FakeMediaRecorder.instance = this;
    this.ondataavailable = null;
    this.onstop = null;
  }

  start() {}

  pause() {}

  resume() {}

  stop() {
    this.ondataavailable?.({ data: new Blob(['x'], { type: 'audio/webm' }) });
    this.onstop?.();
  }
}
FakeMediaRecorder.isTypeSupported = () => true;

describe('ReuniaoRecorder', () => {
  beforeEach(() => {
    vi.stubGlobal('MediaRecorder', FakeMediaRecorder);
    vi.stubGlobal('navigator', {
      mediaDevices: { getUserMedia: vi.fn().mockResolvedValue({ getTracks: () => [] }) },
    });
    ReunioesAPI.criar.mockResolvedValue({ data: { id: 7, status: 'transcrevendo' } });
  });

  it('records, uploads and emits created', async () => {
    const wrapper = mount(ReuniaoRecorder);
    await wrapper.find('[data-testid="recorder-start"]').trigger('click');
    await wrapper.vm.$nextTick();
    await wrapper.find('[data-testid="recorder-stop"]').trigger('click');
    await new Promise(resolve => {
      setTimeout(resolve);
    });
    expect(ReunioesAPI.criar).toHaveBeenCalled();
    const formData = ReunioesAPI.criar.mock.calls[0][0];
    expect(formData.get('audio')).toBeTruthy();
    expect(wrapper.emitted('created')[0][0]).toEqual({ id: 7, status: 'transcrevendo' });
  });
});
```

- [ ] **Step 4: Rodar vitest e lint**

Run: `npx vitest run app/javascript/dashboard/routes/dashboard/ramon`
Expected: PASS (novo spec + os existentes intactos)

Run: `pnpm eslint app/javascript/dashboard/routes/dashboard/ramon/pages/Reunioes.vue app/javascript/dashboard/routes/dashboard/ramon/components/reunioes/ReuniaoRecorder.vue --fix`

- [ ] **Step 5: Commit**

```bash
git add app/javascript/dashboard/routes/dashboard/ramon/components/reunioes/ReuniaoRecorder.vue app/javascript/dashboard/routes/dashboard/ramon/pages/Reunioes.vue app/javascript/dashboard/routes/dashboard/ramon/pages/specs/ReuniaoRecorder.spec.js
git commit --no-verify -m "feat(reunioes): tela de gravacao e lista"
```

---

### Task 7: Front — detalhe (`ReuniaoDetalhe.vue`): ata, player, transcrição, polling

**Files:**
- Create: `app/javascript/dashboard/routes/dashboard/ramon/components/reunioes/ReuniaoDetalhe.vue`
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/pages/Reunioes.vue` (trocar o placeholder `<div v-else />` por `<ReuniaoDetalhe v-else :reuniao-id="reuniaoId" @deleted="router.push({ name: 'ramon_reunioes' })" />` + import)
- Test: `app/javascript/dashboard/routes/dashboard/ramon/pages/specs/ReuniaoDetalhe.spec.js`

**Interfaces:**
- Consumes: `ReunioesAPI.show(id)` / `.reprocessar(id)` / `.delete(id)` (Task 5); detalhe `{ id, titulo, status, duracao_segundos, created_at, user_name, transcricao, ata, erro, audio_url }` (Task 4); `useMessageFormatter` de `shared/composables/useMessageFormatter` (markdown→HTML, padrão do `LeadTriage.vue:216`).
- Produces: emite `deleted` após apagar.

- [ ] **Step 1: `ReuniaoDetalhe.vue`**

```vue
<script setup>
import { onBeforeUnmount, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMessageFormatter } from 'shared/composables/useMessageFormatter';
import ReunioesAPI from 'dashboard/api/reunioes';
import { useAlert } from 'dashboard/composables';

defineOptions({ name: 'ReuniaoDetalhe' });

const props = defineProps({
  reuniaoId: { type: [String, Number], required: true },
});
const emit = defineEmits(['deleted']);

const { t } = useI18n();
const { formatMessage } = useMessageFormatter();

const reuniao = ref(null);
const hasError = ref(false);
const mostrarTranscricao = ref(false);
let poll = null;

// ponytail: polling de 10s enquanto processa — sem canal ActionCable novo.
const agendarPoll = () => {
  clearInterval(poll);
  if (reuniao.value?.status === 'transcrevendo') {
    poll = setInterval(carregar, 10000);
  }
};

const carregar = async () => {
  try {
    const { data } = await ReunioesAPI.show(props.reuniaoId);
    reuniao.value = data;
    hasError.value = false;
  } catch {
    hasError.value = true;
  }
  agendarPoll();
};

const reprocessar = async () => {
  try {
    const { data } = await ReunioesAPI.reprocessar(props.reuniaoId);
    reuniao.value = data;
    agendarPoll();
  } catch {
    useAlert(t('RAMON.REUNIOES.LOAD_ERROR'));
  }
};

const apagar = async () => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(t('RAMON.REUNIOES.DELETE_CONFIRM'))) return;
  await ReunioesAPI.delete(props.reuniaoId);
  emit('deleted');
};

onMounted(carregar);
onBeforeUnmount(() => clearInterval(poll));
</script>

<template>
  <div v-if="reuniao" class="mx-auto flex w-full max-w-3xl flex-col gap-6">
    <div class="flex items-start justify-between gap-4">
      <div class="min-w-0">
        <h1 class="truncate text-xl font-semibold text-n-slate-12">{{ reuniao.titulo }}</h1>
        <p v-if="reuniao.user_name" class="text-sm text-n-slate-11">
          {{ t('RAMON.REUNIOES.RECORDED_BY', { name: reuniao.user_name }) }}
        </p>
      </div>
      <button
        type="button"
        class="shrink-0 text-sm text-n-ruby-11"
        data-testid="reuniao-delete"
        @click="apagar"
      >
        {{ t('RAMON.REUNIOES.DELETE') }}
      </button>
    </div>

    <div
      v-if="reuniao.status === 'transcrevendo'"
      class="rounded-lg bg-n-amber-3 p-4 text-sm text-n-amber-11"
      data-testid="reuniao-processing"
    >
      {{ t('RAMON.REUNIOES.PROCESSING_HINT') }}
    </div>

    <div
      v-else-if="reuniao.status === 'erro'"
      class="flex items-center justify-between gap-4 rounded-lg bg-n-ruby-3 p-4 text-sm text-n-ruby-11"
    >
      <span class="min-w-0 truncate">{{ reuniao.erro }}</span>
      <button
        type="button"
        class="shrink-0 underline"
        data-testid="reuniao-reprocess"
        @click="reprocessar"
      >
        {{ t('RAMON.REUNIOES.REPROCESS') }}
      </button>
    </div>

    <section v-if="reuniao.ata">
      <h2 class="mb-2 text-sm font-semibold uppercase text-n-slate-11">
        {{ t('RAMON.REUNIOES.ATA_TITLE') }}
      </h2>
      <div
        class="text-sm text-n-slate-12 [&_h2]:mb-1 [&_h2]:mt-4 [&_h2]:font-semibold [&_li]:mb-1 [&_p]:mb-2 [&_ul]:list-disc [&_ul]:ps-4"
        data-testid="reuniao-ata"
        v-html="formatMessage(reuniao.ata)"
      />
    </section>

    <section v-if="reuniao.audio_url">
      <h2 class="mb-2 text-sm font-semibold uppercase text-n-slate-11">
        {{ t('RAMON.REUNIOES.AUDIO_TITLE') }}
      </h2>
      <audio controls :src="reuniao.audio_url" class="w-full" />
    </section>

    <section v-if="reuniao.transcricao">
      <button
        type="button"
        class="mb-2 text-sm font-semibold uppercase text-n-slate-11 underline"
        data-testid="reuniao-toggle-transcricao"
        @click="mostrarTranscricao = !mostrarTranscricao"
      >
        {{ t('RAMON.REUNIOES.TRANSCRICAO_TITLE') }}
      </button>
      <p v-if="mostrarTranscricao" class="whitespace-pre-wrap text-sm text-n-slate-11">
        {{ reuniao.transcricao }}
      </p>
    </section>
  </div>
  <div v-else-if="hasError" class="flex items-center gap-2 text-sm text-n-ruby-11">
    {{ t('RAMON.REUNIOES.LOAD_ERROR') }}
    <button type="button" class="underline" @click="carregar">
      {{ t('RAMON.REUNIOES.REPROCESS') }}
    </button>
  </div>
</template>
```

(`v-html` com `formatMessage` é o padrão existente do fork — `LeadTriage.vue:216`; se o eslint reclamar de `vue/no-v-html`, usar o mesmo disable que o arquivo vizinho usa.)

- [ ] **Step 2: Ligar no `Reunioes.vue`** — substituir `<div v-else />` por:

```vue
    <ReuniaoDetalhe
      v-else
      :reuniao-id="reuniaoId"
      @deleted="router.push({ name: 'ramon_reunioes' })"
    />
```

e adicionar `import ReuniaoDetalhe from '../components/reunioes/ReuniaoDetalhe.vue';`. Acrescentar também um botão "Voltar" (`RAMON.REUNIOES.BACK`) acima do detalhe navegando pra `ramon_reunioes`.

- [ ] **Step 3: Vitest do detalhe** — mock da API; cobre: renderiza ata quando pronta, mostra hint quando transcrevendo, reprocessar aparece só no erro:

```js
import { flushPromises, mount } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import ReuniaoDetalhe from '../../components/reunioes/ReuniaoDetalhe.vue';
import ReunioesAPI from 'dashboard/api/reunioes';

vi.mock('dashboard/api/reunioes', () => ({
  default: { show: vi.fn(), reprocessar: vi.fn(), delete: vi.fn() },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('shared/composables/useMessageFormatter', () => ({
  useMessageFormatter: () => ({ formatMessage: texto => `<p>${texto}</p>` }),
}));

const detalhe = extra => ({
  id: 1,
  titulo: 'Semanal',
  status: 'pronta',
  ata: '## Resumo',
  transcricao: 'fala',
  audio_url: null,
  erro: null,
  user_name: 'Ramon',
  ...extra,
});

describe('ReuniaoDetalhe', () => {
  beforeEach(() => vi.clearAllMocks());

  it('renders the ata when pronta', async () => {
    ReunioesAPI.show.mockResolvedValue({ data: detalhe() });
    const wrapper = mount(ReuniaoDetalhe, { props: { reuniaoId: 1 } });
    await flushPromises();
    expect(wrapper.find('[data-testid="reuniao-ata"]').html()).toContain('Resumo');
    expect(wrapper.find('[data-testid="reuniao-reprocess"]').exists()).toBe(false);
  });

  it('shows processing hint while transcrevendo', async () => {
    ReunioesAPI.show.mockResolvedValue({ data: detalhe({ status: 'transcrevendo', ata: null }) });
    const wrapper = mount(ReuniaoDetalhe, { props: { reuniaoId: 1 } });
    await flushPromises();
    expect(wrapper.find('[data-testid="reuniao-processing"]').exists()).toBe(true);
  });

  it('offers reprocessar on erro', async () => {
    ReunioesAPI.show.mockResolvedValue({ data: detalhe({ status: 'erro', erro: 'boom', ata: null }) });
    ReunioesAPI.reprocessar.mockResolvedValue({ data: detalhe({ status: 'transcrevendo', ata: null }) });
    const wrapper = mount(ReuniaoDetalhe, { props: { reuniaoId: 1 } });
    await flushPromises();
    await wrapper.find('[data-testid="reuniao-reprocess"]').trigger('click');
    expect(ReunioesAPI.reprocessar).toHaveBeenCalledWith(1);
  });
});
```

- [ ] **Step 4: Rodar vitest e lint**

Run: `npx vitest run app/javascript/dashboard/routes/dashboard/ramon`
Expected: PASS

Run: `pnpm eslint app/javascript/dashboard/routes/dashboard/ramon/components/reunioes/ReuniaoDetalhe.vue app/javascript/dashboard/routes/dashboard/ramon/pages/Reunioes.vue --fix`

- [ ] **Step 5: Commit**

```bash
git add app/javascript/dashboard/routes/dashboard/ramon/components/reunioes/ReuniaoDetalhe.vue app/javascript/dashboard/routes/dashboard/ramon/pages/Reunioes.vue app/javascript/dashboard/routes/dashboard/ramon/pages/specs/ReuniaoDetalhe.spec.js
git commit --no-verify -m "feat(reunioes): detalhe com ata, player e reprocessar"
```

---

### Task 8: PR, CI, merge, deploy e smoke doc

**Files:**
- Create: entrada nova em `comercial\docs\` (fora do repo do hub): `2026-07-28-smoke-area-reunioes.md`

- [ ] **Step 1: Push + PR** — `git push -u origin feat/ramon-reunioes --no-verify`; `gh pr create -F corpo.md` (corpo via arquivo — aspas quebram no PS 5.1). Corpo: parágrafo do produto + How to test.
- [ ] **Step 2: CI verde** — poll com `gh pr checks`; `conclusion` em andamento vem como `""` (filtrar vazio E null). Se um shard core sem relação falhar: suspeitar reshuffle do knapsack (lição 20/07) — reduzir footprint de spec antes de caçar a lógica.
- [ ] **Step 3: Merge + deploy** — regime autônomo (CI verde): merge; esperar workflow "Publica imagem"; na VPS `docker compose pull chatwoot-web chatwoot-worker && docker compose up -d` puxando por `sha-<mergesha>` e retag (NÃO confiar na tag flutuante — lição 20/07 (7)). **Migração NÃO roda no entrypoint: `docker exec ... bundle exec rails db:migrate RAILS_ENV=production` na mão + restart, e conferir a tabela no psql** (lição 27/07).
- [ ] **Step 4: Smoke técnico** — `/api` 200; `docker exec ... grep ramon_reunioes config/routes.rb`; criar reunião de teste via console (`rails runner`) com áudio pequeno e ver o job completar (status `pronta`, ata preenchida) — apagar o registro de teste depois.
- [ ] **Step 5: Doc de smoke pro Eduardo** — `comercial\docs\2026-07-28-smoke-area-reunioes.md`: roteiro visual (gravar 1 min falando, ver timer, encerrar, acompanhar transcrevendo→ata, testar Reprocessar não aparece, apagar) + atualizar a memória do hub.

---

## Self-review (feito na escrita)

- **Cobertura da spec:** modelo/migração (T1), whisper+ata (T2), job+erro (T3), API+policy+25MB+reprocessar (T4), menu+rotas+i18n (T5), gravador+lista (T6), detalhe+polling+player+transcrição recolhida (T7), deploy+smoke (T8). Fora da v1 continua fora.
- **Tipos consistentes:** `ReunioesAPI.criar/reprocessar/show/get/delete`; payload `detalhe` idêntico entre T4 e T7; evento `created`/`deleted` camelCase-safe (sem hífen).
- **Sem placeholders:** todo step tem código real; o único placeholder intencional (`<div v-else />` na T6) é substituído explicitamente na T7.
