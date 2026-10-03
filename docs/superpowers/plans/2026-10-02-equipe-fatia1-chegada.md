# Equipe · Fatia 1 — Chegada de cliente — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Recepção avisa "chegou cliente" pra uma pessoa; o alerta insiste na tela dela (overlay + toque em loop + notificação do sistema + título piscando) até ela responder em texto livre; sem resposta em 3 min o alerta volta pra quem avisou.

**Architecture:** Tabela própria `ramon_chegadas` (model `Chegada`, isolado das conversas do Chatwoot). O model transmite `ramon.chegada.created/updated` direto pelo `ActionCableBroadcastJob` aos `pubsub_token` de quem avisou e de quem recebe. Um job agendado (3 min) marca a escalada. No front, um store pinia `chegadas` recebe os eventos; `AlertaChegada.vue` (montado sempre no `Dashboard.vue`, padrão do `FloatingCallWidget`) faz o alerta; `ChegouCliente.vue` (botão flutuante + Dialog) é o painel da Recepção com "Quem vem hoje" (ADVBOX), busca (endpoint existente) e campo livre.

**Tech Stack:** Rails 7.1 / Ruby 3.4.4 / RSpec · Vue 3 `<script setup>` / Pinia / Tailwind (tokens `n-*`) / Vitest.

**Spec:** `docs/superpowers/specs/2026-10-02-equipe-chegada-e-chat-design.md`

## Global Constraints

- Worktree: `C:\Users\dudsl\RAdvogados\comercial\projetos\ramon-hub-wt-equipe`, branch `feat/equipe` (base `origin/ramon`). Sempre `git -C <worktree>` ou caminho absoluto — nunca commitar no checkout principal.
- Sem Ruby local: RSpec/RuboCop rodam só no CI. Front: eslint local via `./node_modules/.bin/eslint`; vitest local só com `pnpm install` REAL no worktree (`npx pnpm@10.2.0 install`) — se não der, CI cobre.
- RuboCop: `Style/HashSyntax EnforcedShorthandSyntax: never` (escreva `id: id`, nunca `id:`), 150 colunas, AbcSize/Complexity → decompor em privados.
- Vue: `<script setup>` Composition API, Tailwind só (sem CSS/scoped/inline), eventos camelCase, sem string crua no template (i18n em `app/javascript/dashboard/i18n/locale/{pt_BR,en}/ramon.json`, chave `RAMON.CHEGADA.*` — preencher os DOIS arquivos).
- Nome do time da Recepção = `recepção` (exato, igual `RamonPortariaListener::FALLBACK`). ⚠️ 02/10 a caixa do escritório mudou pra "atendimento por atribuição" (branch `feat/atendimento-por-atribuicao`, outra sessão) e pode remover o `RamonPortariaListener` — por isso `Chegada::RECEPCAO` é constante PRÓPRIA (não referenciar a do listener). Gate: Gabriela precisa ser membro do time `recepção` (não interfere na atribuição, que usa a caixa, não o time).
- Escalada: **3 min** (`Chegada::ESCALAR_APOS`).
- ADVBOX: cota 500/dia compartilhada → agenda em cache 10 min, `settings` em cache 24 h.
- Fuso: "hoje" = `America/Sao_Paulo` (app roda em UTC).
- Título de PR = conventional commit (`feat(equipe): ...`). Commits terminam com as linhas de atribuição da sessão.

## Review Focus

1. **Destinatário recarrega a página com alerta pendente** → o alerta tem que reaparecer (o store carrega `index` no mount). Teste no Task 4 (`carregar`) + Task 5 (alerta a partir de item carregado).
2. **Duas chegadas seguidas pra mesma pessoa** → fila: mostra uma, contador "+1", responder a 1ª revela a 2ª sem parar o toque. Teste no Task 5.
3. **Resposta chega depois da escalada** → estado vira `respondido` e some o alerta de escalada de quem avisou. Teste no Task 1 (`estado`) + Task 4 (getter).
4. **ADVBOX fora do ar** → "Quem vem hoje" mostra aviso e o campo livre segue funcionando (503 tratado). Teste no Task 3.
5. **Agente comum tentando avisar / responder chegada de outro** → 403 / 404. Teste no Task 2.

---

### Task 1: Model `Chegada` + migração

**Files:**
- Create: `db/migrate/20261002000001_create_ramon_chegadas.rb`
- Modify: `db/schema.rb` (versão + `create_table "ramon_chegadas"` em ordem alfabética entre os `create_table`)
- Create: `app/models/chegada.rb`
- Modify: `app/models/account.rb:89` (ao lado de `has_many :reunioes`)
- Test: `spec/models/chegada_spec.rb`

**Interfaces:**
- Produces: `Chegada` (`criado_por`, `destinatario` → `User`; `cliente_nome`, `motivo`, `advbox_customer_id`, `advbox_post_id`, `resposta`, `respondido_em`, `escalado_em`), `Chegada::RECEPCAO`, `Chegada::ESCALAR_APOS`, `Chegada.recepcao?(account, user) → Boolean`, scope `de_hoje`, `#estado → 'aguardando'|'escalado'|'respondido'`, `#push_event_data → Hash` (chaves: `id account_id cliente_nome motivo resposta estado criado_por{id,name} destinatario{id,name} created_at respondido_em escalado_em`), `Account#chegadas`.

- [ ] **Step 1: Write the failing test** — `spec/models/chegada_spec.rb`

```ruby
require 'rails_helper'

RSpec.describe Chegada do
  let(:account) { create(:account) }
  let(:gabriela) { create(:user, account: account, role: :agent) }
  let(:brenda) { create(:user, account: account, role: :agent) }

  def chegada(attrs = {})
    account.chegadas.create!({ criado_por: gabriela, destinatario: brenda, cliente_nome: 'Maria' }.merge(attrs))
  end

  it 'exige nome do cliente' do
    expect(account.chegadas.new(criado_por: gabriela, destinatario: brenda)).not_to be_valid
  end

  it 'deriva o estado: resposta vence a escalada' do
    expect(chegada.estado).to eq('aguardando')
    expect(chegada(escalado_em: Time.current).estado).to eq('escalado')
    expect(chegada(escalado_em: 1.minute.ago, resposta: 'Já vou', respondido_em: Time.current).estado).to eq('respondido')
  end

  it 'transmite created e updated pra quem avisou e pra quem recebe' do
    expect { chegada }.to have_enqueued_job(ActionCableBroadcastJob)
      .with(contain_exactly(gabriela.pubsub_token, brenda.pubsub_token), 'ramon.chegada.created', hash_including(cliente_nome: 'Maria'))

    registro = chegada
    expect { registro.update!(resposta: 'Já vou', respondido_em: Time.current) }
      .to have_enqueued_job(ActionCableBroadcastJob).with(anything, 'ramon.chegada.updated', hash_including(estado: 'respondido'))
  end

  it 'reconhece quem é da Recepção pelo time' do
    time = create(:team, account: account, name: Chegada::RECEPCAO)
    create(:team_member, team: time, user: gabriela)

    expect(described_class.recepcao?(account, gabriela)).to be(true)
    expect(described_class.recepcao?(account, brenda)).to be(false)
  end

  it 'de_hoje usa o dia de São Paulo' do
    travel_to Time.zone.parse('2026-10-03 01:00:00 UTC') do # 22:00 de 02/10 em SP
      ontem_sp = chegada
      expect(account.chegadas.de_hoje).to include(ontem_sp)
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails** — sem Ruby local: confirmar por leitura que `Chegada` não existe (`grep -rn "class Chegada" app` vazio). O vermelho real aparece no CI se o Step 3 faltar.

- [ ] **Step 3: Migração** — `db/migrate/20261002000001_create_ramon_chegadas.rb`

```ruby
# Equipe · chegada de cliente: Recepção avisa, destinatário responde (texto livre),
# sem resposta em 3 min escala de volta pra quem avisou.
class CreateRamonChegadas < ActiveRecord::Migration[7.1]
  def change
    create_table :ramon_chegadas do |t|
      t.bigint :account_id, null: false
      t.bigint :criado_por_id, null: false
      t.bigint :destinatario_id, null: false
      t.string :cliente_nome, null: false
      t.string :motivo
      t.bigint :advbox_customer_id
      t.bigint :advbox_post_id
      t.text :resposta
      t.datetime :respondido_em
      t.datetime :escalado_em
      t.timestamps
      t.index [:account_id, :created_at]
    end
  end
end
```

- [ ] **Step 4: `db/schema.rb`** — trocar `define(version: 2026_09_28_000004)` por `define(version: 2026_10_02_000001)` e inserir na posição alfabética dos `create_table`:

```ruby
  create_table "ramon_chegadas", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "criado_por_id", null: false
    t.bigint "destinatario_id", null: false
    t.string "cliente_nome", null: false
    t.string "motivo"
    t.bigint "advbox_customer_id"
    t.bigint "advbox_post_id"
    t.text "resposta"
    t.datetime "respondido_em"
    t.datetime "escalado_em"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "created_at"], name: "index_ramon_chegadas_on_account_id_and_created_at"
  end

```

- [ ] **Step 5: Model** — `app/models/chegada.rb`

```ruby
# Chegada de cliente na recepção (Equipe · Fatia 1): a Recepção avisa quem vai
# atender; o alerta insiste na tela da pessoa até ela responder em texto livre
# e, sem resposta em 3 min, volta pra quem avisou (Ramon::ChegadaEscalarJob).
class Chegada < ApplicationRecord
  self.table_name = 'ramon_chegadas'

  RECEPCAO = 'recepção' # mesmo time da Portaria (RamonPortariaListener::FALLBACK)
  ESCALAR_APOS = 3.minutes
  ZONA = 'America/Sao_Paulo'

  belongs_to :account
  belongs_to :criado_por, class_name: 'User'
  belongs_to :destinatario, class_name: 'User'

  validates :cliente_nome, presence: true

  scope :de_hoje, -> { where(created_at: Time.find_zone!(ZONA).now.all_day) }

  after_create_commit { transmitir('ramon.chegada.created') }
  after_update_commit { transmitir('ramon.chegada.updated') }

  def self.recepcao?(account, user)
    account.teams.find_by(name: RECEPCAO)&.members&.exists?(user.id) || false
  end

  def estado
    return 'respondido' if respondido_em.present?

    escalado_em.present? ? 'escalado' : 'aguardando'
  end

  def push_event_data
    {
      id: id, account_id: account_id, cliente_nome: cliente_nome, motivo: motivo, resposta: resposta, estado: estado,
      criado_por: { id: criado_por_id, name: criado_por.name },
      destinatario: { id: destinatario_id, name: destinatario.name },
      created_at: created_at.iso8601, respondido_em: respondido_em&.iso8601, escalado_em: escalado_em&.iso8601
    }
  end

  private

  def transmitir(evento)
    ActionCableBroadcastJob.perform_later([criado_por.pubsub_token, destinatario.pubsub_token].uniq, evento, push_event_data)
  end
end
```

- [ ] **Step 6: Account** — em `app/models/account.rb`, logo abaixo de `has_many :reunioes, class_name: 'Reuniao', dependent: :destroy_async`:

```ruby
  has_many :chegadas, class_name: 'Chegada', dependent: :destroy_async
```
(`class_name` obrigatório — o inflector não sabe plural PT.)

- [ ] **Step 7: Commit**

```bash
git -C <worktree> add db/migrate/20261002000001_create_ramon_chegadas.rb db/schema.rb app/models/chegada.rb app/models/account.rb spec/models/chegada_spec.rb
git -C <worktree> commit -m "feat(equipe): model Chegada (chegada de cliente)"
```

---

### Task 2: API — policy, controller (index/create/responder), rotas, job de escalada

**Files:**
- Create: `app/policies/ramon_chegada_policy.rb`
- Create: `app/controllers/api/v1/accounts/ramon_chegadas_controller.rb`
- Create: `app/jobs/ramon/chegada_escalar_job.rb`
- Modify: `config/routes.rb` (bloco `ramon_*`, depois de `resources :ramon_reunioes ... end`, ~linha 302)
- Test: `spec/controllers/api/v1/accounts/ramon_chegadas_controller_spec.rb`, `spec/jobs/ramon/chegada_escalar_job_spec.rb`

**Interfaces:**
- Consumes: `Chegada`, `Chegada.recepcao?`, `Account#chegadas` (Task 1).
- Produces (HTTP, base `/api/v1/accounts/:account_id/ramon_chegadas`):
  - `GET /` → `{ payload: [push_event_data...], pode_avisar: Boolean }` (recepção/admin veem todas de hoje; os demais só as suas)
  - `POST /` body `{ cliente_nome, motivo?, advbox_customer_id?, advbox_post_id?, destinatario_id }` → `push_event_data` (403 se não for recepção/admin)
  - `POST /:id/responder` body `{ resposta }` → `push_event_data` (404 se não for o destinatário)
  - `GET /agenda` → definido no Task 3 (rota e policy já criadas aqui).
- Produces: `Ramon::ChegadaEscalarJob.perform_later(chegada_id)`.

- [ ] **Step 1: Write the failing tests**

`spec/controllers/api/v1/accounts/ramon_chegadas_controller_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe 'Ramon Chegadas API', type: :request do
  let(:account) { create(:account) }
  let(:gabriela) { create(:user, account: account, role: :agent) }
  let(:brenda) { create(:user, account: account, role: :agent) }
  let(:outro) { create(:user, account: account, role: :agent) }
  let(:url) { "/api/v1/accounts/#{account.id}/ramon_chegadas" }

  before do
    time = create(:team, account: account, name: Chegada::RECEPCAO)
    create(:team_member, team: time, user: gabriela)
  end

  def avisar(user = gabriela)
    post url, params: { cliente_nome: 'Maria', motivo: 'Assinatura', destinatario_id: brenda.id },
              headers: user.create_new_auth_token, as: :json
  end

  it 'recepção avisa e agenda a escalada' do
    expect { avisar }.to have_enqueued_job(Ramon::ChegadaEscalarJob)
    expect(response).to have_http_status(:success)
    expect(response.parsed_body).to include('cliente_nome' => 'Maria', 'estado' => 'aguardando')
    expect(response.parsed_body['destinatario']).to include('id' => brenda.id)
  end

  it 'agente fora da recepção não avisa' do
    avisar(outro)
    expect(response).to have_http_status(:unauthorized)
  end

  it 'só o destinatário responde' do
    avisar
    id = response.parsed_body['id']

    post "#{url}/#{id}/responder", params: { resposta: 'x' }, headers: outro.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)

    post "#{url}/#{id}/responder", params: { resposta: 'Já vou' }, headers: brenda.create_new_auth_token, as: :json
    expect(response.parsed_body).to include('estado' => 'respondido', 'resposta' => 'Já vou')
  end

  it 'index: recepção vê todas e pode avisar; os demais só as suas' do
    avisar
    get url, headers: gabriela.create_new_auth_token, as: :json
    expect(response.parsed_body).to include('pode_avisar' => true)
    expect(response.parsed_body['payload'].size).to eq(1)

    get url, headers: outro.create_new_auth_token, as: :json
    expect(response.parsed_body).to include('pode_avisar' => false, 'payload' => [])

    get url, headers: brenda.create_new_auth_token, as: :json
    expect(response.parsed_body['payload'].size).to eq(1)
  end
end
```

> Nota: confirme no spec de outro controller Ramon qual status o Pundit devolve em negado neste fork (`:unauthorized` é o padrão do Chatwoot — `rescue_from Pundit::NotAuthorizedError` em `Api::V1::Accounts::BaseController`/`EnsureCurrentAccountHelper`). Use o que o fork usa.

`spec/jobs/ramon/chegada_escalar_job_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe Ramon::ChegadaEscalarJob do
  let(:account) { create(:account) }
  let(:chegada) do
    account.chegadas.create!(criado_por: create(:user, account: account), destinatario: create(:user, account: account),
                             cliente_nome: 'Maria')
  end

  it 'escala a chegada sem resposta' do
    described_class.perform_now(chegada.id)
    expect(chegada.reload.estado).to eq('escalado')
  end

  it 'não mexe na chegada já respondida' do
    chegada.update!(resposta: 'Já vou', respondido_em: Time.current)
    described_class.perform_now(chegada.id)
    expect(chegada.reload.escalado_em).to be_nil
  end

  it 'ignora chegada apagada' do
    expect { described_class.perform_now(0) }.not_to raise_error
  end
end
```

- [ ] **Step 2: Run tests to verify they fail** — sem Ruby local; confirmar que as classes não existem. (CI dá o vermelho/verde.)

- [ ] **Step 3: Policy** — `app/policies/ramon_chegada_policy.rb`

```ruby
class RamonChegadaPolicy < ApplicationPolicy
  def index?
    @account_user.administrator? || @account_user.agent?
  end

  def responder?
    index?
  end

  def create?
    @account_user.administrator? || Chegada.recepcao?(@account, @user)
  end

  def agenda?
    create?
  end
end
```

- [ ] **Step 4: Controller** — `app/controllers/api/v1/accounts/ramon_chegadas_controller.rb`

```ruby
# Equipe · chegada de cliente: Recepção avisa, destinatário responde. A busca de
# cliente no ADVBOX reusa ramon_calculos#advbox_customers.
class Api::V1::Accounts::RamonChegadasController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :check_authorization

  def index
    chegadas = Current.account.chegadas.de_hoje.includes(:criado_por, :destinatario).order(:created_at)
    chegadas = chegadas.where('criado_por_id = :id OR destinatario_id = :id', id: Current.user.id) unless pode_avisar?
    render json: { payload: chegadas.map(&:push_event_data), pode_avisar: pode_avisar? }
  end

  def create
    chegada = Current.account.chegadas.create!(
      chegada_params.merge(criado_por: Current.user, destinatario: Current.account.users.find(params[:destinatario_id]))
    )
    Ramon::ChegadaEscalarJob.set(wait: Chegada::ESCALAR_APOS).perform_later(chegada.id)
    render json: chegada.push_event_data
  end

  def responder
    chegada = Current.account.chegadas.where(destinatario: Current.user).find(params[:id])
    chegada.update!(resposta: params.require(:resposta), respondido_em: Time.current)
    render json: chegada.push_event_data
  end

  private

  def pode_avisar?
    Current.account_user.administrator? || Chegada.recepcao?(Current.account, Current.user)
  end

  def chegada_params
    params.permit(:cliente_nome, :motivo, :advbox_customer_id, :advbox_post_id)
  end

  def check_authorization
    authorize(:ramon_chegada, :"#{action_name}?")
  end
end
```

- [ ] **Step 5: Job** — `app/jobs/ramon/chegada_escalar_job.rb`

```ruby
# 3 min depois do aviso: se ninguém respondeu, marca a escalada — o update
# transmite ramon.chegada.updated e o alerta toca pra quem avisou.
class Ramon::ChegadaEscalarJob < ApplicationJob
  queue_as :default

  def perform(chegada_id)
    chegada = Chegada.find_by(id: chegada_id)
    return if chegada.nil? || chegada.respondido_em.present? || chegada.escalado_em.present?

    chegada.update!(escalado_em: Time.current)
  end
end
```

- [ ] **Step 6: Rotas** — em `config/routes.rb`, logo após o bloco `resources :ramon_reunioes ... end`:

```ruby
          resources :ramon_chegadas, only: [:index, :create], controller: 'ramon_chegadas' do
            member { post :responder }
            collection { get :agenda }
          end
```

- [ ] **Step 7: Commit**

```bash
git -C <worktree> add app/policies/ramon_chegada_policy.rb app/controllers/api/v1/accounts/ramon_chegadas_controller.rb app/jobs/ramon/chegada_escalar_job.rb config/routes.rb spec/controllers/api/v1/accounts/ramon_chegadas_controller_spec.rb spec/jobs/ramon/chegada_escalar_job_spec.rb
git -C <worktree> commit -m "feat(equipe): API de chegadas + escalada em 3 min"
```

---

### Task 3: "Quem vem hoje" — `Ramon::AgendaHojeService` + `GET agenda`

**Files:**
- Create: `app/services/ramon/agenda_hoje_service.rb`
- Modify: `app/controllers/api/v1/accounts/ramon_chegadas_controller.rb` (action `agenda`)
- Test: `spec/services/ramon/agenda_hoje_service_spec.rb`, + 1 exemplo no spec do controller (503)

**Interfaces:**
- Consumes: `Ramon::AdvboxClient.posts(params)` e `.settings` (`lib/ramon/advbox_client.rb`), `Ramon::AdvboxClient::UnavailableError`.
- Produces: `Ramon::AgendaHojeService.new(account).perform → Array<Hash>` com chaves `advbox_post_id cliente_nome advbox_customer_id notas responsavel_advbox destinatario_id` (destinatario_id = user do hub casado por e-mail, ou nil); `GET ramon_chegadas/agenda → { payload: [...] }` ou 503 `{ error: 'ADVBOX_UNAVAILABLE' }`.

- [ ] **Step 1: Write the failing test** — `spec/services/ramon/agenda_hoje_service_spec.rb`

```ruby
require 'rails_helper'

RSpec.describe Ramon::AgendaHojeService do
  let(:account) { create(:account) }
  let!(:brenda) { create(:user, account: account, email: 'brendantunes_@hotmail.com') }

  before do
    allow(Ramon::AdvboxClient).to receive(:posts).and_return(
      'data' => [
        { 'id' => 1, 'task' => 'ATENDIMENTO', 'notes' => 'traz CNIS',
          'lawsuit' => { 'customers' => [{ 'customer_id' => 9, 'name' => 'INSS', 'customers_origins_id' => 25_705 },
                                         { 'customer_id' => 7, 'name' => 'MARIA SILVA', 'customers_origins_id' => nil }] },
          'users' => [{ 'user_id' => 260_009, 'name' => 'BRENDA ANTUNES' }] },
        { 'id' => 2, 'task' => 'ANALISAR SENTENÇA', 'lawsuit' => { 'customers' => [] }, 'users' => [] }
      ]
    )
    allow(Ramon::AdvboxClient).to receive(:settings)
      .and_return('users' => [{ 'id' => 260_009, 'email' => 'BRENDANTUNES_@HOTMAIL.COM' }])
  end

  it 'lista só ATENDIMENTO, pula a parte contrária e casa o responsável por e-mail' do
    linhas = described_class.new(account).perform

    expect(linhas.size).to eq(1)
    expect(linhas.first).to include(advbox_post_id: 1, cliente_nome: 'MARIA SILVA', advbox_customer_id: 7,
                                    notas: 'traz CNIS', responsavel_advbox: 'BRENDA ANTUNES', destinatario_id: brenda.id)
  end

  it 'pede as tarefas do dia de São Paulo' do
    travel_to Time.zone.parse('2026-10-03 01:00:00 UTC') { described_class.new(account).perform }
    expect(Ramon::AdvboxClient).to have_received(:posts).with(hash_including(date_start: '2026-10-02', date_end: '2026-10-02'))
  end
end
```

E no spec do controller (Task 2), acrescentar:

```ruby
  it 'agenda devolve 503 com ADVBOX fora' do
    allow(Ramon::AdvboxClient).to receive(:posts).and_raise(Ramon::AdvboxClient::UnavailableError)
    get "#{url}/agenda", headers: gabriela.create_new_auth_token, as: :json
    expect(response).to have_http_status(:service_unavailable)
  end
```

- [ ] **Step 2: Run tests to verify they fail** — CI.

- [ ] **Step 3: Service** — `app/services/ramon/agenda_hoje_service.rb`

```ruby
# "Quem vem hoje" pra Recepção: tarefas ATENDIMENTO do dia no ADVBOX, com o
# responsável casado ao usuário do hub por e-mail. A API do ADVBOX tem cota de
# 500 chamadas/dia (compartilhada) → agenda em cache de 10 min, settings de 24 h.
class Ramon::AgendaHojeService
  TAREFA = 'ATENDIMENTO'
  # ponytail: origem que o ADVBOX põe nas partes contrárias (INSS etc.) nesta conta;
  # se errar, a Gabriela corrige o nome no campo antes de avisar.
  PARTE_CONTRARIA = 25_705

  def initialize(account)
    @account = account
  end

  def perform
    tarefas_de_hoje.map { |tarefa| linha(tarefa) }
  end

  private

  def tarefas_de_hoje
    hoje = Time.find_zone!(Chegada::ZONA).today.iso8601
    Rails.cache.fetch("ramon/agenda_hoje/#{hoje}", expires_in: 10.minutes) do
      resposta = Ramon::AdvboxClient.posts(date_start: hoje, date_end: hoje, limit: 100)
      Array(resposta.is_a?(Hash) ? resposta['data'] : resposta).select { |tarefa| tarefa['task'] == TAREFA }
    end
  end

  def linha(tarefa)
    cliente = Array(tarefa.dig('lawsuit', 'customers')).find { |c| c['customers_origins_id'] != PARTE_CONTRARIA }
    responsavel = Array(tarefa['users']).first || {}
    {
      advbox_post_id: tarefa['id'], cliente_nome: cliente&.dig('name'), advbox_customer_id: cliente&.dig('customer_id'),
      notas: tarefa['notes'], responsavel_advbox: responsavel['name'], destinatario_id: usuario_do_hub(responsavel['user_id'])&.id
    }
  end

  def usuario_do_hub(advbox_user_id)
    email = emails_advbox[advbox_user_id]
    email && @account.users.find_by('LOWER(users.email) = ?', email.downcase)
  end

  def emails_advbox
    @emails_advbox ||= Rails.cache.fetch('ramon/advbox_users_email', expires_in: 24.hours) do
      Array(Ramon::AdvboxClient.settings['users']).to_h { |user| [user['id'], user['email']] }
    end
  end
end
```

- [ ] **Step 4: Action** — no controller, depois de `responder`:

```ruby
  def agenda
    render json: { payload: Ramon::AgendaHojeService.new(Current.account).perform }
  rescue Ramon::AdvboxClient::UnavailableError
    render json: { error: 'ADVBOX_UNAVAILABLE' }, status: :service_unavailable
  end
```

- [ ] **Step 5: Commit**

```bash
git -C <worktree> add app/services/ramon/agenda_hoje_service.rb app/controllers/api/v1/accounts/ramon_chegadas_controller.rb spec/services/ramon/agenda_hoje_service_spec.rb spec/controllers/api/v1/accounts/ramon_chegadas_controller_spec.rb
git -C <worktree> commit -m "feat(equipe): quem vem hoje (tarefas ATENDIMENTO do ADVBOX)"
```

---

### Task 4: Front — API client, store `chegadas`, eventos do ActionCable

**Files:**
- Create: `app/javascript/dashboard/api/ramonChegadas.js`
- Create: `app/javascript/dashboard/stores/chegadas.js`
- Modify: `app/javascript/dashboard/helper/actionCable.js` (mapa de eventos ~linha 59 + handler ao lado de `onLeadUpsert`)
- Test: `app/javascript/dashboard/stores/chegadas.spec.js`

**Interfaces:**
- Consumes: HTTP do Task 2/3.
- Produces: `RamonChegadasAPI` (`get()`, `create(data)`, `responder(id, resposta)`, `agenda()`); `useChegadasStore()` com state `itens: Chegada[]`, `podeAvisar: Boolean`, `vistos: number[]`; getter `alertasPara(userId) → Chegada[]`; actions `upsert(chegada)`, `carregar()`, `criar(payload) → chegada`, `responder(id, resposta)`, `marcarVisto(id)`.

- [ ] **Step 0 (setup do worktree, se ainda não feito):** `npx pnpm@10.2.0 install` dentro do worktree + copiar `.husky/_/husky.sh` do repo principal. Se o install falhar, seguir só com eslint (`./node_modules/.bin/eslint` via junction) e deixar vitest pro CI.

- [ ] **Step 1: Write the failing test** — `app/javascript/dashboard/stores/chegadas.spec.js`

```js
import { setActivePinia, createPinia } from 'pinia';
import { useChegadasStore } from './chegadas';
import ChegadasAPI from 'dashboard/api/ramonChegadas';

vi.mock('dashboard/api/ramonChegadas', () => ({
  default: { get: vi.fn(), create: vi.fn(), responder: vi.fn() },
}));

const chegada = (over = {}) => ({
  id: 1,
  cliente_nome: 'Maria',
  estado: 'aguardando',
  criado_por: { id: 10, name: 'Gabriela' },
  destinatario: { id: 20, name: 'Brenda' },
  ...over,
});

describe('useChegadasStore', () => {
  beforeEach(() => setActivePinia(createPinia()));

  it('alerta o destinatário enquanto não responde', () => {
    const store = useChegadasStore();
    store.upsert(chegada());
    expect(store.alertasPara(20)).toHaveLength(1);
    expect(store.alertasPara(10)).toHaveLength(0);
    store.upsert(chegada({ estado: 'respondido' }));
    expect(store.alertasPara(20)).toHaveLength(0);
  });

  it('escalada alerta quem avisou até marcar visto; resposta tardia apaga', () => {
    const store = useChegadasStore();
    store.upsert(chegada({ estado: 'escalado' }));
    expect(store.alertasPara(10)).toHaveLength(1);
    store.marcarVisto(1);
    expect(store.alertasPara(10)).toHaveLength(0);
    store.upsert(chegada({ id: 2, estado: 'escalado' }));
    store.upsert(chegada({ id: 2, estado: 'respondido' }));
    expect(store.alertasPara(10)).toHaveLength(0);
  });

  it('carregar recupera pendências após recarregar a página', async () => {
    ChegadasAPI.get.mockResolvedValue({
      data: { payload: [chegada()], pode_avisar: true },
    });
    const store = useChegadasStore();
    await store.carregar();
    expect(store.podeAvisar).toBe(true);
    expect(store.alertasPara(20)).toHaveLength(1);
  });
});
```

- [ ] **Step 2: Run test to verify it fails** — `TZ=UTC ./node_modules/.bin/vitest --no-watch app/javascript/dashboard/stores/chegadas.spec.js` → FAIL (módulo não existe).

- [ ] **Step 3: API client** — `app/javascript/dashboard/api/ramonChegadas.js`

```js
/* global axios */
import ApiClient from './ApiClient';

class RamonChegadasAPI extends ApiClient {
  constructor() {
    super('ramon_chegadas', { accountScoped: true });
  }

  responder(id, resposta) {
    return axios.post(`${this.url}/${id}/responder`, { resposta });
  }

  agenda() {
    return axios.get(`${this.url}/agenda`);
  }
}

export default new RamonChegadasAPI();
```

- [ ] **Step 4: Store** — `app/javascript/dashboard/stores/chegadas.js`

```js
import { defineStore } from 'pinia';
import ChegadasAPI from 'dashboard/api/ramonChegadas';

export const useChegadasStore = defineStore('chegadas', {
  state: () => ({ itens: [], podeAvisar: false, vistos: [] }),

  getters: {
    // O que insiste na tela de quem está logado: chegada pra mim sem resposta,
    // ou chegada que eu avisei e escalou (ninguém respondeu em 3 min).
    alertasPara: state => userId =>
      state.itens.filter(
        c =>
          c.estado !== 'respondido' &&
          (c.destinatario.id === userId ||
            (c.criado_por.id === userId &&
              c.estado === 'escalado' &&
              !state.vistos.includes(c.id)))
      ),
  },

  actions: {
    upsert(chegada) {
      const i = this.itens.findIndex(c => c.id === chegada.id);
      if (i === -1) this.itens.push(chegada);
      else this.itens.splice(i, 1, chegada);
    },
    async carregar() {
      const { data } = await ChegadasAPI.get();
      this.itens = data.payload;
      this.podeAvisar = data.pode_avisar;
    },
    async criar(payload) {
      const { data } = await ChegadasAPI.create(payload);
      this.upsert(data);
      return data;
    },
    async responder(id, resposta) {
      const { data } = await ChegadasAPI.responder(id, resposta);
      this.upsert(data);
    },
    marcarVisto(id) {
      this.vistos.push(id);
    },
  },
});
```

- [ ] **Step 5: ActionCable** — em `app/javascript/dashboard/helper/actionCable.js`:
  - import no topo: `import { useChegadasStore } from 'dashboard/stores/chegadas';`
  - no mapa, depois de `'lead.updated': this.onLeadUpsert,`:
    ```js
      'ramon.chegada.created': this.onChegadaUpsert,
      'ramon.chegada.updated': this.onChegadaUpsert,
    ```
  - handler logo após `onLeadUpsert`:
    ```js
  // eslint-disable-next-line class-methods-use-this
  onChegadaUpsert = data => {
    useChegadasStore().upsert(data);
  };
    ```

- [ ] **Step 6: Run test to verify it passes** — mesmo comando do Step 2 → PASS. `./node_modules/.bin/eslint app/javascript/dashboard/stores/chegadas.js app/javascript/dashboard/stores/chegadas.spec.js app/javascript/dashboard/api/ramonChegadas.js app/javascript/dashboard/helper/actionCable.js` → limpo.

- [ ] **Step 7: Commit**

```bash
git -C <worktree> add app/javascript/dashboard/api/ramonChegadas.js app/javascript/dashboard/stores/chegadas.js app/javascript/dashboard/stores/chegadas.spec.js app/javascript/dashboard/helper/actionCable.js
git -C <worktree> commit -m "feat(equipe): store de chegadas + eventos em tempo real"
```

---

### Task 5: `AlertaChegada.vue` — o alerta que insiste

**Files:**
- Create: `app/javascript/dashboard/routes/dashboard/ramon/components/equipe/AlertaChegada.vue`
- Modify: `app/javascript/dashboard/routes/dashboard/Dashboard.vue` (import + registro + montar ao lado de `<FloatingCallWidget ... />`, linha ~179)
- Modify: `app/javascript/dashboard/i18n/locale/pt_BR/ramon.json` e `en/ramon.json` (bloco `RAMON.CHEGADA`)
- Test: `app/javascript/dashboard/routes/dashboard/ramon/components/equipe/specs/AlertaChegada.spec.js`

**Interfaces:**
- Consumes: `useChegadasStore` (Task 4), getter Vuex `getCurrentUserID`, `/audio/dashboard/ringtone.mp3`.
- Produces: componente sem props, montado sempre (não `v-if`) — ele mesmo chama `carregar()` no mount.

- [ ] **Step 1: i18n** — adicionar dentro de `"RAMON": { ... }` nos dois `ramon.json` (en com o mesmo texto em inglês simples):

pt_BR:
```json
    "CHEGADA": {
      "CHEGOU": "{quem} avisou: chegou cliente",
      "SEM_RESPOSTA": "{quem} não respondeu em 3 min",
      "NOTIF_CHEGOU": "Chegou: {cliente}",
      "NOTIF_SEM_RESPOSTA": "Sem resposta: {cliente}",
      "RESPOSTA_PLACEHOLDER": "Responder pra recepção (ex.: já vou / peça pra aguardar 5 min)",
      "RESPONDER": "Responder",
      "ENTENDI": "Entendi",
      "MAIS": "+{n} na fila",
      "BOTAO": "Chegou cliente",
      "TITULO": "Avisar chegada de cliente",
      "ABA_HOJE": "Quem vem hoje",
      "ABA_BUSCAR": "Buscar no ADVBOX",
      "ABA_LIVRE": "Livre",
      "HOJE_VAZIO": "Nenhum ATENDIMENTO marcado hoje no ADVBOX.",
      "ADVBOX_FORA": "ADVBOX indisponível — use Buscar ou Livre.",
      "BUSCAR_PLACEHOLDER": "Nome ou CPF",
      "NOME": "Nome do cliente",
      "MOTIVO": "Motivo (opcional)",
      "DESTINATARIO": "Quem vai atender",
      "AVISAR": "Avisar",
      "AGUARDANDO": "Hoje",
      "ESTADO_aguardando": "aguardando",
      "ESTADO_escalado": "sem resposta",
      "ESTADO_respondido": "respondeu"
    }
```
en: mesmas chaves (`"CHEGOU": "{quem}: a client has arrived"`, `"SEM_RESPOSTA": "{quem} didn't answer in 3 min"`, etc.).

- [ ] **Step 2: Write the failing test** — `.../equipe/specs/AlertaChegada.spec.js`

```js
import { mount, flushPromises } from '@vue/test-utils';
import { createPinia, setActivePinia } from 'pinia';
import AlertaChegada from '../AlertaChegada.vue';
import { useChegadasStore } from 'dashboard/stores/chegadas';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));
vi.mock('dashboard/composables/store', () => ({
  useStoreGetters: () => ({ getCurrentUserID: { value: 20 } }),
}));
vi.mock('dashboard/api/ramonChegadas', () => ({
  default: {
    get: vi.fn().mockResolvedValue({ data: { payload: [], pode_avisar: false } }),
    responder: vi.fn(),
  },
}));

const play = vi.fn().mockResolvedValue();
const pause = vi.fn();
vi.stubGlobal(
  'Audio',
  class {
    constructor() {
      this.play = play;
      this.pause = pause;
      this.loop = false;
      this.currentTime = 0;
    }
  }
);

const chegada = (id, over = {}) => ({
  id,
  cliente_nome: `Cliente ${id}`,
  motivo: null,
  estado: 'aguardando',
  criado_por: { id: 10, name: 'Gabriela' },
  destinatario: { id: 20, name: 'Brenda' },
  ...over,
});

describe('AlertaChegada.vue', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    play.mockClear();
    pause.mockClear();
  });

  it('toca e mostra a fila; responder a 1ª revela a 2ª; última resposta para o toque', async () => {
    const wrapper = mount(AlertaChegada);
    await flushPromises();
    const store = useChegadasStore();
    store.upsert(chegada(1));
    store.upsert(chegada(2));
    await flushPromises();

    expect(wrapper.text()).toContain('Cliente 1');
    expect(wrapper.text()).toContain('RAMON.CHEGADA.MAIS');
    expect(play).toHaveBeenCalled();

    store.upsert(chegada(1, { estado: 'respondido' }));
    await flushPromises();
    expect(wrapper.text()).toContain('Cliente 2');
    expect(pause).not.toHaveBeenCalled();

    store.upsert(chegada(2, { estado: 'respondido' }));
    await flushPromises();
    expect(wrapper.find('[data-testid="alerta-chegada"]').exists()).toBe(false);
    expect(pause).toHaveBeenCalled();
  });

  it('escalada pra quem avisou mostra "Entendi" em vez do campo de resposta', async () => {
    const wrapper = mount(AlertaChegada);
    await flushPromises();
    useChegadasStore().upsert(
      chegada(3, {
        estado: 'escalado',
        criado_por: { id: 20, name: 'Eu' },
        destinatario: { id: 30, name: 'Tamires' },
      })
    );
    await flushPromises();
    expect(wrapper.find('[data-testid="chegada-resposta"]').exists()).toBe(false);
    expect(wrapper.text()).toContain('RAMON.CHEGADA.ENTENDI');
  });
});
```

> Ajuste o mock de `dashboard/composables/store` ao formato real que o componente usar (se usar `useStore().getters`, mocke isso). O ponto é: usuário logado = id 20.

- [ ] **Step 3: Run test to verify it fails** — `TZ=UTC ./node_modules/.bin/vitest --no-watch app/javascript/dashboard/routes/dashboard/ramon/components/equipe/specs/AlertaChegada.spec.js` → FAIL.

- [ ] **Step 4: Componente** — `.../equipe/AlertaChegada.vue`

```vue
<script setup>
import { computed, ref, watch, onMounted, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStoreGetters } from 'dashboard/composables/store';
import { useChegadasStore } from 'dashboard/stores/chegadas';

// Alerta que insiste (Equipe · Fatia 1): overlay + toque em loop + notificação
// do sistema + título piscando até a pessoa responder. Montado sempre no
// Dashboard; recarregar a página recupera as pendências via carregar().
const RINGTONE_URL = '/audio/dashboard/ringtone.mp3';

const { t } = useI18n();
const getters = useStoreGetters();
const chegadas = useChegadasStore();

const userId = computed(() => getters.getCurrentUserID.value);
const alertas = computed(() => chegadas.alertasPara(userId.value));
const atual = computed(() => alertas.value[0]);
const souDestinatario = computed(
  () => atual.value?.destinatario.id === userId.value
);
const resposta = ref('');
const enviando = ref(false);

const ringtone = new Audio(RINGTONE_URL);
ringtone.loop = true;
let piscar = null;
let tituloOriginal = '';
const notificados = new Set();

const notificarSistema = chegada => {
  if (notificados.has(chegada.id)) return;
  if (!('Notification' in window) || Notification.permission !== 'granted')
    return;
  notificados.add(chegada.id);
  const chave =
    chegada.destinatario.id === userId.value
      ? 'RAMON.CHEGADA.NOTIF_CHEGOU'
      : 'RAMON.CHEGADA.NOTIF_SEM_RESPOSTA';
  // eslint-disable-next-line no-new
  new Notification(t(chave, { cliente: chegada.cliente_nome }), {
    body: chegada.motivo || '',
    requireInteraction: true,
    tag: `chegada-${chegada.id}-${chegada.estado}`,
  });
};

const pararPiscar = () => {
  if (!piscar) return;
  clearInterval(piscar);
  piscar = null;
  document.title = tituloOriginal;
};

const comecarPiscar = () => {
  if (piscar) return;
  tituloOriginal = document.title;
  piscar = setInterval(() => {
    document.title =
      document.title === tituloOriginal
        ? `🔔 ${atual.value?.cliente_nome || ''}`
        : tituloOriginal;
  }, 1000);
};

const parar = () => {
  ringtone.pause();
  ringtone.currentTime = 0;
  pararPiscar();
};

watch(
  atual,
  chegada => {
    if (!chegada) {
      parar();
      return;
    }
    resposta.value = '';
    ringtone.play().catch(() => {});
    notificarSistema(chegada);
    comecarPiscar();
  },
  { immediate: true }
);

const enviar = async () => {
  if (!resposta.value.trim() || enviando.value) return;
  enviando.value = true;
  try {
    await chegadas.responder(atual.value.id, resposta.value.trim());
  } finally {
    enviando.value = false;
  }
};

// Navegador só pede permissão com gesto do usuário: no 1º clique em qualquer
// lugar do hub, pergunta (uma vez). Vale pra todo mundo, não só a recepção.
const pedirPermissao = () => {
  if ('Notification' in window && Notification.permission === 'default')
    Notification.requestPermission();
};

onMounted(() => {
  chegadas.carregar().catch(() => {});
  document.addEventListener('click', pedirPermissao, { once: true });
});
onBeforeUnmount(() => {
  parar();
  document.removeEventListener('click', pedirPermissao);
});
</script>

<template>
  <div
    v-if="atual"
    data-testid="alerta-chegada"
    class="fixed inset-0 z-[100] flex items-center justify-center bg-n-alpha-black1 p-4 backdrop-blur-[4px]"
  >
    <div
      class="w-full max-w-md rounded-xl bg-n-solid-1 p-6 shadow-xl outline outline-1 outline-n-weak"
    >
      <p class="text-sm text-n-slate-11">
        {{
          souDestinatario
            ? t('RAMON.CHEGADA.CHEGOU', { quem: atual.criado_por.name })
            : t('RAMON.CHEGADA.SEM_RESPOSTA', { quem: atual.destinatario.name })
        }}
      </p>
      <h2 class="mt-1 text-2xl font-semibold text-n-slate-12">
        {{ atual.cliente_nome }}
      </h2>
      <p v-if="atual.motivo" class="mt-1 text-n-slate-11">{{ atual.motivo }}</p>

      <form
        v-if="souDestinatario"
        class="mt-4 flex flex-col gap-2"
        @submit.prevent="enviar"
      >
        <textarea
          v-model="resposta"
          data-testid="chegada-resposta"
          rows="2"
          autofocus
          :placeholder="t('RAMON.CHEGADA.RESPOSTA_PLACEHOLDER')"
          class="w-full rounded-lg bg-n-alpha-black2 p-2 text-n-slate-12 outline outline-1 outline-n-weak"
          @keydown.enter.exact.prevent="enviar"
        />
        <button
          type="submit"
          :disabled="!resposta.trim() || enviando"
          class="rounded-lg bg-n-brand px-4 py-2 font-medium text-white disabled:opacity-50"
        >
          {{ t('RAMON.CHEGADA.RESPONDER') }}
        </button>
      </form>
      <button
        v-else
        type="button"
        class="mt-4 w-full rounded-lg bg-n-brand px-4 py-2 font-medium text-white"
        @click="chegadas.marcarVisto(atual.id)"
      >
        {{ t('RAMON.CHEGADA.ENTENDI') }}
      </button>

      <p v-if="alertas.length > 1" class="mt-3 text-xs text-n-slate-11">
        {{ t('RAMON.CHEGADA.MAIS', { n: alertas.length - 1 }) }}
      </p>
    </div>
  </div>
</template>
```

> Classes de cor: confira que `bg-n-alpha-black1`, `bg-n-alpha-black2`, `bg-n-solid-1`, `outline-n-weak`, `bg-n-brand` existem em `tailwind.config.js` (as duas primeiras estão no `Dialog.vue`); se alguma não existir, troque pela equivalente usada em outro componente `ramon/`.

- [ ] **Step 5: Montar no Dashboard** — em `app/javascript/dashboard/routes/dashboard/Dashboard.vue`:
  - import: `import AlertaChegada from './ramon/components/equipe/AlertaChegada.vue';` (ao lado do import do `IntranetSidebar`)
  - registrar em `components: { ... AlertaChegada, }`
  - no template, logo depois de `<FloatingCallWidget v-if="hasActiveCall || hasIncomingCall" />`: `<AlertaChegada />`

- [ ] **Step 6: Run test to verify it passes** — comando do Step 3 → PASS; eslint nos arquivos tocados → limpo.

- [ ] **Step 7: Commit**

```bash
git -C <worktree> add app/javascript/dashboard/routes/dashboard/ramon/components/equipe/ app/javascript/dashboard/routes/dashboard/Dashboard.vue app/javascript/dashboard/i18n/locale/pt_BR/ramon.json app/javascript/dashboard/i18n/locale/en/ramon.json
git -C <worktree> commit -m "feat(equipe): alerta de chegada que insiste até responder"
```

---

### Task 6: `ChegouCliente.vue` — botão flutuante + painel da Recepção

**Files:**
- Create: `app/javascript/dashboard/routes/dashboard/ramon/components/equipe/ChegouCliente.vue`
- Modify: `app/javascript/dashboard/routes/dashboard/Dashboard.vue` (montar `<ChegouCliente />` ao lado do `<AlertaChegada />`)
- Test: `app/javascript/dashboard/routes/dashboard/ramon/components/equipe/specs/ChegouCliente.spec.js`

**Interfaces:**
- Consumes: `useChegadasStore` (`podeAvisar`, `itens`, `criar`), `RamonChegadasAPI.agenda()`, `ramonCalculos.advboxCustomers(q)` (`app/javascript/dashboard/api/ramonCalculos.js`, devolve `{ data: { payload: [{ id, name, identification, ... }] } }`), Vuex `agents/get` + getter `agents/getAgents`, `Dialog` de `dashboard/components-next/dialog/Dialog.vue` (ref `.open()`/`.close()`, props `title`, `confirmButtonLabel`, `disableConfirmButton`, `isLoading`, evento `confirm`).
- Produces: componente sem props; só renderiza o botão se `store.podeAvisar`.

- [ ] **Step 1: Write the failing test** — `.../equipe/specs/ChegouCliente.spec.js`

```js
import { mount, flushPromises } from '@vue/test-utils';
import { createPinia, setActivePinia } from 'pinia';
import ChegouCliente from '../ChegouCliente.vue';
import { useChegadasStore } from 'dashboard/stores/chegadas';
import ChegadasAPI from 'dashboard/api/ramonChegadas';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: vi.fn() }),
  useStoreGetters: () => ({
    'agents/getAgents': { value: [{ id: 20, name: 'Brenda' }] },
  }),
}));
vi.mock('dashboard/api/ramonChegadas', () => ({
  default: { agenda: vi.fn(), create: vi.fn() },
}));
vi.mock('dashboard/api/ramonCalculos', () => ({
  default: { advboxCustomers: vi.fn() },
}));

const DialogStub = {
  template: '<div><slot /></div>',
  methods: { open() {}, close() {} },
};

const montar = () =>
  mount(ChegouCliente, { global: { stubs: { Dialog: DialogStub } } });

describe('ChegouCliente.vue', () => {
  beforeEach(() => setActivePinia(createPinia()));

  it('some para quem não pode avisar', () => {
    const wrapper = montar();
    expect(wrapper.find('[data-testid="chegou-cliente-botao"]').exists()).toBe(
      false
    );
  });

  it('clicar em quem vem hoje preenche cliente e sugere quem atende', async () => {
    ChegadasAPI.agenda.mockResolvedValue({
      data: {
        payload: [
          {
            advbox_post_id: 5,
            cliente_nome: 'MARIA SILVA',
            advbox_customer_id: 7,
            notas: 'traz CNIS',
            responsavel_advbox: 'BRENDA',
            destinatario_id: 20,
          },
        ],
      },
    });
    useChegadasStore().podeAvisar = true;
    const wrapper = montar();
    await wrapper.find('[data-testid="chegou-cliente-botao"]').trigger('click');
    await flushPromises();
    await wrapper.find('[data-testid="agenda-item"]').trigger('click');

    expect(wrapper.find('[data-testid="chegada-nome"]').element.value).toBe(
      'MARIA SILVA'
    );
    expect(
      wrapper.find('[data-testid="chegada-destinatario"]').element.value
    ).toBe('20');
  });

  it('ADVBOX fora mostra aviso', async () => {
    ChegadasAPI.agenda.mockRejectedValue(new Error('503'));
    useChegadasStore().podeAvisar = true;
    const wrapper = montar();
    await wrapper.find('[data-testid="chegou-cliente-botao"]').trigger('click');
    await flushPromises();
    expect(wrapper.text()).toContain('RAMON.CHEGADA.ADVBOX_FORA');
  });
});
```

- [ ] **Step 2: Run test to verify it fails** — `TZ=UTC ./node_modules/.bin/vitest --no-watch .../equipe/specs/ChegouCliente.spec.js` → FAIL.

- [ ] **Step 3: Componente** — `.../equipe/ChegouCliente.vue`

```vue
<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useStoreGetters } from 'dashboard/composables/store';
import { useChegadasStore } from 'dashboard/stores/chegadas';
import ChegadasAPI from 'dashboard/api/ramonChegadas';
import RamonCalculosAPI from 'dashboard/api/ramonCalculos';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

// Painel da Recepção (Equipe · Fatia 1): escolhe o cliente (agenda do ADVBOX,
// busca ou livre) e quem vai atender; abaixo, as chegadas de hoje com estado.
const { t } = useI18n();
const store = useStore();
const getters = useStoreGetters();
const chegadas = useChegadasStore();

const dialogRef = ref(null);
const aba = ref('hoje');
const agenda = ref([]);
const advboxFora = ref(false);
const termo = ref('');
const resultados = ref([]);
const form = ref({});
const enviando = ref(false);

const agents = computed(() => getters['agents/getAgents']?.value ?? []);
const podeEnviar = computed(
  () => form.value.cliente_nome?.trim() && form.value.destinatario_id
);
const deHoje = computed(() => [...chegadas.itens].reverse());

const limpar = () => {
  form.value = { cliente_nome: '', motivo: '', destinatario_id: '' };
};

const abrir = async () => {
  limpar();
  aba.value = 'hoje';
  advboxFora.value = false;
  store.dispatch('agents/get');
  dialogRef.value?.open();
  try {
    const { data } = await ChegadasAPI.agenda();
    agenda.value = data.payload;
  } catch {
    advboxFora.value = true;
  }
};

const usarAgenda = item => {
  form.value = {
    cliente_nome: item.cliente_nome || '',
    motivo: item.notas || '',
    destinatario_id: item.destinatario_id ? String(item.destinatario_id) : '',
    advbox_customer_id: item.advbox_customer_id,
    advbox_post_id: item.advbox_post_id,
  };
  aba.value = 'livre';
};

const buscar = async () => {
  if (termo.value.trim().length < 2) return;
  try {
    const { data } = await RamonCalculosAPI.advboxCustomers(termo.value.trim());
    resultados.value = data.payload;
  } catch {
    advboxFora.value = true;
  }
};

const usarCliente = cliente => {
  form.value = {
    ...form.value,
    cliente_nome: cliente.name,
    advbox_customer_id: cliente.id,
  };
  aba.value = 'livre';
};

const avisar = async () => {
  if (!podeEnviar.value || enviando.value) return;
  enviando.value = true;
  try {
    await chegadas.criar({
      ...form.value,
      destinatario_id: Number(form.value.destinatario_id),
    });
    limpar();
  } finally {
    enviando.value = false;
  }
};

const ABAS = ['hoje', 'buscar', 'livre'];
const ROTULO_ABA = {
  hoje: 'RAMON.CHEGADA.ABA_HOJE',
  buscar: 'RAMON.CHEGADA.ABA_BUSCAR',
  livre: 'RAMON.CHEGADA.ABA_LIVRE',
};
</script>

<template>
  <template v-if="chegadas.podeAvisar">
    <button
      type="button"
      data-testid="chegou-cliente-botao"
      class="fixed bottom-4 z-50 flex items-center gap-2 rounded-full bg-n-brand px-4 py-2 font-medium text-white shadow-lg ltr:right-20 rtl:left-20"
      @click="abrir"
    >
      <span class="i-lucide-bell-ring size-4" />
      {{ t('RAMON.CHEGADA.BOTAO') }}
    </button>

    <Dialog
      ref="dialogRef"
      :title="t('RAMON.CHEGADA.TITULO')"
      :confirm-button-label="t('RAMON.CHEGADA.AVISAR')"
      :disable-confirm-button="!podeEnviar"
      :is-loading="enviando"
      @confirm="avisar"
    >
      <div class="flex flex-col gap-4">
        <div class="flex gap-2">
          <button
            v-for="nome in ABAS"
            :key="nome"
            type="button"
            class="rounded-lg px-3 py-1 text-sm"
            :class="
              aba === nome
                ? 'bg-n-alpha-2 text-n-slate-12'
                : 'text-n-slate-11'
            "
            @click="aba = nome"
          >
            {{ t(ROTULO_ABA[nome]) }}
          </button>
        </div>

        <p v-if="advboxFora" class="text-sm text-n-ruby-11">
          {{ t('RAMON.CHEGADA.ADVBOX_FORA') }}
        </p>

        <ul v-if="aba === 'hoje'" class="flex flex-col gap-1">
          <li v-if="!agenda.length && !advboxFora" class="text-sm text-n-slate-11">
            {{ t('RAMON.CHEGADA.HOJE_VAZIO') }}
          </li>
          <li v-for="item in agenda" :key="item.advbox_post_id">
            <button
              type="button"
              data-testid="agenda-item"
              class="w-full rounded-lg px-3 py-2 text-start hover:bg-n-alpha-2"
              @click="usarAgenda(item)"
            >
              <span class="font-medium text-n-slate-12">{{ item.cliente_nome }}</span>
              <span class="block text-xs text-n-slate-11">
                {{ item.responsavel_advbox }}{{ item.notas ? ` · ${item.notas}` : '' }}
              </span>
            </button>
          </li>
        </ul>

        <div v-else-if="aba === 'buscar'" class="flex flex-col gap-2">
          <input
            v-model="termo"
            :placeholder="t('RAMON.CHEGADA.BUSCAR_PLACEHOLDER')"
            class="rounded-lg bg-n-alpha-black2 px-3 py-2 text-n-slate-12"
            @keydown.enter.prevent="buscar"
          />
          <button
            v-for="cliente in resultados"
            :key="cliente.id"
            type="button"
            class="rounded-lg px-3 py-2 text-start hover:bg-n-alpha-2"
            @click="usarCliente(cliente)"
          >
            {{ cliente.name }}
          </button>
        </div>

        <div v-else class="flex flex-col gap-2">
          <input
            v-model="form.cliente_nome"
            data-testid="chegada-nome"
            :placeholder="t('RAMON.CHEGADA.NOME')"
            class="rounded-lg bg-n-alpha-black2 px-3 py-2 text-n-slate-12"
          />
          <input
            v-model="form.motivo"
            :placeholder="t('RAMON.CHEGADA.MOTIVO')"
            class="rounded-lg bg-n-alpha-black2 px-3 py-2 text-n-slate-12"
          />
        </div>

        <label class="flex flex-col gap-1 text-sm text-n-slate-11">
          {{ t('RAMON.CHEGADA.DESTINATARIO') }}
          <select
            v-model="form.destinatario_id"
            data-testid="chegada-destinatario"
            class="rounded-lg bg-n-alpha-black2 px-3 py-2 text-n-slate-12"
          >
            <option value="" disabled />
            <option v-for="agent in agents" :key="agent.id" :value="String(agent.id)">
              {{ agent.name }}
            </option>
          </select>
        </label>

        <div v-if="deHoje.length" class="flex flex-col gap-1 border-t border-n-weak pt-3">
          <p class="text-xs font-medium uppercase text-n-slate-11">
            {{ t('RAMON.CHEGADA.AGUARDANDO') }}
          </p>
          <p v-for="c in deHoje" :key="c.id" class="text-sm text-n-slate-12">
            {{ c.cliente_nome }} → {{ c.destinatario.name }} ·
            <span :class="c.estado === 'escalado' ? 'text-n-ruby-11' : 'text-n-slate-11'">
              {{ t(`RAMON.CHEGADA.ESTADO_${c.estado}`) }}
            </span>
            <span v-if="c.resposta" class="block text-n-slate-11">“{{ c.resposta }}”</span>
          </p>
        </div>
      </div>
    </Dialog>
  </template>
</template>
```

> O passo "Quem vem hoje" leva pra aba Livre já preenchida — a Gabriela confere/edita nome e motivo e confirma. 3 cliques: botão → item da agenda → Avisar.
> Posição: o botão fica à esquerda do lançador do Copilot (`right-4`); se sobrepor no smoke, ajustar o `right-*`.

- [ ] **Step 4: Montar no Dashboard** — import `ChegouCliente` (mesmo diretório), registrar em `components`, e no template logo após `<AlertaChegada />`: `<ChegouCliente />`.

- [ ] **Step 5: Run test to verify it passes** — vitest do Step 2 → PASS; eslint nos arquivos tocados → limpo (rodar também `prettier --check` se o pre-commit não rodar).

- [ ] **Step 6: Commit**

```bash
git -C <worktree> add app/javascript/dashboard/routes/dashboard/ramon/components/equipe/ app/javascript/dashboard/routes/dashboard/Dashboard.vue
git -C <worktree> commit -m "feat(equipe): botão Chegou cliente + painel da recepção"
```

---

### Task 7: PR, CI, deploy, smoke

**Files:**
- Modify (fora do repo): `C:\Users\dudsl\RAdvogados\comercial\docs\2026-09-14-smoke-consolidado.md` (nova seção "G — Chegada de cliente")
- Modify (memória): `equipe-chegada-chat-hub.md` + `ramon-hub-plano-mestre-e-frentes.md`

- [ ] **Step 1: Review final adversarial** da branch inteira no modelo mais capaz (lição permanente do hub — pegou bug real em todas as ondas).
- [ ] **Step 2: Push + PR** — `git push -u origin feat/equipe` (classificador costuma barrar → Eduardo roda via `!`). `gh pr create --base ramon --title "feat(equipe): chegada de cliente com alerta que insiste"`; corpo: parágrafo de produto + "How to test" (recepção avisa → destinatário vê overlay/toque → responde → recepção vê a resposta; deixar sem resposta 3 min → recepção é alertada).
- [ ] **Step 3: CI verde** (rubocop costuma pedir decomposição — corrigir e repush). Não mergear vermelho.
- [ ] **Step 4: Merge (squash) + deploy autônomo** na VPS conforme regime do hub (pull da imagem, `db:migrate` À MÃO — entrypoint não roda migração —, `up`), conferir label = squash, `/app/login` 200.
- [ ] **Step 5: Smoke** — seção nova no consolidado (bloco inteiro, não passo a passo em formulário):
  1. Gate: Gabriela no time `recepção` com login; Brenda com login.
  2. Brenda: hub aberto em OUTRA aba; Gabriela: "Chegou cliente" → Livre → "Teste" → Brenda → Avisar.
  3. Brenda: notificação do Windows aparece, aba pisca, toque toca; ao voltar, overlay; responder "já vou" → para tudo.
  4. Gabriela: no painel, "Teste → Brenda · respondeu “já vou”".
  5. Repetir sem responder: em 3 min, Gabriela recebe "Brenda não respondeu"; Entendi fecha.
  6. Brenda com alerta aberto aperta F5 → alerta volta.
  7. Aba "Quem vem hoje" num dia com tarefa ATENDIMENTO no ADVBOX → cliente e responsável sugeridos.
- [ ] **Step 6: Memória** — atualizar `equipe-chegada-chat-hub.md` (PR, squash, VPS, smoke pendente) e a linha do plano mestre.
