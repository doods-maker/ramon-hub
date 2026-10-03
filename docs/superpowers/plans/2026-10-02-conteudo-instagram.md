# Conteúdo do Instagram dentro do hub — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** O ciclo pauta → aprovação → montagem → agenda → publicação de carrossel/estático do Instagram acontece inteiro no ramon-hub, sem comando local.

**Architecture:** O hub (Rails/Vue, fork Chatwoot) guarda as peças em `ramon_pecas`, expõe uma API por token pra rotina cloud (cria pauta) e pro worker (pega peça aprovada, devolve JPEGs), mostra a tela "Conteúdo" (kanban + prévia como post do IG) e publica por cron Sidekiq na Graph API do Instagram. O worker é um container Node+Playwright na VPS rodando o `build.mjs` do motor-marketing. Notion recebe só espelho de status.

**Tech Stack:** Rails 7.1 + RSpec + WebMock · Vue 3 `<script setup>` + Tailwind + Vitest · Sidekiq-cron · Node 22 (`node --test`) + Playwright 1.61.1 + sharp · Graph API `graph.instagram.com/v26.0`.

**Spec:** `docs/superpowers/specs/2026-10-02-conteudo-instagram-design.md` (aprovada 02/10/2026).

## Global Constraints

- Repos: `ramon-hub` (worktree `ramon-hub-wt-conteudo`, branch `feat/conteudo-instagram`, base `origin/ramon`) e `motor-marketing` (branch `main`, repo local `comercial/projetos/motor-marketing`).
- **Sem Ruby/Postgres local:** RSpec e rubocop só rodam no CI do PR. Localmente: `pnpm eslint` (via junction) e `node --test` no motor. Vitest NÃO roda via junction — também só no CI.
- Migração nova → regenerar `db/schema.rb` via scratch DB na VPS (procedimento em `memory/arquivo/ramon-hub-frentes-historico-ate-0707.md` §F2.1a). Deploy não roda migração: `db:migrate` à mão.
- Ruby: rubocop 150 colunas, `class Ramon::X` compacto. Vue: Composition API `<script setup>`, só Tailwind, eventos camelCase, nada de string solta no template (i18n em `i18n/locale/pt_BR/ramon.json` **e** `en/ramon.json`, bloco `RAMON.CONTEUDO` + `RAMON.NAV.CONTEUDO`).
- Commits Conventional, sem citar Claude no título; trailers de sessão no fim. Commitar só paths explícitos. `git push` é do Eduardo (`!`); `gh pr merge` e deploy por ssh podem ser do Claude com CI 100% verde.
- Formatos v1: `carrossel` e `estatico`. **Só feed** — nunca `media_type=STORIES`.
- Grade: **ter/qua/qui 12h00 America/Sao_Paulo**.
- Legenda/arte seguem as regras do motor (OAB-safe; emoji só na legenda). Publicar exige clique do Eduardo ("Aprovar e agendar"/"Publicar agora").
- Status válidos: `rascunho aprovado montando montado agendado publicando publicado reprovado falhou`.
- Tokens/segredos nunca em código, prompt ou chat: `RAMON_CONTEUDO_TOKEN`, `RAMON_NOTION_TOKEN`, `GOOGLE_API_KEY`, `RAMON_IG_PUBLISH_TOKEN`.

## Review Focus

1. **Post em dobro.** Cron sobreposto, clique duplo em "Publicar agora" ou "Tentar de novo" depois de um publish que deu certo mas não gravou → a Meta recebe 2 posts. Esperado: nunca publicar se `ig_media_id` existe; `publicando` > 15 min vira `falhou` com "conferir no Instagram". (Tasks 15, 16)
2. **Refação em loop.** Worker falha numa refação e a peça volta a ser elegível pra sempre (`refazer_cards` não zerado) → Gemini cobrado a cada 30 s. Esperado: `falha` zera `refazer_cards`. (Task 8)
3. **Vigia local montando junto.** Espelho grava `aprovado` no Notion e o `montar-aprovados.mjs` do PC também monta → custo dobrado e Drive duplicado. Esperado: `montando` não é espelhado; vigia desligado no deploy do PR 2. (Tasks 3, 12)
4. **Status mudou por baixo da tela.** Eduardo clica "Aprovar e agendar" numa peça que o worker acabou de pôr em `montando`. Esperado: 409 com mensagem clara, tela recarrega, nada muda. (Task 4)
5. **Agendar no passado / slot ocupado.** Data digitada já passou, ou a sugestão cai num slot já tomado. Esperado: 422 pra passado; sugestão pula slots com peça `agendado/publicando/publicado`. (Tasks 13, 16)

---

# PR 1 — Pauta no hub (+ espelho Notion)

### Task 1: Tabela `ramon_pecas` + model `Peca`

**Files:**
- Create: `db/migrate/20261002000001_create_ramon_pecas.rb`
- Create: `app/models/peca.rb`
- Modify: `app/models/account.rb` (junto dos `has_many :reunioes`, ~linha 89)
- Create: `spec/factories/pecas.rb`
- Test: `spec/models/peca_spec.rb`

**Interfaces:**
- Produces: `Peca` (table `ramon_pecas`), `Peca::STATUSES`, `Peca::TIPOS`, `Peca::TransicaoInvalida`, `Peca#transicionar!(de:, para:, **attrs)` (lock + valida origem + `update!`), `Peca#travada?`, `Account#pecas`, factory `:peca`. Callback enfileira `Ramon::NotionEspelhoJob.perform_later(id)` quando `status` muda.

- [ ] **Step 1: Migração**

```ruby
class CreateRamonPecas < ActiveRecord::Migration[7.1]
  def change
    create_table :ramon_pecas do |t|
      t.references :account, null: false, foreign_key: true
      t.string :slug, null: false
      t.date :rodada, null: false
      t.string :tipo, null: false
      t.string :estilo
      t.string :tese
      t.string :gancho, null: false
      t.jsonb :conteudo, null: false, default: {}
      t.text :legenda
      t.string :status, null: false, default: 'rascunho'
      t.jsonb :imagens, null: false, default: []
      t.integer :refazer_cards, array: true, null: false, default: []
      t.datetime :agendado_para
      t.datetime :montagem_iniciada_em
      t.datetime :publicacao_iniciada_em
      t.string :ig_media_id
      t.string :permalink
      t.text :erro
      t.text :nota_reprovacao
      t.string :notion_page_id
      t.string :drive_pasta_id
      t.timestamps
    end
    add_index :ramon_pecas, [:account_id, :slug], unique: true
    add_index :ramon_pecas, [:status, :agendado_para]
  end
end
```

- [ ] **Step 2: Factory**

```ruby
FactoryBot.define do
  factory :peca do
    account
    sequence(:slug) { |n| "0#{n}-peca-teste" }
    rodada { Date.new(2026, 10, 1) }
    tipo { 'carrossel' }
    gancho { 'Auxílio-acidente: quem tem direito' }
    conteudo { { 'fields' => { 'capa_titulo' => 'Título' }, 'legenda' => 'Legenda base', 'hashtags' => ['#inss', '#auxilioacidente'] } }
  end
end
```

- [ ] **Step 3: Teste do model (falha)**

```ruby
require 'rails_helper'

RSpec.describe Peca do
  it 'monta a legenda inicial com as hashtags' do
    expect(create(:peca).legenda).to eq "Legenda base\n\n#inss #auxilioacidente"
  end

  it 'mantém legenda informada' do
    expect(create(:peca, legenda: 'minha').legenda).to eq 'minha'
  end

  it 'slug é único por conta' do
    peca = create(:peca)
    expect(build(:peca, account: peca.account, slug: peca.slug)).not_to be_valid
  end

  it 'transiciona quando a origem bate' do
    peca = create(:peca)
    peca.transicionar!(de: 'rascunho', para: 'aprovado')
    expect(peca.reload.status).to eq 'aprovado'
  end

  it 'recusa transição de origem errada' do
    peca = create(:peca, status: 'montando')
    expect { peca.transicionar!(de: 'rascunho', para: 'aprovado') }.to raise_error(Peca::TransicaoInvalida)
    expect(peca.reload.status).to eq 'montando'
  end

  it 'enfileira o espelho do Notion só quando o status muda' do
    peca = create(:peca)
    expect { peca.update!(legenda: 'x') }.not_to have_enqueued_job(Ramon::NotionEspelhoJob)
    expect { peca.update!(status: 'aprovado') }.to have_enqueued_job(Ramon::NotionEspelhoJob).with(peca.id)
  end

  it 'travada? quando montando há mais de 15 min' do
    expect(build(:peca, status: 'montando', montagem_iniciada_em: 16.minutes.ago)).to be_travada
    expect(build(:peca, status: 'montando', montagem_iniciada_em: 5.minutes.ago)).not_to be_travada
  end
end
```

- [ ] **Step 4: Model**

```ruby
# Peça de conteúdo do Instagram (carrossel/estático): pauta da rotina cloud →
# aprovação → montagem (worker na VPS) → agenda → publicação.
# Spec: docs/superpowers/specs/2026-10-02-conteudo-instagram-design.md
class Peca < ApplicationRecord
  self.table_name = 'ramon_pecas'

  STATUSES = %w[rascunho aprovado montando montado agendado publicando publicado reprovado falhou].freeze
  TIPOS = %w[carrossel estatico].freeze
  TRAVA = 15.minutes

  class TransicaoInvalida < StandardError; end

  belongs_to :account

  validates :slug, presence: true, uniqueness: { scope: :account_id }
  validates :gancho, :rodada, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :tipo, inclusion: { in: TIPOS }

  before_validation :legenda_inicial, on: :create
  after_update_commit :espelhar_notion, if: :saved_change_to_status?

  # Toda mudança de status passa por aqui: trava a linha e confere a origem, pra
  # tela, worker e cron nunca atropelarem um ao outro.
  def transicionar!(de:, para:, **attrs)
    with_lock do
      raise TransicaoInvalida, "#{status} → #{para}" unless Array(de).include?(status)

      update!(status: para, **attrs)
    end
  end

  def travada?
    status == 'montando' && montagem_iniciada_em.present? && montagem_iniciada_em < TRAVA.ago
  end

  private

  def legenda_inicial
    return if legenda.present?

    tags = Array(conteudo['hashtags']).join(' ')
    self.legenda = [conteudo['legenda'], tags.presence].compact.join("\n\n")
  end

  def espelhar_notion
    Ramon::NotionEspelhoJob.perform_later(id)
  end
end
```

Em `app/models/account.rb`, logo abaixo de `has_many :reunioes, ...`:

```ruby
  has_many :pecas, class_name: 'Peca', dependent: :destroy_async
```

- [ ] **Step 5: Commit** (o teste roda no CI junto com a Task 3, que cria o job)

```bash
git add db/migrate/20261002000001_create_ramon_pecas.rb app/models/peca.rb app/models/account.rb spec/factories/pecas.rb spec/models/peca_spec.rb
git commit -m "feat(conteudo): tabela ramon_pecas e model Peca com transições travadas"
```

### Task 2: API pública — rotina cria pauta (`POST /public/api/v1/conteudo/pecas`)

**Files:**
- Create: `app/controllers/public/api/v1/conteudo_controller.rb`
- Modify: `config/routes.rb` (bloco público, logo após `post 'agente/execucoes'`, ~linha 711)
- Test: `spec/requests/public/api/v1/conteudo_spec.rb`

**Interfaces:**
- Consumes: `Account#pecas`, `Peca`.
- Produces: header `X-Conteudo-Token` (= `ENV['RAMON_CONTEUDO_TOKEN']`), conta = `ENV['RAMON_CONTEUDO_ACCOUNT_ID']`. `POST conteudo/pecas` body `{slug, rodada, tipo, gancho, estilo?, tese?, notion_page_id?, conteudo}` → 201 `{id, status}` (nova) / 200 (slug já existia, nada muda). Métodos privados `conta`, `verify_token`, `payload(peca)` reaproveitados nas Tasks 8.

- [ ] **Step 1: Teste (falha)**

```ruby
require 'rails_helper'

RSpec.describe 'Public Conteudo API', type: :request do
  let(:account) { create(:account) }
  let(:token) { 'conteudo-teste' }
  let(:headers) { { 'CONTENT_TYPE' => 'application/json', 'X-Conteudo-Token' => token } }
  let(:corpo) do
    { slug: '01-auxilio-acidente', rodada: '2026-10-01', tipo: 'carrossel', gancho: 'Quem tem direito',
      estilo: 'fluxo', tese: 'auxilio-acidente', notion_page_id: 'np1',
      conteudo: { fields: { capa_titulo: 'T' }, legenda: 'L', hashtags: ['#inss'] } }
  end

  around { |ex| with_modified_env(RAMON_CONTEUDO_TOKEN: token, RAMON_CONTEUDO_ACCOUNT_ID: account.id.to_s) { ex.run } }

  it 'rejeita token errado' do
    post '/public/api/v1/conteudo/pecas', params: corpo.to_json, headers: headers.merge('X-Conteudo-Token' => 'x')
    expect(response).to have_http_status(:unauthorized)
  end

  it 'cria a pauta em rascunho' do
    post '/public/api/v1/conteudo/pecas', params: corpo.to_json, headers: headers
    expect(response).to have_http_status(:created)
    peca = account.pecas.last
    expect(peca).to have_attributes(slug: '01-auxilio-acidente', status: 'rascunho', tipo: 'carrossel',
                                    notion_page_id: 'np1', legenda: "L\n\n#inss")
    expect(peca.conteudo['fields']['capa_titulo']).to eq 'T'
  end

  it 'é idempotente pelo slug (rotina pode re-rodar)' do
    2.times { post '/public/api/v1/conteudo/pecas', params: corpo.to_json, headers: headers }
    expect(response).to have_http_status(:ok)
    expect(account.pecas.count).to eq 1
  end

  it '422 com tipo fora da v1' do
    post '/public/api/v1/conteudo/pecas', params: corpo.merge(tipo: 'video').to_json, headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
  end
end
```

- [ ] **Step 2: Controller**

```ruby
# API de conteúdo do Instagram pra rotina cloud (cria pauta) e pro worker de
# montagem na VPS. Token no header X-Conteudo-Token; conta fixa por env.
# Spec: docs/superpowers/specs/2026-10-02-conteudo-instagram-design.md §4.2
class Public::Api::V1::ConteudoController < PublicController
  before_action :verify_token

  def criar
    peca = conta.pecas.find_by(slug: params.require(:slug))
    return render json: { id: peca.id, status: peca.status }, status: :ok if peca

    peca = conta.pecas.create(peca_params)
    return render json: { error: peca.errors.full_messages.to_sentence }, status: :unprocessable_entity unless peca.persisted?

    render json: { id: peca.id, status: peca.status }, status: :created
  end

  private

  def conta
    @conta ||= Account.find(ENV.fetch('RAMON_CONTEUDO_ACCOUNT_ID'))
  end

  def peca_params
    { slug: params[:slug], rodada: params.require(:rodada), tipo: params.require(:tipo), gancho: params.require(:gancho),
      estilo: params[:estilo], tese: params[:tese], notion_page_id: params[:notion_page_id],
      conteudo: params.require(:conteudo).to_unsafe_h }
  end

  def verify_token
    secret = ENV.fetch('RAMON_CONTEUDO_TOKEN', nil)
    provided = request.headers['X-Conteudo-Token'].to_s
    return if secret.present? && provided.present? && ActiveSupport::SecurityUtils.secure_compare(provided, secret)

    head :unauthorized
  end
end
```

- [ ] **Step 3: Rota** — em `config/routes.rb`, logo após `post 'agente/execucoes', to: 'agente#execucoes'`:

```ruby
        # Ramon — conteúdo do Instagram (rotina cloud + worker de montagem). Token no header X-Conteudo-Token.
        post 'conteudo/pecas', to: 'conteudo#criar'
```

- [ ] **Step 4: Commit**

```bash
git add app/controllers/public/api/v1/conteudo_controller.rb config/routes.rb spec/requests/public/api/v1/conteudo_spec.rb
git commit -m "feat(conteudo): API pública pra rotina cloud criar pauta"
```

### Task 3: Espelho de status no Notion

**Files:**
- Create: `app/jobs/ramon/notion_espelho_job.rb`
- Test: `spec/jobs/ramon/notion_espelho_job_spec.rb`

**Interfaces:**
- Consumes: `Peca#notion_page_id`, `Peca#status`.
- Produces: `Ramon::NotionEspelhoJob.perform_later(peca_id)` — PATCH `Status` (select) na página. Mapa: `rascunho→rascunho`, `aprovado→aprovado`, `montado→montado`, `agendado→montado`, `publicado→publicado`; resto (incl. `montando`) não escreve.

- [ ] **Step 1: Teste (falha)**

```ruby
require 'rails_helper'

RSpec.describe Ramon::NotionEspelhoJob do
  let(:peca) { create(:peca, notion_page_id: 'pg1') }
  let(:url) { 'https://api.notion.com/v1/pages/pg1' }

  it 'não chama o Notion sem token' do
    with_modified_env(RAMON_NOTION_TOKEN: nil) { described_class.perform_now(peca.id) }
    expect(a_request(:patch, url)).not_to have_been_made
  end

  it 'agendado aparece como montado' do
    peca.update_columns(status: 'agendado')
    stub = stub_request(:patch, url)
           .with(body: { properties: { 'Status' => { select: { name: 'montado' } } } }.to_json,
                 headers: { 'Authorization' => 'Bearer nt', 'Notion-Version' => '2022-06-28' })
           .to_return(status: 200)
    with_modified_env(RAMON_NOTION_TOKEN: 'nt') { described_class.perform_now(peca.id) }
    expect(stub).to have_been_requested
  end

  it 'montando não é espelhado (senão o vigia local monta junto)' do
    peca.update_columns(status: 'montando')
    with_modified_env(RAMON_NOTION_TOKEN: 'nt') { described_class.perform_now(peca.id) }
    expect(a_request(:patch, url)).not_to have_been_made
  end

  it 'erro do Notion não levanta' do
    stub_request(:patch, url).to_return(status: 500)
    with_modified_env(RAMON_NOTION_TOKEN: 'nt') { expect { described_class.perform_now(peca.id) }.not_to raise_error }
  end
end
```

- [ ] **Step 2: Job**

```ruby
# Espelho de status da peça no kanban "Peças" do Notion durante a transição
# (hub é a fonte da verdade). Desliga tirando RAMON_NOTION_TOKEN. Best-effort.
class Ramon::NotionEspelhoJob < ApplicationJob
  queue_as :low

  # `montando` fica de fora: gravar "aprovado" de novo acordaria o vigia local.
  MAPA = { 'rascunho' => 'rascunho', 'aprovado' => 'aprovado', 'montado' => 'montado',
           'agendado' => 'montado', 'publicado' => 'publicado' }.freeze

  def perform(peca_id)
    token = ENV.fetch('RAMON_NOTION_TOKEN', nil)
    peca = Peca.find_by(id: peca_id)
    status = MAPA[peca&.status]
    return if token.blank? || peca&.notion_page_id.blank? || status.nil?

    res = patch(peca.notion_page_id, status, token)
    Rails.logger.warn("NotionEspelho #{peca.slug}: HTTP #{res.code}") unless res.is_a?(Net::HTTPSuccess)
  rescue StandardError => e
    Rails.logger.warn("NotionEspelho falhou p/ peça #{peca_id}: #{e.class} #{e.message}")
  end

  private

  def patch(page_id, status, token)
    uri = URI("https://api.notion.com/v1/pages/#{page_id}")
    req = Net::HTTP::Patch.new(uri, 'Authorization' => "Bearer #{token}", 'Notion-Version' => '2022-06-28',
                                    'Content-Type' => 'application/json')
    req.body = { properties: { 'Status' => { select: { name: status } } } }.to_json
    Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) { |http| http.request(req) }
  end
end
```

- [ ] **Step 3: Commit**

```bash
git add app/jobs/ramon/notion_espelho_job.rb spec/jobs/ramon/notion_espelho_job_spec.rb
git commit -m "feat(conteudo): espelho de status da peça no Notion"
```

### Task 4: API interna da tela — listar, ver, aprovar, reprovar

**Files:**
- Create: `app/controllers/api/v1/accounts/ramon_conteudo_controller.rb`
- Create: `app/policies/peca_policy.rb`
- Modify: `config/routes.rb` (após o bloco `resources :ramon_reunioes`, ~linha 302)
- Test: `spec/requests/api/v1/accounts/ramon_conteudo_spec.rb`

**Interfaces:**
- Consumes: `Peca#transicionar!`, `Peca::TransicaoInvalida`, `Peca#travada?`.
- Produces: rotas `GET ramon_conteudo`, `GET ramon_conteudo/:id`, `POST ramon_conteudo/:id/aprovar`, `POST ramon_conteudo/:id/reprovar` (`nota`). JSON da linha: `{id, slug, rodada, tipo, estilo, tese, gancho, status, capa, agendado_para, erro, travada, permalink}`; detalhe = linha + `{conteudo, legenda, imagens, nota_reprovacao}`. 409 `{error}` em transição inválida. Só administrador. Métodos privados `linha`/`detalhe` são estendidos nas Tasks 9 e 16.

- [ ] **Step 1: Teste (falha)**

```ruby
require 'rails_helper'

RSpec.describe 'Ramon Conteudo API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let!(:peca) { create(:peca, account: account) }
  let(:base) { "/api/v1/accounts/#{account.id}/ramon_conteudo" }

  it 'agente não acessa' do
    get base, headers: agent.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
  end

  it 'lista as peças (sem reprovadas)' do
    create(:peca, account: account, status: 'reprovado')
    get base, headers: admin.create_new_auth_token
    expect(response.parsed_body['payload'].pluck('id')).to eq [peca.id]
  end

  it 'aprova a pauta' do
    post "#{base}/#{peca.id}/aprovar", headers: admin.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(peca.reload.status).to eq 'aprovado'
  end

  it 'reprova com nota' do
    post "#{base}/#{peca.id}/reprovar", params: { nota: 'tema repetido' }, headers: admin.create_new_auth_token
    expect(peca.reload).to have_attributes(status: 'reprovado', nota_reprovacao: 'tema repetido')
  end

  it '409 quando o status mudou por baixo' do
    peca.update_columns(status: 'montando')
    post "#{base}/#{peca.id}/aprovar", headers: admin.create_new_auth_token
    expect(response).to have_http_status(:conflict)
    expect(peca.reload.status).to eq 'montando'
  end
end
```

- [ ] **Step 2: Policy**

```ruby
# Conteúdo do Instagram: só administrador (Eduardo) aprova, agenda e publica.
class PecaPolicy < ApplicationPolicy
  %i[index? show? aprovar? reprovar? atualizar_legenda? refazer? agendar? publicar_agora?
     cancelar_agendamento? tentar_de_novo?].each do |acao|
    define_method(acao) { @account_user.administrator? }
  end
end
```

- [ ] **Step 3: Controller**

```ruby
# Tela "Conteúdo": kanban das peças do Instagram e ações de aprovação/agenda.
# Spec: docs/superpowers/specs/2026-10-02-conteudo-instagram-design.md §4.3
class Api::V1::Accounts::RamonConteudoController < Api::V1::Accounts::BaseController
  LIMIT = 200

  before_action :current_account
  before_action :fetch_peca, except: [:index]
  before_action :check_authorization

  rescue_from Peca::TransicaoInvalida do |e|
    render json: { error: "A peça mudou de etapa (#{e.message}). Recarregue a tela." }, status: :conflict
  end

  def index
    pecas = Current.account.pecas.where.not(status: 'reprovado').order(created_at: :desc).limit(LIMIT)
    render json: { payload: pecas.map { |peca| linha(peca) } }
  end

  def show
    render json: detalhe(@peca)
  end

  def aprovar
    @peca.transicionar!(de: 'rascunho', para: 'aprovado', erro: nil)
    render json: detalhe(@peca)
  end

  def reprovar
    @peca.transicionar!(de: 'rascunho', para: 'reprovado', nota_reprovacao: params[:nota].presence)
    render json: detalhe(@peca)
  end

  private

  def fetch_peca
    @peca = Current.account.pecas.find(params[:id])
  end

  def check_authorization
    authorize(:peca, :"#{action_name}?")
  end

  def linha(peca)
    {
      id: peca.id, slug: peca.slug, rodada: peca.rodada, tipo: peca.tipo, estilo: peca.estilo, tese: peca.tese,
      gancho: peca.gancho, status: peca.status, capa: peca.imagens.first, agendado_para: peca.agendado_para&.iso8601,
      erro: peca.erro, travada: peca.travada?, permalink: peca.permalink
    }
  end

  def detalhe(peca)
    linha(peca).merge(conteudo: peca.conteudo, legenda: peca.legenda, imagens: peca.imagens,
                      nota_reprovacao: peca.nota_reprovacao)
  end
end
```

- [ ] **Step 4: Rotas** — após o bloco `resources :ramon_reunioes ... end`:

```ruby
          resources :ramon_conteudo, only: [:index, :show], controller: 'ramon_conteudo' do
            member do
              post :aprovar
              post :reprovar
            end
          end
```

- [ ] **Step 5: Commit**

```bash
git add app/controllers/api/v1/accounts/ramon_conteudo_controller.rb app/policies/peca_policy.rb config/routes.rb spec/requests/api/v1/accounts/ramon_conteudo_spec.rb
git commit -m "feat(conteudo): API da tela — listar, aprovar e reprovar pauta"
```

### Task 5: Tela "Conteúdo" — kanban + painel da pauta

**Files:**
- Create: `app/javascript/dashboard/api/ramonConteudo.js`
- Create: `app/javascript/dashboard/routes/dashboard/ramon/pages/Conteudo.vue`
- Create: `app/javascript/dashboard/routes/dashboard/ramon/components/conteudo/PecaPainel.vue`
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/ramon.routes.js` (após as rotas de reuniões)
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/components/IntranetSidebar.vue` (item depois de `reunioes`)
- Modify: `app/javascript/dashboard/i18n/locale/pt_BR/ramon.json`, `.../en/ramon.json`
- Test: `app/javascript/dashboard/routes/dashboard/ramon/pages/specs/Conteudo.spec.js`

**Interfaces:**
- Consumes: API da Task 4.
- Produces: `RamonConteudoAPI` (`get`, `show(id)`, `aprovar(id)`, `reprovar(id, nota)`; Tasks 10/17 adicionam métodos); `PecaPainel` props `{ pecaId: Number }`, emite `changed` (camelCase) após qualquer ação; rota `ramon_conteudo`; `COLUNAS` exportado de `Conteudo.vue` não — fica interno.

- [ ] **Step 1: Cliente da API**

```js
/* global axios */
import ApiClient from './ApiClient';

class RamonConteudoAPI extends ApiClient {
  constructor() {
    super('ramon_conteudo', { accountScoped: true });
  }

  aprovar(id) {
    return axios.post(`${this.url}/${id}/aprovar`);
  }

  reprovar(id, nota) {
    return axios.post(`${this.url}/${id}/reprovar`, { nota });
  }
}

export default new RamonConteudoAPI();
```

- [ ] **Step 2: Teste do kanban (falha)**

```js
import { flushPromises, mount } from '@vue/test-utils';
import { describe, it, expect, vi } from 'vitest';
import Conteudo from '../Conteudo.vue';
import RamonConteudoAPI from 'dashboard/api/ramonConteudo';

vi.mock('dashboard/api/ramonConteudo', () => ({ default: { get: vi.fn() } }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

const peca = (id, status, extra = {}) => ({
  id, status, gancho: `Peça ${id}`, tipo: 'carrossel', tese: 'bpc', capa: null, travada: false, ...extra,
});

describe('Conteudo', () => {
  it('distribui as peças nas 5 colunas', async () => {
    RamonConteudoAPI.get.mockResolvedValue({
      data: { payload: [peca(1, 'rascunho'), peca(2, 'montando'), peca(3, 'montado'), peca(4, 'falhou'), peca(5, 'publicado')] },
    });
    const wrapper = mount(Conteudo, { global: { stubs: { PecaPainel: true, RamonPageHeader: true } } });
    await flushPromises();
    const ids = col => wrapper.findAll(`[data-testid="coluna-${col}"] [data-testid="peca-card"]`).length;
    expect([ids('pauta'), ids('montando'), ids('prontas'), ids('agendadas'), ids('publicadas')]).toEqual([1, 1, 1, 1, 1]);
  });

  it('marca peça travada', async () => {
    RamonConteudoAPI.get.mockResolvedValue({ data: { payload: [peca(1, 'montando', { travada: true })] } });
    const wrapper = mount(Conteudo, { global: { stubs: { PecaPainel: true, RamonPageHeader: true } } });
    await flushPromises();
    expect(wrapper.find('[data-testid="peca-travada"]').exists()).toBe(true);
  });
});
```

- [ ] **Step 3: Página `Conteudo.vue`**

```vue
<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import RamonConteudoAPI from 'dashboard/api/ramonConteudo';
import RamonPageHeader from '../components/RamonPageHeader.vue';
import PecaPainel from '../components/conteudo/PecaPainel.vue';

defineOptions({ name: 'RamonConteudo' });

const { t } = useI18n();

const COLUNAS = [
  { key: 'pauta', status: ['rascunho'] },
  { key: 'montando', status: ['aprovado', 'montando'] },
  { key: 'prontas', status: ['montado'] },
  { key: 'agendadas', status: ['agendado', 'publicando', 'falhou'] },
  { key: 'publicadas', status: ['publicado'] },
];

const pecas = ref([]);
const hasError = ref(false);
const aberta = ref(null);

const porColuna = computed(() =>
  COLUNAS.map(coluna => ({
    ...coluna,
    pecas: pecas.value.filter(p => coluna.status.includes(p.status)),
  }))
);

const carregar = async () => {
  hasError.value = false;
  try {
    const { data } = await RamonConteudoAPI.get();
    pecas.value = data.payload;
  } catch {
    hasError.value = true;
  }
};

const onChanged = () => carregar();

onMounted(carregar);
</script>

<template>
  <div class="flex h-full w-full flex-col overflow-hidden p-8">
    <RamonPageHeader :title="t('RAMON.CONTEUDO.TITLE')" />
    <p v-if="hasError" class="text-sm text-n-ruby-11">
      {{ t('RAMON.CONTEUDO.LOAD_ERROR') }}
    </p>
    <div class="flex flex-1 gap-4 overflow-x-auto">
      <section
        v-for="coluna in porColuna"
        :key="coluna.key"
        :data-testid="`coluna-${coluna.key}`"
        class="flex w-64 shrink-0 flex-col gap-2 rounded-xl bg-n-alpha-1 p-3"
      >
        <h2 class="text-sm font-medium text-n-slate-12">
          {{ t(`RAMON.CONTEUDO.COLUNA.${coluna.key.toUpperCase()}`) }}
          <span class="text-n-slate-10">{{ coluna.pecas.length }}</span>
        </h2>
        <button
          v-for="peca in coluna.pecas"
          :key="peca.id"
          type="button"
          data-testid="peca-card"
          class="flex flex-col gap-1 rounded-lg bg-n-solid-1 p-2 text-left shadow-sm hover:bg-n-alpha-2"
          @click="aberta = peca.id"
        >
          <img v-if="peca.capa" :src="peca.capa" alt="" class="aspect-[4/5] w-full rounded object-cover" />
          <span class="text-sm text-n-slate-12">{{ peca.gancho }}</span>
          <span class="text-xs text-n-slate-10">
            {{ t(`RAMON.CONTEUDO.TIPO.${peca.tipo.toUpperCase()}`) }} · {{ peca.tese }}
          </span>
          <span v-if="peca.travada" data-testid="peca-travada" class="text-xs text-n-amber-11">
            {{ t('RAMON.CONTEUDO.TRAVADA') }}
          </span>
          <span v-if="peca.status === 'falhou'" class="text-xs text-n-ruby-11">
            {{ t('RAMON.CONTEUDO.FALHOU') }}
          </span>
        </button>
      </section>
    </div>
    <PecaPainel v-if="aberta" :peca-id="aberta" @changed="onChanged" @close="aberta = null" />
  </div>
</template>
```

- [ ] **Step 4: `PecaPainel.vue` (etapa Pauta; Tasks 10 e 17 acrescentam as outras)**

```vue
<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import RamonConteudoAPI from 'dashboard/api/ramonConteudo';

const props = defineProps({ pecaId: { type: Number, required: true } });
const emit = defineEmits(['changed', 'close']);

const { t } = useI18n();
const peca = ref(null);
const nota = ref('');
const ocupado = ref(false);

const campos = computed(() =>
  Object.entries(peca.value?.conteudo?.fields || {}).filter(
    ([, valor]) => typeof valor === 'string' && valor.trim()
  )
);

const carregar = async () => {
  const { data } = await RamonConteudoAPI.show(props.pecaId);
  peca.value = data;
};

const agir = async acao => {
  ocupado.value = true;
  try {
    const { data } = await acao();
    peca.value = data;
    emit('changed');
  } catch (e) {
    useAlert(e?.response?.data?.error || t('RAMON.CONTEUDO.ACAO_ERRO'));
    await carregar();
    emit('changed');
  } finally {
    ocupado.value = false;
  }
};

watch(() => props.pecaId, carregar, { immediate: true });
</script>

<template>
  <aside
    v-if="peca"
    class="fixed inset-y-0 right-0 z-50 flex w-full max-w-xl flex-col gap-4 overflow-y-auto bg-n-solid-1 p-6 shadow-xl"
  >
    <header class="flex items-start justify-between gap-2">
      <h2 class="text-lg font-medium text-n-slate-12">{{ peca.gancho }}</h2>
      <Button ghost slate sm icon="i-lucide-x" @click="emit('close')" />
    </header>
    <p v-if="peca.erro" class="rounded bg-n-ruby-3 p-2 text-sm text-n-ruby-11">{{ peca.erro }}</p>

    <template v-if="peca.status === 'rascunho'">
      <dl class="flex flex-col gap-2 text-sm">
        <div v-for="[chave, valor] in campos" :key="chave">
          <dt class="text-xs text-n-slate-10">{{ chave }}</dt>
          <dd class="whitespace-pre-line text-n-slate-12">{{ valor }}</dd>
        </div>
      </dl>
      <p class="whitespace-pre-line rounded bg-n-alpha-1 p-3 text-sm">{{ peca.legenda }}</p>
      <textarea
        v-model="nota"
        class="rounded border border-n-weak p-2 text-sm"
        :placeholder="t('RAMON.CONTEUDO.NOTA_PLACEHOLDER')"
      />
      <div class="flex gap-2">
        <Button
          :label="t('RAMON.CONTEUDO.APROVAR')"
          :is-loading="ocupado"
          data-testid="peca-aprovar"
          @click="agir(() => RamonConteudoAPI.aprovar(peca.id))"
        />
        <Button
          ruby
          outline
          :label="t('RAMON.CONTEUDO.REPROVAR')"
          :is-loading="ocupado"
          @click="agir(() => RamonConteudoAPI.reprovar(peca.id, nota))"
        />
      </div>
    </template>

    <p v-else-if="['aprovado', 'montando'].includes(peca.status)" class="text-sm text-n-slate-11">
      {{ t('RAMON.CONTEUDO.MONTANDO_INFO') }}
    </p>
  </aside>
</template>
```

- [ ] **Step 5: Rota** — em `ramon.routes.js`, após a rota `ramon_reuniao`:

```js
  {
    path: frontendURL('accounts/:accountId/ramon/conteudo'),
    name: 'ramon_conteudo',
    component: () => import('./pages/Conteudo.vue'),
    meta: { permissions: ['administrator'], world: 'intranet' },
  },
```

- [ ] **Step 6: Menu** — em `IntranetSidebar.vue`, depois do item `reunioes`:

```js
        {
          key: 'conteudo',
          label: t('RAMON.NAV.CONTEUDO'),
          icon: 'i-lucide-instagram',
          to: accountScopedRoute('ramon_conteudo'),
          names: ['ramon_conteudo'],
          adminOnly: true,
        },
```

- [ ] **Step 7: i18n** — `pt_BR/ramon.json`: `RAMON.NAV.CONTEUDO = "Conteúdo"` e bloco:

```json
"CONTEUDO": {
  "TITLE": "Conteúdo do Instagram",
  "LOAD_ERROR": "Não foi possível carregar as peças",
  "ACAO_ERRO": "Não deu certo — tente de novo",
  "COLUNA": { "PAUTA": "Pauta", "MONTANDO": "Montando", "PRONTAS": "Prontas", "AGENDADAS": "Agendadas", "PUBLICADAS": "Publicadas" },
  "TIPO": { "CARROSSEL": "Carrossel", "ESTATICO": "Estático" },
  "TRAVADA": "Montagem demorando — confira o worker",
  "FALHOU": "Publicação falhou",
  "APROVAR": "Aprovar",
  "REPROVAR": "Reprovar",
  "NOTA_PLACEHOLDER": "Motivo (opcional)",
  "MONTANDO_INFO": "A peça está na fila de montagem. A prévia aparece aqui quando ficar pronta."
}
```

`en/ramon.json`: mesmas chaves em inglês (`"Content"`, `"Instagram content"`, `"Could not load posts"`, `"Something went wrong — try again"`, colunas `"Ideas" "Building" "Ready" "Scheduled" "Published"`, tipos `"Carousel" "Single image"`, `"Build is taking long — check the worker"`, `"Publishing failed"`, `"Approve"`, `"Reject"`, `"Reason (optional)"`, `"Queued for building. The preview shows up here when ready."`).

- [ ] **Step 8: Lint local** — Run: `pnpm eslint app/javascript/dashboard/routes/dashboard/ramon app/javascript/dashboard/api/ramonConteudo.js` · Expected: sem erros.

- [ ] **Step 9: Commit**

```bash
git add app/javascript/dashboard/api/ramonConteudo.js app/javascript/dashboard/routes/dashboard/ramon/pages/Conteudo.vue app/javascript/dashboard/routes/dashboard/ramon/components/conteudo/PecaPainel.vue app/javascript/dashboard/routes/dashboard/ramon/ramon.routes.js app/javascript/dashboard/routes/dashboard/ramon/components/IntranetSidebar.vue app/javascript/dashboard/i18n/locale/pt_BR/ramon.json app/javascript/dashboard/i18n/locale/en/ramon.json app/javascript/dashboard/routes/dashboard/ramon/pages/specs/Conteudo.spec.js
git commit -m "feat(conteudo): tela Conteúdo com kanban e aprovação da pauta"
```

### Task 6: Schema, PR 1, deploy e envs

**Files:**
- Modify: `db/schema.rb` (regenerado)
- Create: `../../docs/2026-10-0X-smoke-conteudo-pr1.md` (em `comercial\docs\`)

- [ ] **Step 1:** Regenerar `db/schema.rb` pelo scratch DB na VPS (§F2.1a). Conferir que o diff só adiciona `ramon_pecas`. Commit `chore(conteudo): schema com ramon_pecas`.
- [ ] **Step 2:** Pedir ao Eduardo `! git -C <worktree> push -u origin feat/conteudo-instagram`; abrir PR para `ramon` (`gh pr create`), descrição no formato do AGENTS.md (parágrafo + How to test).
- [ ] **Step 3:** CI 100% verde → `gh pr merge --squash`. Vermelho → corrigir, nunca mergear.
- [ ] **Step 4:** Deploy (receita do plano mestre: pull da imagem `sha-…` + retag + up web/worker), depois `db:migrate` à mão; conferir label da imagem e login 200.
- [ ] **Step 5 (gate Eduardo):** gerar `RAMON_CONTEUDO_TOKEN` (`openssl rand -hex 24`) e pôr no `chatwoot.env` junto de `RAMON_CONTEUDO_ACCOUNT_ID=2` e `RAMON_NOTION_TOKEN` (mesmo `NOTION_TOKEN` do `.env` do motor); restart web/worker. Script preparado no scratchpad, Eduardo roda via `!` (classificador barra segredo por ssh).
- [ ] **Step 6:** Smoke doc em bloco: menu Conteúdo aparece só pra admin; `curl` de teste cria pauta; aprovar → Notion vira `aprovado` (e, enquanto o PR 2 não sobe, o vigia local monta como hoje).

### Task 7: Rotina cloud manda a pauta pro hub (`motor-marketing`)

**Files:**
- Create: `lib/hub-pecas.mjs`
- Test: `test/hub-pecas.test.mjs`
- Modify: `skills/scan.md` (passo 9)

**Interfaces:**
- Consumes: `POST /public/api/v1/conteudo/pecas` (Task 2); o JSON de peças que o scan já monta pro Notion (`[{slug, gancho, tipo, tese, estilo, ...}]` — é dele que vem `tese`, que não existe no `carousel.json`) e a saída do `notion-pecas.mjs create` (`[{pageId, slug}]`).
- Produces: `enviarRodada({ dataDir, hubUrl, token, pecas = [], notion = [], fetchImpl })` → `[{slug, status}]`; CLI `node lib/hub-pecas.mjs <drafts/AAAA-MM-DD> <pecas.json> [notion-criados.json]` (env `HUB_URL`, `RAMON_CONTEUDO_TOKEN`).

- [ ] **Step 1: Teste (falha)**

```js
import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { enviarRodada } from "../lib/hub-pecas.mjs";

test("enviarRodada manda carrossel e estático, pula vídeo, casa o pageId do Notion", async () => {
  const dataDir = join(mkdtempSync(join(tmpdir(), "rodada-")), "2026-10-01");
  const peca = (slug, arquivo, json) => { mkdirSync(join(dataDir, slug), { recursive: true }); writeFileSync(join(dataDir, slug, arquivo), JSON.stringify(json)); };
  peca("01-bpc", "carousel.json", { estilo: "fluxo", fields: { capa_titulo: "BPC e Bolsa Família" }, legenda: "L" });
  peca("02-ir", "static.json", { fields: { titulo: "Isenção de IR" } });
  const pecas = [{ slug: "01-bpc", gancho: "BPC e Bolsa Família contam juntos?", tese: "bpc" }, { slug: "02-ir", gancho: "Isenção de IR", tese: "isencao-ir" }];
  peca("03-video", "video.json", { roteiro: "x" });
  const enviados = [];
  const fetchImpl = async (url, opts) => { enviados.push({ url, opts }); return { status: 201, json: async () => ({ status: "rascunho" }) }; };

  const r = await enviarRodada({ dataDir, hubUrl: "https://hub", token: "t", pecas, notion: [{ pageId: "np1", slug: "01-bpc" }], fetchImpl });

  assert.deepEqual(r.map((x) => x.slug), ["01-bpc", "02-ir"]);
  const corpo = JSON.parse(enviados[0].opts.body);
  assert.equal(enviados[0].url, "https://hub/public/api/v1/conteudo/pecas");
  assert.equal(enviados[0].opts.headers["X-Conteudo-Token"], "t");
  assert.deepEqual([corpo.tipo, corpo.rodada, corpo.gancho, corpo.estilo, corpo.tese, corpo.notion_page_id], ["carrossel", "2026-10-01", "BPC e Bolsa Família contam juntos?", "fluxo", "bpc", "np1"]);
  assert.equal(JSON.parse(enviados[1].opts.body).tipo, "estatico");
});
```

Run: `node --test test/hub-pecas.test.mjs` · Expected: FAIL (módulo não existe).

- [ ] **Step 2: Implementação**

```js
// Envia as peças de uma rodada (drafts/AAAA-MM-DD) pro hub como pauta (spec ramon-hub
// 2026-10-02-conteudo-instagram §6). Vídeo fica fora da v1. Idempotente no hub (slug).
// Uso: HUB_URL=… RAMON_CONTEUDO_TOKEN=… node lib/hub-pecas.mjs drafts/AAAA-MM-DD <pecas.json> [notion-criados.json]
import { readdirSync, readFileSync, existsSync } from "node:fs";
import { join, basename, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const TIPOS = { "carousel.json": "carrossel", "static.json": "estatico" };

export async function enviarRodada({ dataDir, hubUrl, token, pecas = [], notion = [], fetchImpl = fetch }) {
  const rodada = basename(dataDir);
  const resultado = [];
  for (const slug of readdirSync(dataDir).sort()) {
    const arquivo = Object.keys(TIPOS).find((f) => existsSync(join(dataDir, slug, f)));
    if (!arquivo) continue;
    const conteudo = JSON.parse(readFileSync(join(dataDir, slug, arquivo), "utf8"));
    const meta = pecas.find((p) => p.slug === slug) ?? {};
    const corpo = {
      slug, rodada, tipo: TIPOS[arquivo], conteudo,
      gancho: meta.gancho || conteudo.fields?.capa_titulo || conteudo.fields?.titulo || conteudo.topic || slug,
      estilo: conteudo.estilo, tese: meta.tese,
      notion_page_id: notion.find((n) => n.slug === slug)?.pageId,
    };
    const r = await fetchImpl(`${hubUrl}/public/api/v1/conteudo/pecas`, {
      method: "POST", headers: { "Content-Type": "application/json", "X-Conteudo-Token": token }, body: JSON.stringify(corpo),
    });
    if (r.status >= 300) throw new Error(`hub recusou ${slug}: HTTP ${r.status}`);
    resultado.push({ slug, status: (await r.json()).status });
  }
  return resultado;
}

if (process.argv[1] && fileURLToPath(import.meta.url) === resolve(process.argv[1])) {
  const [, , dataDir, pecasJson, notionJson] = process.argv;
  const { HUB_URL: hubUrl, RAMON_CONTEUDO_TOKEN: token } = process.env;
  if (!dataDir || !pecasJson || !hubUrl || !token) { console.error("uso: HUB_URL=… RAMON_CONTEUDO_TOKEN=… node lib/hub-pecas.mjs drafts/AAAA-MM-DD <pecas.json> [notion-criados.json]"); process.exit(1); }
  const pecas = JSON.parse(readFileSync(pecasJson, "utf8"));
  const notion = notionJson ? JSON.parse(readFileSync(notionJson, "utf8")) : [];
  enviarRodada({ dataDir, hubUrl, token, pecas, notion })
    .then((r) => r.forEach((x) => console.log(`${x.slug}: ${x.status}`)))
    .catch((e) => { console.error("ERRO:", e.message); process.exit(1); });
}
```

Run: `node --test test/hub-pecas.test.mjs` · Expected: PASS.

- [ ] **Step 3: `skills/scan.md` passo 9** — depois do `notion-pecas.mjs create`, trocar a linha por:

```
   na rotina agendada = gravar as peças num JSON temporário, rodar
   `node --env-file=.env lib/notion-pecas.mjs create <dbId> --json <arquivo> > /tmp/notion-criados.json`
   e em seguida **mandar a pauta pro hub** (mesmo `<arquivo>` de peças, que tem `gancho` e `tese`):
   `node lib/hub-pecas.mjs drafts/<data> <arquivo> /tmp/notion-criados.json`
   (envs `HUB_URL=https://chat.ramonantonio.adv.br` e `RAMON_CONTEUDO_TOKEN` vêm do ambiente cloud;
   se faltarem, avise no resumo da rodada — não invente token). Vídeos não vão pro hub (v1).
```

- [ ] **Step 4: Commit + push** (push automático liberado no motor)

```bash
git add lib/hub-pecas.mjs test/hub-pecas.test.mjs skills/scan.md
git commit -m "feat: rodada manda a pauta pro hub (carrossel e estático)"
git push
```

- [ ] **Step 5 (gate Eduardo):** pôr `HUB_URL` e `RAMON_CONTEUDO_TOKEN` nas variáveis do ambiente da rotina `trig_01Ls2UxuVTv2aQQXDCXLhrYQ` (claude.ai/code → rotinas → ambiente). Conferir na rodada seguinte que as pautas aparecem na coluna Pauta.

---

# PR 2 — Montagem na VPS + prévia como post do IG

### Task 8: API do worker — `proxima`, `montada`, `falha`

**Files:**
- Modify: `app/controllers/public/api/v1/conteudo_controller.rb`
- Modify: `config/routes.rb`
- Test: `spec/requests/public/api/v1/conteudo_spec.rb` (acrescentar)

**Interfaces:**
- Consumes: `Peca#transicionar!`, `conta`, `verify_token` (Task 2).
- Produces: `POST conteudo/pecas/proxima` → 200 `{id, slug, rodada, tipo, conteudo, refazer_cards}` (e a peça vira `montando`) ou 204; `PATCH conteudo/pecas/:id/montada` `{imagens: [url]}` → `montado`; `PATCH conteudo/pecas/:id/falha` `{erro}` → `rascunho` (montagem nova) ou `montado` (refação), sempre zerando `refazer_cards`.

- [ ] **Step 1: Testes (falham)** — acrescentar ao describe:

```ruby
  describe 'worker' do
    it 'proxima entrega a aprovada mais antiga e marca montando' do
      create(:peca, account: account, status: 'rascunho')
      a = create(:peca, account: account, status: 'aprovado')
      post '/public/api/v1/conteudo/pecas/proxima', headers: headers
      expect(response.parsed_body).to include('id' => a.id, 'tipo' => 'carrossel', 'refazer_cards' => [])
      expect(a.reload).to have_attributes(status: 'montando')
      expect(a.montagem_iniciada_em).to be_present
    end

    it 'proxima também entrega refação de peça montada' do
      m = create(:peca, account: account, status: 'montado', refazer_cards: [3])
      post '/public/api/v1/conteudo/pecas/proxima', headers: headers
      expect(response.parsed_body['refazer_cards']).to eq [3]
      expect(m.reload.status).to eq 'montando'
    end

    it 'proxima responde 204 sem trabalho e não entrega a mesma peça duas vezes' do
      create(:peca, account: account, status: 'aprovado')
      post '/public/api/v1/conteudo/pecas/proxima', headers: headers
      post '/public/api/v1/conteudo/pecas/proxima', headers: headers
      expect(response).to have_http_status(:no_content)
    end

    it 'montada grava imagens e zera refação' do
      p = create(:peca, account: account, status: 'montando', refazer_cards: [2])
      patch "/public/api/v1/conteudo/pecas/#{p.id}/montada", params: { imagens: %w[u1 u2] }.to_json, headers: headers
      expect(p.reload).to have_attributes(status: 'montado', imagens: %w[u1 u2], refazer_cards: [], erro: nil)
    end

    it 'falha de montagem nova volta pra pauta com o erro' do
      p = create(:peca, account: account, status: 'montando')
      patch "/public/api/v1/conteudo/pecas/#{p.id}/falha", params: { erro: 'Gemini 429' }.to_json, headers: headers
      expect(p.reload).to have_attributes(status: 'rascunho', erro: 'Gemini 429')
    end

    it 'falha de refação volta pra montado e não entra em loop' do
      p = create(:peca, account: account, status: 'montando', refazer_cards: [2], imagens: ['u1'])
      patch "/public/api/v1/conteudo/pecas/#{p.id}/falha", params: { erro: 'x' }.to_json, headers: headers
      expect(p.reload).to have_attributes(status: 'montado', refazer_cards: [], imagens: ['u1'])
      post '/public/api/v1/conteudo/pecas/proxima', headers: headers
      expect(response).to have_http_status(:no_content)
    end
  end
```

- [ ] **Step 2: Ações no controller**

```ruby
  def proxima
    peca = Peca.transaction do
      fila = conta.pecas.where(status: 'aprovado')
                  .or(conta.pecas.where(status: 'montado').where('cardinality(refazer_cards) > 0'))
      fila.order(:id).lock('FOR UPDATE SKIP LOCKED').first&.tap do |p|
        p.update!(status: 'montando', montagem_iniciada_em: Time.current)
      end
    end
    return head :no_content unless peca

    render json: peca.slice(:id, :slug, :rodada, :tipo, :conteudo, :refazer_cards)
  end

  def montada
    peca = conta.pecas.find(params[:id])
    peca.transicionar!(de: 'montando', para: 'montado', imagens: Array(params.require(:imagens)), refazer_cards: [],
                       erro: nil, montagem_iniciada_em: nil)
    head :no_content
  end

  # Refação que falha volta pra `montado` (as imagens antigas seguem válidas) e
  # zera refazer_cards — senão o worker pegaria a mesma peça a cada 30 s.
  def falha
    peca = conta.pecas.find(params[:id])
    destino = peca.refazer_cards.any? ? 'montado' : 'rascunho'
    peca.transicionar!(de: 'montando', para: destino, erro: params[:erro].to_s.truncate(2000), refazer_cards: [],
                       montagem_iniciada_em: nil)
    head :no_content
  end
```

- [ ] **Step 3: Rotas** (junto de `post 'conteudo/pecas'`):

```ruby
        post  'conteudo/pecas/proxima',     to: 'conteudo#proxima'
        patch 'conteudo/pecas/:id/montada', to: 'conteudo#montada'
        patch 'conteudo/pecas/:id/falha',   to: 'conteudo#falha'
```

- [ ] **Step 4: Commit**

```bash
git add app/controllers/public/api/v1/conteudo_controller.rb config/routes.rb spec/requests/public/api/v1/conteudo_spec.rb
git commit -m "feat(conteudo): API do worker de montagem (próxima, montada, falha)"
```

### Task 9: Legenda editável e "refazer imagem do card N"

**Files:**
- Modify: `app/controllers/api/v1/accounts/ramon_conteudo_controller.rb`
- Modify: `config/routes.rb` (member do `ramon_conteudo`)
- Test: `spec/requests/api/v1/accounts/ramon_conteudo_spec.rb` (acrescentar)

**Interfaces:**
- Produces: `PATCH ramon_conteudo/:id/atualizar_legenda` `{legenda}` (só em `montado`/`agendado`, senão 409); `POST ramon_conteudo/:id/refazer` `{cards: [Int 1..5]}` (só em `montado`; peça segue `montado` com `refazer_cards`).

- [ ] **Step 1: Testes (falham)**

```ruby
  it 'edita a legenda de peça pronta' do
    peca.update_columns(status: 'montado')
    patch "#{base}/#{peca.id}/atualizar_legenda", params: { legenda: 'nova' }, headers: admin.create_new_auth_token
    expect(peca.reload.legenda).to eq 'nova'
  end

  it 'não edita legenda de peça publicada' do
    peca.update_columns(status: 'publicado')
    patch "#{base}/#{peca.id}/atualizar_legenda", params: { legenda: 'nova' }, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:conflict)
  end

  it 'pede refação dos cards escolhidos' do
    peca.update_columns(status: 'montado')
    post "#{base}/#{peca.id}/refazer", params: { cards: [2, 9, 'x'] }, headers: admin.create_new_auth_token
    expect(peca.reload).to have_attributes(status: 'montado', refazer_cards: [2])
  end
```

- [ ] **Step 2: Ações**

```ruby
  def atualizar_legenda
    @peca.transicionar!(de: %w[montado agendado], para: @peca.status, legenda: params.require(:legenda))
    render json: detalhe(@peca)
  end

  def refazer
    cards = Array(params[:cards]).map(&:to_i).select { |n| n.between?(1, 5) }.uniq
    return render json: { error: 'Escolha ao menos um card' }, status: :unprocessable_entity if cards.empty?

    @peca.transicionar!(de: 'montado', para: 'montado', refazer_cards: cards)
    render json: detalhe(@peca)
  end
```

(`transicionar!(de: X, para: status atual)` = só a trava + checagem de origem; status não muda, espelho não dispara.)

- [ ] **Step 3: Rotas** — no `member do` do `ramon_conteudo`: `patch :atualizar_legenda` e `post :refazer`.

- [ ] **Step 4: Commit**

```bash
git add app/controllers/api/v1/accounts/ramon_conteudo_controller.rb config/routes.rb spec/requests/api/v1/accounts/ramon_conteudo_spec.rb
git commit -m "feat(conteudo): legenda editável e refazer imagem por card"
```

### Task 10: Prévia como post do Instagram

**Files:**
- Create: `app/javascript/dashboard/routes/dashboard/ramon/components/conteudo/PostPrevia.vue`
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/components/conteudo/PecaPainel.vue`
- Modify: `app/javascript/dashboard/api/ramonConteudo.js`
- Modify: i18n `pt_BR`/`en` `RAMON.CONTEUDO`
- Test: `app/javascript/dashboard/routes/dashboard/ramon/pages/specs/PostPrevia.spec.js`

**Interfaces:**
- Consumes: `detalhe.imagens`, `detalhe.legenda`, Task 9 endpoints.
- Produces: `PostPrevia` props `{ imagens: Array, legenda: String }` (só exibição); API `atualizarLegenda(id, legenda)`, `refazer(id, cards)`.

- [ ] **Step 1: Teste (falha)**

```js
import { mount } from '@vue/test-utils';
import { describe, it, expect, vi } from 'vitest';
import PostPrevia from '../../components/conteudo/PostPrevia.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

const imagens = ['a.jpg', 'b.jpg', 'c.jpg'];

describe('PostPrevia', () => {
  it('navega entre slides com as setas e mostra as bolinhas', async () => {
    const w = mount(PostPrevia, { props: { imagens, legenda: 'x' } });
    expect(w.find('img[data-testid="slide"]').attributes('src')).toBe('a.jpg');
    expect(w.findAll('[data-testid="bolinha"]')).toHaveLength(3);
    await w.find('[data-testid="proximo"]').trigger('click');
    expect(w.find('img[data-testid="slide"]').attributes('src')).toBe('b.jpg');
    expect(w.find('[data-testid="anterior"]').exists()).toBe(true);
  });

  it('estático não tem setas nem bolinhas', () => {
    const w = mount(PostPrevia, { props: { imagens: ['a.jpg'], legenda: 'x' } });
    expect(w.find('[data-testid="proximo"]').exists()).toBe(false);
    expect(w.findAll('[data-testid="bolinha"]')).toHaveLength(0);
  });

  it('corta a legenda em 125 caracteres com "mais" e expande', async () => {
    const w = mount(PostPrevia, { props: { imagens, legenda: 'a'.repeat(200) } });
    expect(w.find('[data-testid="legenda"]').text()).toContain('…');
    await w.find('[data-testid="legenda-mais"]').trigger('click');
    expect(w.find('[data-testid="legenda"]').text()).toContain('a'.repeat(200));
  });
});
```

- [ ] **Step 2: `PostPrevia.vue`**

```vue
<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  imagens: { type: Array, required: true },
  legenda: { type: String, default: '' },
});

const CORTE = 125; // ponytail: corte aproximado do "mais" no feed do app; ajustar se destoar
const { t } = useI18n();
const indice = ref(0);
const expandida = ref(false);

const cortada = computed(() => !expandida.value && props.legenda.length > CORTE);
const textoLegenda = computed(() =>
  cortada.value ? `${props.legenda.slice(0, CORTE)}…` : props.legenda
);

watch(() => props.imagens, () => { indice.value = 0; });
</script>

<template>
  <article class="mx-auto w-full max-w-sm overflow-hidden rounded-xl border border-n-weak bg-white text-black">
    <header class="flex items-center gap-2 p-3">
      <span class="flex size-8 items-center justify-center rounded-full bg-black text-xs text-white">RA</span>
      <span class="text-sm font-semibold">ramonantonioadvogados</span>
    </header>
    <div class="relative aspect-[4/5] bg-n-alpha-2">
      <a :href="imagens[indice]" target="_blank" rel="noopener">
        <img data-testid="slide" :src="imagens[indice]" alt="" class="size-full object-cover" />
      </a>
      <button
        v-if="indice > 0"
        data-testid="anterior"
        type="button"
        class="absolute left-2 top-1/2 flex size-7 -translate-y-1/2 items-center justify-center rounded-full bg-white/80"
        @click="indice -= 1"
      >
        <span class="i-lucide-chevron-left" />
      </button>
      <button
        v-if="indice < imagens.length - 1"
        data-testid="proximo"
        type="button"
        class="absolute right-2 top-1/2 flex size-7 -translate-y-1/2 items-center justify-center rounded-full bg-white/80"
        @click="indice += 1"
      >
        <span class="i-lucide-chevron-right" />
      </button>
    </div>
    <div v-if="imagens.length > 1" class="flex justify-center gap-1 py-2">
      <span
        v-for="(_, i) in imagens"
        :key="i"
        data-testid="bolinha"
        class="size-1.5 rounded-full"
        :class="i === indice ? 'bg-blue-500' : 'bg-gray-300'"
      />
    </div>
    <p class="whitespace-pre-line px-3 pb-3 text-sm" data-testid="legenda">
      <span class="font-semibold">ramonantonioadvogados</span>
      {{ textoLegenda }}
      <button v-if="cortada" data-testid="legenda-mais" type="button" class="text-gray-500" @click="expandida = true">
        {{ t('RAMON.CONTEUDO.MAIS') }}
      </button>
    </p>
  </article>
</template>
```

- [ ] **Step 3: API** — em `ramonConteudo.js`:

```js
  atualizarLegenda(id, legenda) {
    return axios.patch(`${this.url}/${id}/atualizar_legenda`, { legenda });
  }

  refazer(id, cards) {
    return axios.post(`${this.url}/${id}/refazer`, { cards });
  }
```

- [ ] **Step 4: Painel** — em `PecaPainel.vue`: importar `PostPrevia`; `const legenda = ref('')` sincronizada em `carregar` (`legenda.value = data.legenda`); `const refazerCards = ref([])`. Acrescentar antes do bloco `v-else-if` de montando:

```vue
    <template v-if="['montado', 'agendado', 'falhou', 'publicado'].includes(peca.status)">
      <PostPrevia :imagens="peca.imagens" :legenda="legenda" />
      <template v-if="['montado', 'agendado'].includes(peca.status)">
        <textarea v-model="legenda" rows="8" class="rounded border border-n-weak p-2 text-sm" />
        <Button
          sm
          outline
          :label="t('RAMON.CONTEUDO.SALVAR_LEGENDA')"
          :disabled="legenda === peca.legenda"
          @click="agir(() => RamonConteudoAPI.atualizarLegenda(peca.id, legenda))"
        />
      </template>
      <div v-if="peca.status === 'montado'" class="flex flex-wrap items-center gap-2 text-sm">
        <span>{{ t('RAMON.CONTEUDO.REFAZER') }}</span>
        <label v-for="n in peca.imagens.length" :key="n" class="flex items-center gap-1">
          <input v-model="refazerCards" type="checkbox" :value="n" />{{ n }}
        </label>
        <Button
          sm
          slate
          :label="t('RAMON.CONTEUDO.REFAZER_BOTAO')"
          :disabled="!refazerCards.length"
          @click="agir(() => RamonConteudoAPI.refazer(peca.id, refazerCards))"
        />
      </div>
    </template>
```

- [ ] **Step 5: i18n** — `MAIS: "mais"`, `SALVAR_LEGENDA: "Salvar legenda"`, `REFAZER: "Refazer imagem dos cards:"`, `REFAZER_BOTAO: "Refazer"` (en: `"more"`, `"Save caption"`, `"Redo image of cards:"`, `"Redo"`).

- [ ] **Step 6:** `pnpm eslint` nos arquivos tocados · Expected: limpo.

- [ ] **Step 7: Commit**

```bash
git add app/javascript/dashboard/routes/dashboard/ramon/components/conteudo/PostPrevia.vue app/javascript/dashboard/routes/dashboard/ramon/components/conteudo/PecaPainel.vue app/javascript/dashboard/api/ramonConteudo.js app/javascript/dashboard/i18n/locale/pt_BR/ramon.json app/javascript/dashboard/i18n/locale/en/ramon.json app/javascript/dashboard/routes/dashboard/ramon/pages/specs/PostPrevia.spec.js
git commit -m "feat(conteudo): prévia da peça como post do Instagram"
```

### Task 11: Worker de montagem (`motor-marketing`)

**Files:**
- Create: `lib/jpeg.mjs`
- Modify: `lib/publicar-ig.mjs:76` e `:178` (usar `paraJpeg`)
- Create: `lib/worker-hub.mjs`
- Create: `Dockerfile`, `.dockerignore`
- Test: `test/worker-hub.test.mjs`

**Interfaces:**
- Consumes: `POST …/proxima`, `PATCH …/:id/montada|falha` (Task 8); `buildCarousel({draftDir, mock})`, `buildStatic({draftDir, mock})` → `{ files: [png...] }`.
- Produces: `paraJpeg(src, dest)`; `montarUma({ hub, token, dataDir, mediaDir, mediaUrl, mock, fetchImpl })` → `id` montado/falho ou `null` sem trabalho. Imagens publicadas como `${mediaUrl}/${slug}/slide-NN.jpg?v=<epoch>`.

- [ ] **Step 1: `lib/jpeg.mjs`**

```js
import sharp from "sharp";

// A Graph API do Instagram só aceita JPEG.
export const paraJpeg = (src, dest) => sharp(src).jpeg({ quality: 92, mozjpeg: true }).toFile(dest);
```

Em `publicar-ig.mjs`, trocar as duas chamadas `sharp(X).jpeg({ quality: 92, mozjpeg: true }).toFile(Y)` por `paraJpeg(X, Y)` e o `import sharp` por `import { paraJpeg } from "./jpeg.mjs";` (se `sharp` não for usado em mais nada no arquivo).

- [ ] **Step 2: Teste (falha)**

```js
import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { montarUma } from "../lib/worker-hub.mjs";

const fields = {
  capa_categoria: "DIREITO PREVIDENCIÁRIO · INSS", capa_titulo: "Título", capa_sub: "Sub",
  t_kicker: "O QUE É", t_titulo: "T", t_corpo: "C", t_callout: "Co",
  l_kicker: "QUEM TEM DIREITO", l_titulo: "T", l_item1: "a", l_item2: "b", l_item3: "c", l_item4: "d", l_nota: "n",
  d_kicker: "QUANTO RECEBE", d_num: "50%", d_num_label: "l", d_item1: "a", d_item2: "b", d_item3: "c",
  fim_titulo: "Resumo", fim_corpo: "Recap",
};

function hubFalso(peca) {
  const chamadas = [];
  const fetchImpl = async (url, opts = {}) => {
    chamadas.push({ url, metodo: opts.method, corpo: opts.body && JSON.parse(opts.body) });
    if (url.endsWith("/proxima")) return peca ? { status: 200, ok: true, json: async () => peca } : { status: 204, ok: true };
    return { status: 204, ok: true };
  };
  return { chamadas, fetchImpl };
}

const cfg = (fetchImpl) => {
  const raiz = mkdtempSync(join(tmpdir(), "worker-"));
  return { hub: "http://hub", token: "t", dataDir: join(raiz, "data"), mediaDir: join(raiz, "media"),
           mediaUrl: "https://chat/ig-media", mock: true, fetchImpl };
};

test("sem trabalho devolve null", async () => {
  const { fetchImpl } = hubFalso(null);
  assert.equal(await montarUma(cfg(fetchImpl)), null);
});

test("monta carrossel, grava JPEGs e avisa montada", async () => {
  const { chamadas, fetchImpl } = hubFalso({ id: 7, slug: "01-teste", rodada: "2026-10-01", tipo: "carrossel", refazer_cards: [],
    conteudo: { topic: "t", fields, image_briefs: { capa: "a", texto: "b", lista: "c", destaque: "d" } } });
  const c = cfg(fetchImpl);
  assert.equal(await montarUma(c), 7);
  const fim = chamadas.at(-1);
  assert.equal(fim.url, "http://hub/public/api/v1/conteudo/pecas/7/montada");
  assert.equal(fim.corpo.imagens.length, 5);
  assert.match(fim.corpo.imagens[0], /^https:\/\/chat\/ig-media\/01-teste\/slide-01\.jpg\?v=\d+$/);
  assert.ok(existsSync(join(c.mediaDir, "01-teste", "slide-05.jpg")));
});

test("erro no build vira falha com a mensagem", async () => {
  const { chamadas, fetchImpl } = hubFalso({ id: 8, slug: "02-ruim", rodada: "2026-10-01", tipo: "carrossel", refazer_cards: [], conteudo: {} });
  await montarUma(cfg(fetchImpl));
  const fim = chamadas.at(-1);
  assert.equal(fim.url, "http://hub/public/api/v1/conteudo/pecas/8/falha");
  assert.match(fim.corpo.erro, /fields/);
});
```

Run: `node --test test/worker-hub.test.mjs` · Expected: FAIL (módulo não existe).

- [ ] **Step 3: `lib/worker-hub.mjs`**

```js
// Worker de montagem na VPS (spec ramon-hub 2026-10-02-conteudo-instagram §5): pede ao hub
// a próxima peça aprovada, roda o build do motor, converte pra JPEG em /ig-media (servido
// pelo Caddy) e devolve as URLs. Sem Claude: o build é determinístico. Uma peça por vez.
import { mkdirSync, writeFileSync, rmSync } from "node:fs";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { buildCarousel } from "./build.mjs";
import { buildStatic } from "./build-static.mjs";
import { paraJpeg } from "./jpeg.mjs";

const nn = (n) => String(n).padStart(2, "0");

export async function montarUma({ hub, token, dataDir, mediaDir, mediaUrl, mock = false, fetchImpl = fetch }) {
  const headers = { "X-Conteudo-Token": token, "Content-Type": "application/json" };
  const api = (caminho, metodo, corpo) =>
    fetchImpl(`${hub}/public/api/v1/conteudo/pecas/${caminho}`, { method: metodo, headers, body: corpo && JSON.stringify(corpo) });

  const r = await api("proxima", "POST");
  if (r.status === 204) return null;
  if (!r.ok) throw new Error(`proxima: HTTP ${r.status}`);
  const peca = await r.json();

  try {
    // Diretório persistente por peça: refação reaproveita as imagens dos outros cards.
    const draftDir = join(dataDir, "pecas", peca.rodada, peca.slug);
    const imgDir = join(draftDir, "img");
    mkdirSync(draftDir, { recursive: true });
    writeFileSync(join(draftDir, peca.tipo === "carrossel" ? "carousel.json" : "static.json"), JSON.stringify(peca.conteudo));
    // `continua` é uma panorâmica só: refazer qualquer card regenera a imagem inteira.
    if (peca.refazer_cards.length && peca.conteudo.estilo === "continua") rmSync(imgDir, { recursive: true, force: true });
    for (const n of peca.refazer_cards) rmSync(join(imgDir, `slide-${nn(n)}.png`), { force: true });

    const build = peca.tipo === "carrossel" ? buildCarousel : buildStatic;
    const { files } = await build({ draftDir, mock });

    const destDir = join(mediaDir, peca.slug);
    mkdirSync(destDir, { recursive: true });
    const versao = Date.now(); // fura cache do navegador/Meta depois de uma refação
    const imagens = [];
    for (const [i, png] of files.entries()) {
      const nome = `slide-${nn(i + 1)}.jpg`;
      await paraJpeg(png, join(destDir, nome));
      imagens.push(`${mediaUrl}/${peca.slug}/${nome}?v=${versao}`);
    }
    await api(`${peca.id}/montada`, "PATCH", { imagens });
  } catch (e) {
    await api(`${peca.id}/falha`, "PATCH", { erro: e.message });
  }
  return peca.id;
}

if (process.argv[1] && fileURLToPath(import.meta.url) === resolve(process.argv[1])) {
  const cfg = {
    hub: process.env.HUB_URL, token: process.env.RAMON_CONTEUDO_TOKEN,
    dataDir: process.env.DATA_DIR ?? "/data", mediaDir: process.env.MEDIA_DIR ?? "/ig-media",
    mediaUrl: process.env.MEDIA_URL ?? "https://chat.ramonantonio.adv.br/ig-media",
  };
  if (!cfg.hub || !cfg.token) { console.error("HUB_URL e RAMON_CONTEUDO_TOKEN são obrigatórios"); process.exit(1); }
  console.log(`worker de conteúdo no ar → ${cfg.hub}`);
  for (;;) {
    try {
      let id;
      while ((id = await montarUma(cfg))) console.log(new Date().toISOString(), `peça ${id} processada`);
    } catch (e) {
      console.error(new Date().toISOString(), e.message);
    }
    await new Promise((r) => setTimeout(r, 30_000));
  }
}
```

Run: `node --test test/worker-hub.test.mjs` · Expected: PASS (3 testes; usa Chromium local do Playwright em mock). Rodar também `node --test` inteiro · Expected: tudo verde (publicar-ig não tem teste; conferir com `node lib/publicar-ig.mjs` sem args que o import resolve).

- [ ] **Step 4: `Dockerfile` e `.dockerignore`**

```dockerfile
# Worker de montagem de peças do Instagram (VPS). Versão casada com o playwright do package-lock.
FROM mcr.microsoft.com/playwright:v1.61.1-noble
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev
COPY . .
CMD ["node", "lib/worker-hub.mjs"]
```

```
node_modules
drafts
output
video
logs
intel
.env
*.mp4
```

- [ ] **Step 5: Commit + push**

```bash
git add lib/jpeg.mjs lib/publicar-ig.mjs lib/worker-hub.mjs test/worker-hub.test.mjs Dockerfile .dockerignore
git commit -m "feat: worker de montagem que atende o hub (container Playwright)"
git push
```

### Task 12: PR 2 no ar + worker na VPS + vigia desligado

- [ ] **Step 1:** PR 2 do hub (Tasks 8–10): push pelo Eduardo, `gh pr create`, CI verde, merge, deploy (sem migração).
- [ ] **Step 2 (gate Eduardo, via `!`):** subir o código do worker: do PC, `git -C motor-marketing archive --format=tar main | ssh root@185.194.216.67 "rm -rf /opt/conteudo-worker && mkdir -p /opt/conteudo-worker && tar -x -C /opt/conteudo-worker"`.
- [ ] **Step 3 (gate Eduardo):** acrescentar ao `/opt/intranet-ramon/docker-compose.override.yml`:

```yaml
  # Worker de montagem das peças do Instagram (spec 2026-10-02). Fonte em
  # /opt/conteudo-worker (git archive do motor-marketing main). Fala só com o hub.
  conteudo-worker:
    build: /opt/conteudo-worker
    restart: unless-stopped
    mem_limit: 1536m
    cpus: 1
    env_file: /opt/conteudo-worker.env   # GOOGLE_API_KEY, RAMON_CONTEUDO_TOKEN
    environment:
      HUB_URL: http://chatwoot-web:3000
    volumes:
      - ./ig-media:/ig-media
      - conteudo_data:/data
```

e `conteudo_data:` na seção `volumes:` do override (criar a seção se não existir). `/opt/conteudo-worker.env` (0600) preparado por script no scratchpad sem imprimir segredo. `docker compose up -d --build conteudo-worker`; `docker compose logs --tail 20 conteudo-worker` deve mostrar "worker de conteúdo no ar".
- [ ] **Step 4 (gate Eduardo):** desligar o vigia local — `! schtasks /change /tn "Motor marketing - montar aprovados" /disable` — e anotar no `CLAUDE.md` do motor (seção Notion) que a montagem agora é no hub.
- [ ] **Step 5:** Smoke doc em bloco: aprovar uma pauta → em ≤ 2 min vai pra Prontas com prévia; refazer card 2 → só a imagem 2 muda; legenda editada aparece na prévia; `docker stats` mostra o worker abaixo de 1,5 GB.

---

# PR 3 — Agenda e publicação

### Task 13: Grade de horários

**Files:**
- Create: `app/services/ramon/grade_conteudo.rb`
- Test: `spec/services/ramon/grade_conteudo_spec.rb`

**Interfaces:**
- Produces: `Ramon::GradeConteudo.proximo_horario(account, agora = Time.current)` → `ActiveSupport::TimeWithZone` (America/Sao_Paulo) do próximo slot livre.

- [ ] **Step 1: Teste (falha)**

```ruby
require 'rails_helper'

RSpec.describe Ramon::GradeConteudo do
  let(:account) { create(:account) }
  let(:fuso) { Time.find_zone('America/Sao_Paulo') }

  it 'quarta 10h sugere quarta 12h' do
    expect(described_class.proximo_horario(account, fuso.local(2026, 10, 7, 10))).to eq fuso.local(2026, 10, 7, 12)
  end

  it 'pula slot ocupado' do
    create(:peca, account: account, status: 'agendado', agendado_para: fuso.local(2026, 10, 7, 12))
    expect(described_class.proximo_horario(account, fuso.local(2026, 10, 7, 10))).to eq fuso.local(2026, 10, 8, 12)
  end

  it 'sexta sugere a terça seguinte' do
    expect(described_class.proximo_horario(account, fuso.local(2026, 10, 9, 9))).to eq fuso.local(2026, 10, 13, 12)
  end

  it 'exatamente 12h já não serve' do
    expect(described_class.proximo_horario(account, fuso.local(2026, 10, 7, 12))).to eq fuso.local(2026, 10, 8, 12)
  end
end
```

- [ ] **Step 2: Implementação**

```ruby
# Grade de sugestão de horário das peças: ter/qua/qui 12h (BRT) — o time inteiro
# reposta na hora do almoço (decisão do Eduardo 02/10/2026).
module Ramon::GradeConteudo
  # ponytail: grade fixa no código; trocar aqui se as métricas pedirem
  SLOTS = { 2 => [12, 0], 3 => [12, 0], 4 => [12, 0] }.freeze
  FUSO = 'America/Sao_Paulo'.freeze
  OCUPA = %w[agendado publicando publicado].freeze

  module_function

  def proximo_horario(account, agora = Time.current)
    zona = Time.find_zone(FUSO)
    ocupados = account.pecas.where(status: OCUPA).where(agendado_para: agora..).pluck(:agendado_para).to_set(&:to_i)
    hoje = agora.in_time_zone(zona).to_date
    (0..21).each do |d|
      dia = hoje + d
      slot = SLOTS[dia.wday]
      next unless slot

      horario = zona.local(dia.year, dia.month, dia.day, *slot)
      return horario if horario > agora && ocupados.exclude?(horario.to_i)
    end
    nil
  end
end
```

- [ ] **Step 3: Commit**

```bash
git add app/services/ramon/grade_conteudo.rb spec/services/ramon/grade_conteudo_spec.rb
git commit -m "feat(conteudo): grade ter/qua/qui 12h com próximo slot livre"
```

### Task 14: Publicador do Instagram (só feed + colaborador)

**Files:**
- Create: `app/services/ramon/instagram_publisher.rb`
- Modify: `config/installation_config.yml` (após `INSTAGRAM_API_VERSION`), `app/controllers/super_admin/app_configs_controller.rb:48`
- Test: `spec/services/ramon/instagram_publisher_spec.rb`

**Interfaces:**
- Produces: `Ramon::InstagramPublisher.new(peca, token:, espera: 5)`; `#publicar` → `ig_media_id` (String) — **retorna assim que o `media_publish` responde**; `#permalink(media_id)` → String ou nil (nunca levanta); `Ramon::InstagramPublisher::Erro`. Config `RAMON_IG_PUBLISH_TOKEN` (secret) no super admin → Instagram.

- [ ] **Step 1: Teste (falha)**

```ruby
require 'rails_helper'

RSpec.describe Ramon::InstagramPublisher do
  let(:g) { 'https://graph.instagram.com/v26.0' }
  let(:peca) do
    build(:peca, tipo: 'carrossel', imagens: %w[https://m/1.jpg https://m/2.jpg],
                 legenda: "Texto\n\nCom Brenda Antunes, nossa advogada")
  end
  let(:pub) { described_class.new(peca, token: 'tk', espera: 0) }

  it 'publica carrossel: filhos, contêiner com colaborador, espera FINISHED e media_publish' do
    filhos = stub_request(:post, "#{g}/me/media").with(body: hash_including('is_carousel_item' => 'true'))
                                                 .to_return({ body: { id: 'c1' }.to_json }, { body: { id: 'c2' }.to_json })
    pai = stub_request(:post, "#{g}/me/media")
          .with(body: hash_including('media_type' => 'CAROUSEL', 'children' => 'c1,c2', 'collaborators' => '["brendantunes"]'))
          .to_return(body: { id: 'p1' }.to_json)
    stub_request(:get, "#{g}/p1").with(query: hash_including('fields' => 'status_code'))
                                 .to_return({ body: { status_code: 'IN_PROGRESS' }.to_json }, { body: { status_code: 'FINISHED' }.to_json })
    publish = stub_request(:post, "#{g}/me/media_publish").with(body: hash_including('creation_id' => 'p1'))
                                                          .to_return(body: { id: 'm9' }.to_json)
    expect(pub.publicar).to eq 'm9'
    expect([filhos, pai, publish]).to all(have_been_requested.at_least_once)
    expect(a_request(:post, "#{g}/me/media").with(body: hash_including('media_type' => 'STORIES'))).not_to have_been_made
  end

  it 'estático usa image_url no contêiner único' do
    peca.assign_attributes(tipo: 'estatico', imagens: ['https://m/1.jpg'], legenda: 'L')
    stub_request(:post, "#{g}/me/media").with(body: hash_including('image_url' => 'https://m/1.jpg', 'caption' => 'L'))
                                        .to_return(body: { id: 'p1' }.to_json)
    stub_request(:get, "#{g}/p1").with(query: hash_including('fields' => 'status_code')).to_return(body: { status_code: 'FINISHED' }.to_json)
    stub_request(:post, "#{g}/me/media_publish").to_return(body: { id: 'm1' }.to_json)
    expect(pub.publicar).to eq 'm1'
  end

  it 'erro da Meta vira Erro com a mensagem' do
    stub_request(:post, "#{g}/me/media").to_return(status: 400, body: { error: { message: 'Invalid image' } }.to_json)
    expect { pub.publicar }.to raise_error(described_class::Erro, /Invalid image/)
  end

  it 'sem token não chama a Meta' do
    expect { described_class.new(peca, token: nil).publicar }.to raise_error(described_class::Erro, /token/)
  end

  it 'permalink nunca levanta' do
    stub_request(:get, "#{g}/m9").with(query: hash_including('fields' => 'permalink')).to_return(status: 500)
    expect(pub.permalink('m9')).to be_nil
  end
end
```

- [ ] **Step 2: Serviço**

```ruby
# Publica uma peça (carrossel/estático) no feed do @ramonantonioadvogados pela Graph API
# do Instagram — paridade com motor-marketing/lib/publicar-ig.mjs, SEM stories (decisão
# do Eduardo 02/10: arte 4:5 quebra no story). Colaborador: crédito na legenda → @.
class Ramon::InstagramPublisher
  GRAPH = 'https://graph.instagram.com/v26.0'.freeze
  TENTATIVAS = 60 # × espera (5 s) ≈ 5 min

  # Espelho de motor-marketing packs/marca-ramon-antonio/brand.json → identidades (22/09).
  COLABORADORES = {
    'Dr. Ramon Antonio' => 'ramon_antonio__', 'Eduardo Schlata' => 'eduardoschlata', 'Brenda Antunes' => 'brendantunes',
    'Rafaela Pinter' => 'rafaelabpf', 'Tamires de Farias' => 'tamidefarias', 'Crisleine Antonio' => 'crisleine_antonio'
  }.freeze

  class Erro < StandardError; end

  def initialize(peca, token: GlobalConfigService.load('RAMON_IG_PUBLISH_TOKEN', nil), espera: 5)
    @peca = peca
    @token = token
    @espera = espera
  end

  def publicar
    raise Erro, 'Token do Instagram ausente (super admin → Instagram → RAMON_IG_PUBLISH_TOKEN)' if @token.blank?

    container = @peca.tipo == 'carrossel' ? carrossel : post('me/media', base.merge(image_url: @peca.imagens.first))['id']
    aguardar(container)
    post('me/media_publish', creation_id: container)['id']
  end

  def permalink(media_id)
    get(media_id, fields: 'permalink')['permalink']
  rescue StandardError
    nil
  end

  private

  def carrossel
    filhos = @peca.imagens.map { |url| post('me/media', image_url: url, is_carousel_item: true)['id'] }
    post('me/media', base.merge(media_type: 'CAROUSEL', children: filhos.join(',')))['id']
  end

  def base
    achados = COLABORADORES.select { |nome, _| @peca.legenda.to_s.include?(nome) }.values.first(3)
    { caption: @peca.legenda }.merge(achados.any? ? { collaborators: achados.to_json } : {})
  end

  def aguardar(id)
    TENTATIVAS.times do
      codigo = get(id, fields: 'status_code')['status_code']
      return if codigo == 'FINISHED'
      raise Erro, "Contêiner #{id}: #{codigo}" if %w[ERROR EXPIRED].include?(codigo)

      sleep @espera
    end
    raise Erro, "Contêiner #{id} não ficou pronto em ~5 min"
  end

  def post(caminho, params)
    responder Net::HTTP.post_form(URI("#{GRAPH}/#{caminho}"), params.merge(access_token: @token))
  end

  def get(caminho, params)
    uri = URI("#{GRAPH}/#{caminho}")
    uri.query = URI.encode_www_form(params.merge(access_token: @token))
    responder Net::HTTP.get_response(uri)
  end

  def responder(res)
    corpo = JSON.parse(res.body.presence || '{}')
    raise Erro, corpo.dig('error', 'message') || "HTTP #{res.code}" unless res.is_a?(Net::HTTPSuccess)

    corpo
  end
end
```

- [ ] **Step 3: Config no super admin** — `config/installation_config.yml`, após o item `INSTAGRAM_API_VERSION`:

```yaml
- name: RAMON_IG_PUBLISH_TOKEN
  display_title: 'Token de publicação do Instagram (conteúdo)'
  description: 'Token de longa duração do @ramonantonioadvogados (painel Meta → produto Instagram → Gerar token). Renovado sozinho toda semana.'
  locked: false
  type: secret
```

e em `app_configs_controller.rb:48` acrescentar `RAMON_IG_PUBLISH_TOKEN` à lista `'instagram'`.

- [ ] **Step 4: Commit**

```bash
git add app/services/ramon/instagram_publisher.rb config/installation_config.yml app/controllers/super_admin/app_configs_controller.rb spec/services/ramon/instagram_publisher_spec.rb
git commit -m "feat(conteudo): publicador do feed do Instagram com colaborador"
```

### Task 15: Cron de publicação + acervo no Drive

**Files:**
- Create: `app/jobs/ramon/publicar_pecas_job.rb`
- Create: `app/jobs/ramon/conteudo_drive_job.rb`
- Modify: `config/schedule.yml` (após `ramon_portal_sync_job`)
- Test: `spec/jobs/ramon/publicar_pecas_job_spec.rb`, `spec/jobs/ramon/conteudo_drive_job_spec.rb`

**Interfaces:**
- Consumes: `Ramon::InstagramPublisher#publicar/#permalink`, `Peca#transicionar!`, `Ramon::NtfyPushJob.perform_later(nil, title:, body:)`, `Ramon::DriveClient`.
- Produces: `Ramon::PublicarPecasJob.perform_now` (cron 1 min; também chamado por "Publicar agora"); `Ramon::ConteudoDriveJob.perform_later(peca_id)` — sobe os JPEGs publicados + `legenda.txt` em `RAMON_DRIVE_POSTS_ID/<Carrossel|Estático>/<rodada — gancho>`.

> **Desvio consciente da spec §4.8:** o acervo sobe **depois de publicar**, não em `montado` — assim o Drive guarda exatamente o que foi ao ar e refações não duplicam arquivo. Atualizar a spec no mesmo commit.

- [ ] **Step 1: Testes (falham)**

```ruby
require 'rails_helper'

RSpec.describe Ramon::PublicarPecasJob do
  let(:peca) { create(:peca, status: 'agendado', agendado_para: 1.minute.ago, imagens: ['u1']) }
  let(:publisher) { instance_double(Ramon::InstagramPublisher, publicar: 'm9', permalink: 'https://ig/p/x') }

  before { allow(Ramon::InstagramPublisher).to receive(:new).and_return(publisher) }

  it 'publica a peça vencida e grava id e link' do
    peca
    expect { described_class.perform_now }.to have_enqueued_job(Ramon::ConteudoDriveJob).with(peca.id)
    expect(peca.reload).to have_attributes(status: 'publicado', ig_media_id: 'm9', permalink: 'https://ig/p/x', erro: nil)
  end

  it 'não mexe em peça agendada pro futuro' do
    peca.update_columns(agendado_para: 1.hour.from_now)
    described_class.perform_now
    expect(publisher).not_to have_received(:publicar)
  end

  it 'erro da Meta vira falhou e avisa no celular' do
    allow(publisher).to receive(:publicar).and_raise(Ramon::InstagramPublisher::Erro, 'Invalid image')
    peca
    expect { described_class.perform_now }.to have_enqueued_job(Ramon::NtfyPushJob)
    expect(peca.reload).to have_attributes(status: 'falhou', erro: 'Invalid image')
  end

  it 'nunca republica peça que já tem ig_media_id' do
    peca.update_columns(ig_media_id: 'm1')
    described_class.perform_now
    expect(publisher).not_to have_received(:publicar)
    expect(peca.reload.status).to eq 'publicado'
  end

  it 'permalink falhando não derruba: fica publicado com o id' do
    allow(publisher).to receive(:permalink).and_return(nil)
    peca
    described_class.perform_now
    expect(peca.reload).to have_attributes(status: 'publicado', ig_media_id: 'm9', permalink: nil)
  end

  it 'publicando há mais de 15 min vira falhou com aviso de conferir' do
    travada = create(:peca, status: 'publicando', publicacao_iniciada_em: 20.minutes.ago)
    described_class.perform_now
    expect(travada.reload).to have_attributes(status: 'falhou')
    expect(travada.erro).to include('conferir no Instagram')
  end
end
```

```ruby
require 'rails_helper'

RSpec.describe Ramon::ConteudoDriveJob do
  let(:peca) { create(:peca, status: 'publicado', imagens: ['https://m/01/slide-01.jpg?v=1'], legenda: 'Leg') }

  it 'não faz nada sem Drive configurado' do
    with_modified_env(RAMON_DRIVE_POSTS_ID: nil) { described_class.perform_now(peca.id) }
    expect(peca.reload.drive_pasta_id).to be_nil
  end

  it 'sobe imagens e legenda na pasta da peça' do
    allow(Ramon::DriveClient).to receive(:configured?).and_return(true)
    allow(Ramon::DriveClient).to receive(:ensure_folder).and_return('tipo1', 'pasta1')
    allow(Ramon::DriveClient).to receive(:upload).and_return('f1')
    stub_request(:get, 'https://m/01/slide-01.jpg?v=1').to_return(body: 'jpg')
    with_modified_env(RAMON_DRIVE_POSTS_ID: 'raiz') { described_class.perform_now(peca.id) }
    expect(Ramon::DriveClient).to have_received(:ensure_folder).with('Carrossel', 'raiz')
    expect(Ramon::DriveClient).to have_received(:upload).with(hash_including(name: 'slide-01.jpg', parent_id: 'pasta1'))
    expect(Ramon::DriveClient).to have_received(:upload).with(hash_including(name: 'legenda.txt'))
    expect(peca.reload.drive_pasta_id).to eq 'pasta1'
  end
end
```

- [ ] **Step 2: `PublicarPecasJob`**

```ruby
# Cron (1 min): publica no Instagram as peças agendadas que venceram. Sem retry
# automático — falha vira `falhou` + push, e o Eduardo decide tentar de novo.
class Ramon::PublicarPecasJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    marcar_interrompidas
    Peca.where(status: 'agendado').where(agendado_para: ..Time.current).find_each { |peca| publicar(peca) }
  end

  private

  def publicar(peca)
    peca.transicionar!(de: 'agendado', para: 'publicando', publicacao_iniciada_em: Time.current)
    # ig_media_id gravado = já está no ar; nunca mandar de novo pra Meta.
    return peca.update!(status: 'publicado') if peca.ig_media_id.present?

    publisher = Ramon::InstagramPublisher.new(peca)
    peca.update!(ig_media_id: publisher.publicar) # grava no instante do publish
    peca.update!(status: 'publicado', permalink: publisher.permalink(peca.ig_media_id), erro: nil)
    Ramon::ConteudoDriveJob.perform_later(peca.id)
    avisar("Publicado no Instagram: #{peca.gancho}", peca.permalink || 'link indisponível — ver no app')
  rescue Peca::TransicaoInvalida
    nil # outro processo já pegou esta peça
  rescue StandardError => e
    peca.update!(status: 'falhou', erro: e.message)
    avisar("Publicação falhou: #{peca.gancho}", e.message)
  end

  def marcar_interrompidas
    Peca.where(status: 'publicando').where(publicacao_iniciada_em: ...Peca::TRAVA.ago).find_each do |peca|
      peca.update!(status: 'falhou', erro: 'Publicação interrompida no meio — conferir no Instagram antes de tentar de novo.')
    end
  end

  def avisar(titulo, corpo)
    Ramon::NtfyPushJob.perform_later(nil, title: titulo, body: corpo)
  end
end
```

- [ ] **Step 3: `ConteudoDriveJob`**

```ruby
# Acervo: depois de publicada, a peça (JPEGs + legenda) vai pra
# Posts Instagram/<Carrossel|Estático>/<rodada — gancho> no Drive. Best-effort.
class Ramon::ConteudoDriveJob < ApplicationJob
  queue_as :low

  def perform(peca_id)
    raiz = ENV.fetch('RAMON_DRIVE_POSTS_ID', nil)
    return if raiz.blank? || !Ramon::DriveClient.configured?

    peca = Peca.find(peca_id)
    tipo = Ramon::DriveClient.ensure_folder(peca.tipo == 'carrossel' ? 'Carrossel' : 'Estático', raiz)
    pasta = Ramon::DriveClient.ensure_folder("#{peca.rodada.iso8601} — #{peca.gancho.delete('/\\:*?"<>|')}", tipo)
    peca.imagens.each do |url|
      nome = File.basename(URI(url).path)
      Ramon::DriveClient.upload(name: nome, io: StringIO.new(Net::HTTP.get(URI(url))), content_type: 'image/jpeg', parent_id: pasta)
    end
    Ramon::DriveClient.upload(name: 'legenda.txt', io: StringIO.new(peca.legenda.to_s), content_type: 'text/plain', parent_id: pasta)
    peca.update!(drive_pasta_id: pasta)
  end
end
```

- [ ] **Step 4: Cron** — `config/schedule.yml`:

```yaml
# Conteúdo do Instagram: publica as peças agendadas que venceram (spec 2026-10-02).
ramon_publicar_pecas_job:
  cron: '* * * * *'
  class: 'Ramon::PublicarPecasJob'
  queue: scheduled_jobs
```

- [ ] **Step 5: Spec** — em `docs/superpowers/specs/2026-10-02-conteudo-instagram-design.md` §4.8, trocar "Em `montado`:" por "Depois de `publicado`:" e remover a frase "(re-upload só em refação)".

- [ ] **Step 6: Commit**

```bash
git add app/jobs/ramon/publicar_pecas_job.rb app/jobs/ramon/conteudo_drive_job.rb config/schedule.yml spec/jobs/ramon/publicar_pecas_job_spec.rb spec/jobs/ramon/conteudo_drive_job_spec.rb docs/superpowers/specs/2026-10-02-conteudo-instagram-design.md
git commit -m "feat(conteudo): cron de publicação sem post em dobro e acervo no Drive"
```

### Task 16: Ações de agenda na API da tela

**Files:**
- Modify: `app/controllers/api/v1/accounts/ramon_conteudo_controller.rb`
- Modify: `config/routes.rb`
- Test: `spec/requests/api/v1/accounts/ramon_conteudo_spec.rb` (acrescentar)

**Interfaces:**
- Consumes: `Ramon::GradeConteudo.proximo_horario`, `Ramon::PublicarPecasJob`.
- Produces: `POST …/:id/agendar` `{agendado_para: ISO8601}` (`montado`→`agendado`; passado → 422); `POST …/:id/publicar_agora` (`montado|agendado`→`agendado` agora + enfileira job); `POST …/:id/cancelar_agendamento` (`agendado`→`montado`); `POST …/:id/tentar_de_novo` (`falhou`→`agendado` agora; com `ig_media_id` → 409). `detalhe` ganha `sugestao_horario` (ISO8601) quando `montado`.

- [ ] **Step 1: Testes (falham)**

```ruby
  describe 'agenda' do
    before { peca.update_columns(status: 'montado', imagens: ['u1']) }

    it 'detalhe traz a sugestão da grade' do
      get "#{base}/#{peca.id}", headers: admin.create_new_auth_token
      expect(response.parsed_body['sugestao_horario']).to be_present
    end

    it 'agenda pro futuro' do
      quando = 2.days.from_now.change(usec: 0)
      post "#{base}/#{peca.id}/agendar", params: { agendado_para: quando.iso8601 }, headers: admin.create_new_auth_token
      expect(peca.reload).to have_attributes(status: 'agendado', agendado_para: quando)
    end

    it 'recusa horário no passado' do
      post "#{base}/#{peca.id}/agendar", params: { agendado_para: 1.hour.ago.iso8601 }, headers: admin.create_new_auth_token
      expect(response).to have_http_status(:unprocessable_entity)
      expect(peca.reload.status).to eq 'montado'
    end

    it 'publicar agora agenda pra já e dispara o job' do
      expect { post "#{base}/#{peca.id}/publicar_agora", headers: admin.create_new_auth_token }
        .to have_enqueued_job(Ramon::PublicarPecasJob)
      expect(peca.reload.status).to eq 'agendado'
    end

    it 'cancela agendamento' do
      peca.update_columns(status: 'agendado', agendado_para: 1.day.from_now)
      post "#{base}/#{peca.id}/cancelar_agendamento", headers: admin.create_new_auth_token
      expect(peca.reload).to have_attributes(status: 'montado', agendado_para: nil)
    end

    it 'tentar de novo recusa peça que já tem id na Meta' do
      peca.update_columns(status: 'falhou', ig_media_id: 'm1')
      post "#{base}/#{peca.id}/tentar_de_novo", headers: admin.create_new_auth_token
      expect(response).to have_http_status(:conflict)
    end
  end
```

- [ ] **Step 2: Ações**

```ruby
  def agendar
    quando = Time.zone.parse(params.require(:agendado_para).to_s)
    return render json: { error: 'Escolha um horário no futuro' }, status: :unprocessable_entity if quando.nil? || quando <= Time.current

    @peca.transicionar!(de: 'montado', para: 'agendado', agendado_para: quando)
    render json: detalhe(@peca)
  end

  def publicar_agora
    @peca.transicionar!(de: %w[montado agendado], para: 'agendado', agendado_para: Time.current)
    Ramon::PublicarPecasJob.perform_later
    render json: detalhe(@peca)
  end

  def cancelar_agendamento
    @peca.transicionar!(de: 'agendado', para: 'montado', agendado_para: nil)
    render json: detalhe(@peca)
  end

  def tentar_de_novo
    if @peca.ig_media_id.present?
      return render json: { error: 'Esta peça já foi ao ar — confira no Instagram.' }, status: :conflict
    end

    @peca.transicionar!(de: 'falhou', para: 'agendado', agendado_para: Time.current, erro: nil)
    Ramon::PublicarPecasJob.perform_later
    render json: detalhe(@peca)
  end
```

e no `detalhe`:

```ruby
  def detalhe(peca)
    linha(peca).merge(conteudo: peca.conteudo, legenda: peca.legenda, imagens: peca.imagens,
                      nota_reprovacao: peca.nota_reprovacao,
                      sugestao_horario: peca.status == 'montado' ? Ramon::GradeConteudo.proximo_horario(peca.account)&.iso8601 : nil)
  end
```

- [ ] **Step 3: Rotas** — no `member do`: `post :agendar`, `post :publicar_agora`, `post :cancelar_agendamento`, `post :tentar_de_novo`.

- [ ] **Step 4: Commit**

```bash
git add app/controllers/api/v1/accounts/ramon_conteudo_controller.rb config/routes.rb spec/requests/api/v1/accounts/ramon_conteudo_spec.rb
git commit -m "feat(conteudo): agendar, publicar agora, cancelar e tentar de novo"
```

### Task 17: Botões de agenda na tela

**Files:**
- Modify: `app/javascript/dashboard/api/ramonConteudo.js`
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/components/conteudo/PecaPainel.vue`
- Modify: i18n `pt_BR`/`en`
- Test: `app/javascript/dashboard/routes/dashboard/ramon/pages/specs/PecaPainel.spec.js`

**Interfaces:**
- Consumes: endpoints da Task 16, `detalhe.sugestao_horario`.
- Produces: API `agendar(id, quando)`, `publicarAgora(id)`, `cancelarAgendamento(id)`, `tentarDeNovo(id)`; helper `paraInputLocal(iso) → 'YYYY-MM-DDTHH:mm'` (fuso do navegador) em `app/javascript/dashboard/routes/dashboard/ramon/helpers/dataLocal.js`.

- [ ] **Step 1: Helper + teste (falha)**

`helpers/dataLocal.js`:

```js
// <input type="datetime-local"> quer 'YYYY-MM-DDTHH:mm' no fuso do navegador.
export const paraInputLocal = iso => {
  if (!iso) return '';
  const d = new Date(iso);
  const p = n => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}`;
};
```

`pages/specs/PecaPainel.spec.js`:

```js
import { flushPromises, mount } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import PecaPainel from '../../components/conteudo/PecaPainel.vue';
import RamonConteudoAPI from 'dashboard/api/ramonConteudo';

vi.mock('dashboard/api/ramonConteudo', () => ({
  default: { show: vi.fn(), agendar: vi.fn(), publicarAgora: vi.fn() },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

const montada = { id: 3, status: 'montado', gancho: 'G', legenda: 'L', imagens: ['a.jpg'], conteudo: {},
  sugestao_horario: '2026-10-07T15:00:00Z' };

describe('PecaPainel agenda', () => {
  beforeEach(() => vi.clearAllMocks());

  it('pré-preenche a sugestão e agenda com o horário do campo', async () => {
    RamonConteudoAPI.show.mockResolvedValue({ data: montada });
    RamonConteudoAPI.agendar.mockResolvedValue({ data: { ...montada, status: 'agendado' } });
    const w = mount(PecaPainel, { props: { pecaId: 3 } });
    await flushPromises();
    const campo = w.find('[data-testid="agendar-quando"]');
    expect(campo.element.value).not.toBe('');
    await w.find('[data-testid="agendar"]').trigger('click');
    expect(RamonConteudoAPI.agendar).toHaveBeenCalledWith(3, new Date(campo.element.value).toISOString());
  });
});
```

- [ ] **Step 2: API**

```js
  agendar(id, agendadoPara) {
    return axios.post(`${this.url}/${id}/agendar`, { agendado_para: agendadoPara });
  }

  publicarAgora(id) {
    return axios.post(`${this.url}/${id}/publicar_agora`);
  }

  cancelarAgendamento(id) {
    return axios.post(`${this.url}/${id}/cancelar_agendamento`);
  }

  tentarDeNovo(id) {
    return axios.post(`${this.url}/${id}/tentar_de_novo`);
  }
```

- [ ] **Step 3: Painel** — importar `paraInputLocal`; `const quando = ref('')`; em `carregar`, `quando.value = paraInputLocal(data.sugestao_horario || data.agendado_para)`. Acrescentar no bloco da prévia:

```vue
      <div v-if="peca.status === 'montado'" class="flex flex-col gap-2">
        <input v-model="quando" data-testid="agendar-quando" type="datetime-local" class="rounded border border-n-weak p-2 text-sm" />
        <div class="flex gap-2">
          <Button
            data-testid="agendar"
            :label="t('RAMON.CONTEUDO.AGENDAR')"
            :disabled="!quando"
            :is-loading="ocupado"
            @click="agir(() => RamonConteudoAPI.agendar(peca.id, new Date(quando).toISOString()))"
          />
          <Button outline :label="t('RAMON.CONTEUDO.PUBLICAR_AGORA')" :is-loading="ocupado" @click="agir(() => RamonConteudoAPI.publicarAgora(peca.id))" />
        </div>
      </div>
      <div v-if="peca.status === 'agendado'" class="flex flex-col gap-2 text-sm">
        <span>{{ t('RAMON.CONTEUDO.AGENDADA_PARA', { quando: new Date(peca.agendado_para).toLocaleString('pt-BR', { dateStyle: 'short', timeStyle: 'short' }) }) }}</span>
        <div class="flex gap-2">
          <Button outline :label="t('RAMON.CONTEUDO.PUBLICAR_AGORA')" @click="agir(() => RamonConteudoAPI.publicarAgora(peca.id))" />
          <Button ruby outline :label="t('RAMON.CONTEUDO.CANCELAR')" @click="agir(() => RamonConteudoAPI.cancelarAgendamento(peca.id))" />
        </div>
      </div>
      <Button v-if="peca.status === 'falhou'" :label="t('RAMON.CONTEUDO.TENTAR_DE_NOVO')" @click="agir(() => RamonConteudoAPI.tentarDeNovo(peca.id))" />
      <a v-if="peca.permalink" :href="peca.permalink" target="_blank" rel="noopener" class="text-sm text-n-blue-11 underline">
        {{ t('RAMON.CONTEUDO.VER_NO_INSTAGRAM') }}
      </a>
```

- [ ] **Step 4: i18n** — `AGENDAR: "Aprovar e agendar"`, `PUBLICAR_AGORA: "Publicar agora"`, `AGENDADA_PARA: "Agendada para {quando}"`, `CANCELAR: "Cancelar agendamento"`, `TENTAR_DE_NOVO: "Tentar de novo"`, `VER_NO_INSTAGRAM: "Ver no Instagram"` (en: `"Approve and schedule"`, `"Publish now"`, `"Scheduled for {quando}"`, `"Cancel schedule"`, `"Try again"`, `"View on Instagram"`).

- [ ] **Step 5:** `pnpm eslint` nos arquivos tocados · Expected: limpo.

- [ ] **Step 6: Commit**

```bash
git add app/javascript/dashboard/api/ramonConteudo.js app/javascript/dashboard/routes/dashboard/ramon/components/conteudo/PecaPainel.vue app/javascript/dashboard/routes/dashboard/ramon/helpers/dataLocal.js app/javascript/dashboard/i18n/locale/pt_BR/ramon.json app/javascript/dashboard/i18n/locale/en/ramon.json app/javascript/dashboard/routes/dashboard/ramon/pages/specs/PecaPainel.spec.js
git commit -m "feat(conteudo): aprovar e agendar, publicar agora e tentar de novo na tela"
```

### Task 18: Renovação semanal do token

**Files:**
- Create: `app/jobs/ramon/ig_token_refresh_job.rb`
- Modify: `config/schedule.yml`
- Test: `spec/jobs/ramon/ig_token_refresh_job_spec.rb`

**Interfaces:**
- Consumes: `GlobalConfigService.load`, `InstallationConfig#value=`, `Ramon::NtfyPushJob`.
- Produces: cron semanal que troca `RAMON_IG_PUBLISH_TOKEN` pelo renovado.

- [ ] **Step 1: Teste (falha)**

```ruby
require 'rails_helper'

RSpec.describe Ramon::IgTokenRefreshJob do
  let(:url) { 'https://graph.instagram.com/refresh_access_token' }

  before { InstallationConfig.create!(name: 'RAMON_IG_PUBLISH_TOKEN', value: 'velho', locked: false) }

  it 'grava o token renovado' do
    stub_request(:get, url).with(query: { grant_type: 'ig_refresh_token', access_token: 'velho' })
                           .to_return(body: { access_token: 'novo', expires_in: 5_184_000 }.to_json)
    described_class.perform_now
    expect(InstallationConfig.find_by(name: 'RAMON_IG_PUBLISH_TOKEN').value).to eq 'novo'
  end

  it 'avisa no celular quando a Meta recusa' do
    stub_request(:get, url).with(query: hash_including({})).to_return(status: 400, body: { error: { message: 'expired' } }.to_json)
    expect { described_class.perform_now }.to have_enqueued_job(Ramon::NtfyPushJob)
    expect(InstallationConfig.find_by(name: 'RAMON_IG_PUBLISH_TOKEN').value).to eq 'velho'
  end
end
```

- [ ] **Step 2: Job**

```ruby
# Renova o token de publicação do Instagram (vale 60 dias; renovar estende). Semanal.
class Ramon::IgTokenRefreshJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    token = GlobalConfigService.load('RAMON_IG_PUBLISH_TOKEN', nil)
    return if token.blank?

    uri = URI('https://graph.instagram.com/refresh_access_token')
    uri.query = URI.encode_www_form(grant_type: 'ig_refresh_token', access_token: token)
    res = Net::HTTP.get_response(uri)
    novo = JSON.parse(res.body.presence || '{}')['access_token']
    raise "HTTP #{res.code}" if novo.blank?

    InstallationConfig.find_by!(name: 'RAMON_IG_PUBLISH_TOKEN').update!(value: novo)
  rescue StandardError => e
    Ramon::NtfyPushJob.perform_later(nil, title: 'Token do Instagram nao renovou',
                                          body: "#{e.message} — gerar outro no painel Meta e colar no super admin")
  end
end
```

- [ ] **Step 3: Cron**

```yaml
# Renova o token de publicação do Instagram toda segunda 06:00 UTC.
ramon_ig_token_refresh_job:
  cron: '0 6 * * 1'
  class: 'Ramon::IgTokenRefreshJob'
  queue: scheduled_jobs
```

- [ ] **Step 4: Commit**

```bash
git add app/jobs/ramon/ig_token_refresh_job.rb config/schedule.yml spec/jobs/ramon/ig_token_refresh_job_spec.rb
git commit -m "feat(conteudo): renovação semanal do token de publicação"
```

### Task 19: PR 3 no ar + smoke final

- [ ] **Step 1:** PR 3 (Tasks 13–18): push pelo Eduardo, `gh pr create`, CI verde, merge, deploy (sem migração).
- [ ] **Step 2 (gate Eduardo):** gerar token no painel Meta (produto Instagram → Gerar token, conta `@ramonantonioadvogados`) e colar em super admin → Instagram → `RAMON_IG_PUBLISH_TOKEN`; criar pasta de acervo e pôr o id em `RAMON_DRIVE_POSTS_ID` no `chatwoot.env`. ⚠️ Service account não tem cota no "Meu Drive": a pasta tem que estar dentro do drive compartilhado que o hub já usa (`RAMON_DRIVE_ROOT_ID`) ou compartilhada de forma que o upload funcione — testar com 1 upload antes do smoke.
- [ ] **Step 3:** Smoke doc em bloco (`comercial\docs\2026-10-XX-smoke-conteudo-instagram.md`): peça montada → sugestão mostra a próxima ter/qua/qui 12h → agendar pra +5 min → post no feed (sem story), colaborador se houver crédito, Notion `publicado`, pasta no Drive, push no celular; "Publicar agora" e "Cancelar agendamento" numa segunda peça (cancelar antes de publicar).
- [ ] **Step 4:** Atualizar memória `conteudo-instagram-no-hub.md` + plano mestre do hub com PRs/SHAs, e registrar no decision-log do comercial (proposta ao Eduardo): conteúdo do IG passa a ser aprovado e publicado pelo hub.
