# Cálculos a partir do AdvBox — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tela Cálculos ganha busca de cadastro no AdvBox e cria "caso de cálculo" oculto (lead `source: 'calculo-advbox'`) que não aparece nas superfícies comerciais; contato do hub sem lead ganha botão "Criar caso de cálculo".

**Architecture:** Um scope NULL-safe `Lead.funil` exclui o caso de cálculo; `Lead.open` passa a encadeá-lo (conserta os 7 pontos de adoção de lead de uma vez). Controller novo `RamonCalculosController` com proxy de busca AdvBox + criação do caso via `Ramon::CalculoCasoService` (dedup contato por CPF → telefone → cria). Front só toca `Calculos.vue` + API module novo.

**Tech Stack:** Rails (fork Chatwoot v4.15.1), Vue 3 `<script setup>`, RSpec (roda SÓ no CI), Vitest (roda local: `npx vitest run app/javascript/dashboard/routes/dashboard/ramon`), WebMock.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-20-calculos-advbox-design.md`.
- Sem migração de banco (usa coluna `leads.source` existente).
- Sem teste Ruby local (Windows) — RSpec valida no CI; escrever specs mesmo assim.
- i18n: NO fork mantemos `pt_BR/ramon.json` **e** `en/ramon.json` (par obrigatório).
- Evento Vue custom camelCase; página/edits Tailwind only; commits Conventional Commits sem mencionar Claude; push com `--no-verify` (worktree sem husky).
- Rubocop: `ENV.fetch`, máx 150 chars/linha, `.exists?(cond)` direto (Rails/WhereExists).
- `Lead` tem `default_scope { order(...) }` — specs que contam usam `reorder(nil)` quando agregam.
- `create(:account)` seeda o funil (etapas já existem; nunca criar etapa com nome seedado).

---

### Task 1: Scopes `funil`/`open` no Lead

**Files:**
- Modify: `app/models/lead.rb:19-23`
- Test: `spec/models/lead_spec.rb` (adicionar contexto)

**Interfaces:**
- Produces: `Lead::FONTE_CALCULO = 'calculo-advbox'`, `Lead.funil` (relation), `Lead.open` (agora exclui caso de cálculo). Tasks 2–4 consomem.

- [ ] **Step 1: Failing spec** — em `spec/models/lead_spec.rb`, dentro do describe existente:

```ruby
describe 'scopes de funil' do
  let(:account) { create(:account) }
  let(:stage) { account.lead_stages.order(:position).first }
  let!(:lead_normal) { create(:lead, account: account, lead_stage: stage, source: nil) }
  let!(:lead_lp) { create(:lead, account: account, lead_stage: stage, source: 'lp-auxilio-acidente') }
  let!(:caso_calculo) { create(:lead, account: account, lead_stage: stage, source: Lead::FONTE_CALCULO) }

  it 'funil exclui caso de cálculo e mantém source NULL (IS DISTINCT FROM)' do
    expect(account.leads.funil).to contain_exactly(lead_normal, lead_lp)
  end

  it 'open não adota caso de cálculo como lead vivo' do
    expect(account.leads.open).not_to include(caso_calculo)
    expect(account.leads.open).to include(lead_normal)
  end
end
```

- [ ] **Step 2: Implementar** — em `app/models/lead.rb`, logo antes do `scope :open`:

```ruby
  # Caso de cálculo (tela Cálculos ← AdvBox): vive fora do funil comercial.
  FONTE_CALCULO = 'calculo-advbox'.freeze

  # NULL-safe: where.not(source:) excluiria os leads com source NULL junto.
  scope :funil, -> { where('leads.source IS DISTINCT FROM ?', FONTE_CALCULO) }
```

e trocar o `scope :open` por (mesma semântica + funil — "vivo NO FUNIL"; os 7
chamadores de adoção/dedup ficam corrigidos aqui):

```ruby
  scope :open, -> { funil.joins(:lead_stage).where(lead_stages: { is_won: false, is_lost: false }) }
```

- [ ] **Step 3: Commit** — `git add -- app/models/lead.rb spec/models/lead_spec.rb && git commit --no-verify -m "feat(ramon): scope funil no Lead e open restrito ao funil"`

---

### Task 2: Superfícies comerciais usam `.funil`

**Files:**
- Modify: `app/controllers/api/v1/accounts/leads_controller.rb:76-82` (`filtered_leads`)
- Modify: `app/controllers/api/v1/accounts/ramon_dashboard_controller.rb` (linhas 63-64, 84-86, 92, 99 — todo `Current.account.leads.` de agregação vira `Current.account.leads.funil.`)
- Modify: `app/services/ramon/funnel_snapshot_service.rb:23-24` (`@account.leads.funil.reorder(nil)...`)
- Modify: `app/services/ramon/lead_radar.rb:6-19` (`account.leads.funil.joins(...)` em `active_leads` e `account.leads.funil.includes(...)` em `new_from_lp_leads`)
- Modify: `app/services/search_service.rb:182` (`current_account.leads.funil.left_joins(:contact)...`)
- Test: `spec/controllers/api/v1/accounts/leads_controller_spec.rb` (index), `spec/controllers/api/v1/accounts/ramon_dashboard_controller_spec.rb`

**Interfaces:**
- Consumes: `Lead.funil` (Task 1).
- Produces: leads#index continua devolvendo caso de cálculo QUANDO `contact_id` presente (Cálculos/gaveta dependem disso).

- [ ] **Step 1: Failing specs**

`leads_controller_spec.rb` (no describe do index):

```ruby
context 'com caso de cálculo' do
  let!(:caso) do
    create(:lead, account: account, lead_stage: account.lead_stages.order(:position).first,
                  source: Lead::FONTE_CALCULO, contact: contact)
  end

  it 'não aparece no board (sem contact_id)' do
    get "/api/v1/accounts/#{account.id}/leads", headers: agent.create_new_auth_token, as: :json
    ids = response.parsed_body['payload'].pluck('id')
    expect(ids).not_to include(caso.id)
  end

  it 'aparece na visão por pessoa (contact_id)' do
    get "/api/v1/accounts/#{account.id}/leads", params: { contact_id: contact.id },
        headers: agent.create_new_auth_token, as: :json
    expect(response.parsed_body['payload'].pluck('id')).to include(caso.id)
  end
end
```

`ramon_dashboard_controller_spec.rb`: no exemplo existente de contagem do funil,
criar também um caso de cálculo e afirmar que ele não entra em `leads_count`.
(Seguir a estrutura dos exemplos já existentes do arquivo.)

- [ ] **Step 2: Implementar** — `filtered_leads`:

```ruby
  def filtered_leads
    leads = policy_scope(Current.account.leads)
    # Caso de cálculo só aparece nas visões por pessoa (Cálculos, gaveta, Linha da Vida).
    leads = leads.funil if params[:contact_id].blank?
    leads = apply_equality_filters(leads)
    leads = leads.where('sdr_id = :a OR closer_id = :a', a: params[:agent_id]) if params[:agent_id].present?
    leads = apply_cadence_filters(apply_period_filters(leads))
    leads = search_leads(leads, params[:q]) if params[:q].present?
    leads
  end
```

Demais arquivos: inserir `.funil` conforme lista de Files acima (mudança de 1 token
por query; `no_next_action_leads` e `stalled_leads` herdam de `active_leads`).

- [ ] **Step 3: Commit** — `git commit --no-verify -m "feat(ramon): superficies comerciais ignoram caso de calculo"`

---

### Task 3: `Ramon::CalculoCasoService`

**Files:**
- Create: `app/services/ramon/calculo_caso_service.rb`
- Test: `spec/services/ramon/calculo_caso_service_spec.rb`

**Interfaces:**
- Consumes: `Lead::FONTE_CALCULO`; concern `RamonPessoa` do Contact (cpf normalizado p/ dígitos + validação de dígito verificador; update com cpf inválido FALHA → retry sem cpf, padrão colheita).
- Produces: `Ramon::CalculoCasoService.new(account:, params:).perform` → `{ contact: Contact, leads: [Lead] }`. `params` (hash com chaves string ou symbol): ou `contact_id`, ou dados AdvBox `{ nome:, cpf:, telefone:, nascimento:, email: }` (todos opcionais menos nome).

- [ ] **Step 1: Failing spec**

```ruby
require 'rails_helper'

RSpec.describe Ramon::CalculoCasoService do
  let(:account) { create(:account) }
  let(:stage) { account.lead_stages.order(:position).first }

  def perform(params)
    described_class.new(account: account, params: params).perform
  end

  it 'reusa contato por CPF e devolve leads existentes sem criar caso' do
    contact = create(:contact, account: account, cpf: '52998224725')
    lead = create(:lead, account: account, lead_stage: stage, contact: contact)
    result = perform(nome: 'Fulano', cpf: '529.982.247-25')
    expect(result[:contact]).to eq(contact)
    expect(result[:leads]).to contain_exactly(lead)
    expect(account.leads.reorder(nil).count).to eq(1)
  end

  it 'reusa contato por telefone quando não há CPF' do
    contact = create(:contact, account: account, phone_number: '+5548999887766')
    result = perform(nome: 'Fulano', telefone: '(48) 99988-7766')
    expect(result[:contact]).to eq(contact)
  end

  it 'cria contato + caso de cálculo oculto quando pessoa não existe' do
    result = perform(nome: 'Nova Pessoa', cpf: '529.982.247-25', nascimento: '1980-05-10')
    contact = result[:contact]
    expect(contact.cpf).to eq('52998224725')
    expect(contact.data_nascimento).to eq(Date.new(1980, 5, 10))
    caso = result[:leads].sole
    expect(caso.source).to eq(Lead::FONTE_CALCULO)
    expect(caso.lead_stage).to eq(stage)
    expect(account.leads.funil).not_to include(caso)
  end

  it 'CPF inválido não derruba: cria contato sem CPF' do
    result = perform(nome: 'Nova Pessoa', cpf: '111.111.111-11')
    expect(result[:contact].cpf).to be_nil
    expect(result[:leads].sole.source).to eq(Lead::FONTE_CALCULO)
  end

  it 'preenche só campo vazio de contato reusado (não sobrescreve)' do
    contact = create(:contact, account: account, cpf: '52998224725',
                              data_nascimento: Date.new(1970, 1, 1))
    perform(nome: 'Outro Nome', cpf: '52998224725', nascimento: '1980-05-10')
    expect(contact.reload.data_nascimento).to eq(Date.new(1970, 1, 1))
    expect(contact.name).not_to eq('Outro Nome')
  end

  it 'com contact_id cria caso pro contato do hub sem lead' do
    contact = create(:contact, account: account)
    result = perform(contact_id: contact.id)
    expect(result[:contact]).to eq(contact)
    expect(result[:leads].sole.source).to eq(Lead::FONTE_CALCULO)
  end
end
```

- [ ] **Step 2: Implementar**

```ruby
# Caso de cálculo (tela Cálculos): resolve a pessoa (cadastro AdvBox ou contato
# do hub) e garante um lead pra pendurar CNIS/simulações. Se a pessoa já tem
# lead — comercial ou não — o cálculo vive nele; senão nasce um caso oculto
# (source calculo-advbox, fora do funil).
class Ramon::CalculoCasoService
  def initialize(account:, params:)
    @account = account
    @params = params.to_h.symbolize_keys
  end

  def perform
    contact = resolve_contact
    leads = @account.leads.where(contact_id: contact.id).to_a
    leads = [criar_caso(contact)] if leads.empty?
    { contact: contact, leads: leads }
  end

  private

  def resolve_contact
    return @account.contacts.find(@params[:contact_id]) if @params[:contact_id].present?

    contact = find_by_cpf || find_by_phone
    contact ? fill_blanks(contact) : create_contact
  end

  def cpf_digits
    @cpf_digits ||= @params[:cpf].to_s.gsub(/\D/, '').presence
  end

  def phone_e164
    digits = @params[:telefone].to_s.gsub(/\D/, '')
    digits = "55#{digits}" if [10, 11].include?(digits.length)
    return unless [12, 13].include?(digits.length) && digits.start_with?('55')

    "+#{digits}"
  end

  def find_by_cpf
    cpf_digits && @account.contacts.find_by(cpf: cpf_digits)
  end

  def find_by_phone
    phone_e164 && @account.contacts.find_by(phone_number: phone_e164)
  end

  def nascimento
    Date.iso8601(@params[:nascimento].to_s)
  rescue Date::Error
    nil
  end

  # Dado humano nunca é sobrescrito (padrão fill_contact_blanks da colheita).
  def fill_blanks(contact)
    updates = {}
    updates[:cpf] = cpf_digits if contact.cpf.blank? && cpf_digits
    updates[:data_nascimento] = nascimento if contact.data_nascimento.blank? && nascimento
    save_tolerando_cpf(contact, updates)
    contact
  end

  def create_contact
    contact = @account.contacts.new(
      name: @params[:nome].to_s.strip.presence || 'Sem nome',
      cpf: cpf_digits, phone_number: phone_e164,
      email: @params[:email].presence, data_nascimento: nascimento
    )
    return contact if contact.save

    # CPF inválido/duplicado não derruba o fluxo: tenta sem ele.
    contact.cpf = nil
    contact.save!
    contact
  end

  def save_tolerando_cpf(contact, updates)
    return if updates.empty? || contact.update(updates)

    updates.delete(:cpf)
    contact.reload.update(updates) if updates.any?
  end

  def criar_caso(contact)
    @account.leads.create!(
      contact: contact,
      lead_stage: @account.lead_stages.order(:position).first,
      name: contact.name,
      source: Lead::FONTE_CALCULO
    )
  end
end
```

- [ ] **Step 3: Commit** — `git commit --no-verify -m "feat(ramon): CalculoCasoService cria caso de calculo p/ pessoa do advbox ou contato sem lead"`

---

### Task 4: Controller + policy + rotas

**Files:**
- Create: `app/controllers/api/v1/accounts/ramon_calculos_controller.rb`
- Create: `app/policies/ramon_calculos_policy.rb`
- Modify: `config/routes.rb:289-294` (junto dos irmãos ramon_*)
- Test: `spec/controllers/api/v1/accounts/ramon_calculos_controller_spec.rb`

**Interfaces:**
- Consumes: `Ramon::AdvboxClient.customers(name:|identification:, limit:)` (raise `UnavailableError`/`RequestError`), `Ramon::CalculoCasoService` (Task 3).
- Produces (front, Task 5):
  - `GET /api/v1/accounts/:account_id/ramon_calculos/advbox_customers?q=` → `{ payload: [{ id, name, identification, cellphone, birthdate, email }] }`; 503 `{ error: 'ADVBOX_UNAVAILABLE' }` quando o AdvBox falhar.
  - `POST /api/v1/accounts/:account_id/ramon_calculos/criar_caso` body `{ contact_id }` OU `{ nome, cpf, telefone, nascimento, email }` → `{ contact: { id, name }, leads: [push_event_data] }`.

- [ ] **Step 1: Failing spec**

```ruby
require 'rails_helper'

RSpec.describe 'Ramon Calculos API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }

  describe 'GET /advbox_customers' do
    let(:url) { "/api/v1/accounts/#{account.id}/ramon_calculos/advbox_customers" }

    it 'exige login' do
      get url, params: { q: 'Silva' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'busca por nome e devolve payload enxuto' do
      stub = stub_request(:get, %r{advbox.*\/customers})
             .with(query: hash_including('name' => 'Silva'))
             .to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                        body: { data: [{ 'id' => 9, 'name' => 'João Silva', 'identification' => '52998224725',
                                         'cellphone' => '48999887766', 'birthdate' => '1980-05-10',
                                         'protocol_number' => 'x' }] }.to_json)
      get url, params: { q: 'Silva' }, headers: agent.create_new_auth_token, as: :json
      expect(stub).to have_been_requested
      item = response.parsed_body['payload'].sole
      expect(item).to eq('id' => 9, 'name' => 'João Silva', 'identification' => '52998224725',
                         'cellphone' => '48999887766', 'birthdate' => '1980-05-10', 'email' => nil)
    end

    it 'q com 11 dígitos vira busca por CPF (identification)' do
      stub = stub_request(:get, %r{advbox.*\/customers})
             .with(query: hash_including('identification' => '52998224725'))
             .to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: { data: [] }.to_json)
      get url, params: { q: '529.982.247-25' }, headers: agent.create_new_auth_token, as: :json
      expect(stub).to have_been_requested
    end

    it 'AdvBox fora do ar vira 503 com erro nomeado' do
      stub_request(:get, %r{advbox.*\/customers}).to_timeout
      get url, params: { q: 'Silva' }, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:service_unavailable)
      expect(response.parsed_body['error']).to eq('ADVBOX_UNAVAILABLE')
    end
  end

  describe 'POST /criar_caso' do
    let(:url) { "/api/v1/accounts/#{account.id}/ramon_calculos/criar_caso" }

    it 'cria caso a partir de dados do AdvBox e devolve o lead' do
      post url, params: { nome: 'João Silva', cpf: '529.982.247-25' },
                headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      lead = response.parsed_body['leads'].sole
      expect(lead['source']).to eq(Lead::FONTE_CALCULO)
      expect(response.parsed_body.dig('contact', 'name')).to eq('João Silva')
    end
  end
end
```

(Requisitos do ambiente de spec: `ADVBOX_API_TOKEN` — usar `with_modified_env ADVBOX_API_TOKEN: 'test-token'` se o client exigir; conferir como `advbox_closing_service_spec` stub o host e copiar o padrão de URL.)

- [ ] **Step 2: Implementar**

`app/policies/ramon_calculos_policy.rb`:

```ruby
class RamonCalculosPolicy < ApplicationPolicy
  def advbox_customers?
    @account_user.administrator? || @account_user.agent?
  end

  def criar_caso?
    advbox_customers?
  end
end
```

`config/routes.rb` (junto de `ramon_esteira`):

```ruby
          resource :ramon_calculos, only: [], controller: 'ramon_calculos' do
            get :advbox_customers
            post :criar_caso
          end
```

`app/controllers/api/v1/accounts/ramon_calculos_controller.rb`:

```ruby
class Api::V1::Accounts::RamonCalculosController < Api::V1::Accounts::BaseController
  # Cadastro AdvBox → caso de cálculo (spec 2026-07-20-calculos-advbox-design).
  LIMIT = 15
  CAMPOS = %w[id name identification cellphone birthdate email].freeze

  before_action :current_account
  before_action :check_authorization

  # Proxy da busca de clientes do AdvBox — 1 chamada por clique (teto 500/dia lá).
  def advbox_customers
    render json: { payload: advbox_list.map { |c| CAMPOS.index_with { |campo| c[campo] } } }
  rescue Ramon::AdvboxClient::UnavailableError, Ramon::AdvboxClient::RequestError
    render json: { error: 'ADVBOX_UNAVAILABLE' }, status: :service_unavailable
  end

  def criar_caso
    result = Ramon::CalculoCasoService.new(account: Current.account, params: caso_params).perform
    render json: {
      contact: result[:contact].slice(:id, :name),
      leads: result[:leads].map(&:push_event_data)
    }
  end

  private

  def advbox_list
    q = params[:q].to_s.strip
    digits = q.gsub(/\D/, '')
    filtro = digits.length == 11 ? { identification: digits } : { name: q }
    resposta = Ramon::AdvboxClient.customers(filtro.merge(limit: LIMIT))
    resposta.is_a?(Hash) ? Array(resposta['data']) : Array(resposta)
  end

  def caso_params
    params.permit(:contact_id, :nome, :cpf, :telefone, :nascimento, :email)
  end

  def check_authorization
    authorize(:ramon_calculos, :"#{action_name}?")
  end
end
```

- [ ] **Step 3: Commit** — `git commit --no-verify -m "feat(ramon): endpoints de busca advbox e criar caso de calculo"`

---

### Task 5: Front — `Calculos.vue` + API module + i18n + vitest

**Files:**
- Create: `app/javascript/dashboard/api/ramonCalculos.js`
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/pages/Calculos.vue`
- Modify: `app/javascript/dashboard/i18n/locale/pt_BR/ramon.json` e `.../en/ramon.json` (bloco `RAMON.CALCULOS`)
- Test: `app/javascript/dashboard/routes/dashboard/ramon/pages/specs/Calculos.spec.js`

**Interfaces:**
- Consumes: endpoints da Task 4.
- Produces: UX final — botão "Buscar no AdvBox" (sob demanda), lista de cadastros, clique cria/resolve caso e navega; botão "Criar caso de cálculo" no vazio.

- [ ] **Step 1: API module**

```js
/* global axios */
import ApiClient from './ApiClient';

class RamonCalculosAPI extends ApiClient {
  constructor() {
    super('ramon_calculos', { accountScoped: true });
  }

  advboxCustomers(q) {
    return axios.get(`${this.url}/advbox_customers`, { params: { q } });
  }

  criarCaso(payload) {
    return axios.post(`${this.url}/criar_caso`, payload);
  }
}

export default new RamonCalculosAPI();
```

- [ ] **Step 2: Failing vitest** — adicionar ao `Calculos.spec.js` (seguir setup/mocks existentes do arquivo; mockar `dashboard/api/ramonCalculos`):

```js
it('busca no AdvBox só sob demanda e lista cadastros', async () => {
  // digitar termo >=2 → botão advbox-search visível; API advbox NÃO chamada ainda
  // clique → advboxCustomers chamado 1x com o termo; resultados advbox-result renderizados
});

it('escolher cadastro AdvBox cria caso e navega pro lead', async () => {
  // criarCaso resolve { contact, leads: [{ id: 7 }] } → router.push ramon_calculos_lead leadId 7
});

it('contato do hub sem lead mostra botão criar caso', async () => {
  // estado EMPTY_NO_LEAD → botão create-case → criarCaso({ contact_id }) → push
});

it('erro do AdvBox mostra mensagem com retry', async () => {
  // advboxCustomers rejeita → advbox-error visível; retry re-chama
});
```

(Os testes concretos devem seguir os helpers do arquivo — ele já monta o componente
com router mock e i18n; replicar o estilo dos 11 specs existentes.)

- [ ] **Step 3: `Calculos.vue`** — mudanças no `<script setup>`:

```js
import RamonCalculosAPI from 'dashboard/api/ramonCalculos';

const advboxResults = ref([]);
const advboxSearching = ref(false);
const advboxError = ref(false);
const advboxSearched = ref(false);
const creating = ref(false);
const createError = ref(false);
```

No watcher de `query` (junto da limpeza existente): `advboxResults.value = []; advboxError.value = false; advboxSearched.value = false;`

```js
const searchAdvbox = async () => {
  advboxSearching.value = true;
  advboxError.value = false;
  try {
    const { data } = await RamonCalculosAPI.advboxCustomers(query.value.trim());
    advboxResults.value = data.payload || [];
    advboxSearched.value = true;
  } catch {
    advboxError.value = true;
  } finally {
    advboxSearching.value = false;
  }
};

const goToLeads = (contact, leads) => {
  if (leads.length === 1) {
    router.push({ name: 'ramon_calculos_lead', params: { leadId: leads[0].id } });
  } else {
    selectedContact.value = contact;
    contactLeads.value = leads;
  }
};

const criarCaso = async payload => {
  if (creating.value) return;
  creating.value = true;
  createError.value = false;
  try {
    const { data } = await RamonCalculosAPI.criarCaso(payload);
    goToLeads(data.contact, data.leads);
  } catch {
    createError.value = true;
  } finally {
    creating.value = false;
  }
};

const openAdvboxCustomer = c =>
  criarCaso({
    nome: c.name, cpf: c.identification, telefone: c.cellphone,
    nascimento: c.birthdate, email: c.email,
  });

const criarCasoParaContato = () => criarCaso({ contact_id: selectedContact.value.id });
```

Template (abaixo da lista/empty do hub, dentro do `max-w-xl`):

```html
<template v-if="query.trim().length >= 2">
  <button
    v-if="!advboxSearching"
    data-testid="advbox-search"
    class="mt-4 text-sm text-n-iris-11 hover:underline"
    @click="searchAdvbox"
  >
    {{ $t('RAMON.CALCULOS.ADVBOX_SEARCH') }}
  </button>
  <p v-else class="mt-4 text-sm text-n-slate-10">
    {{ $t('RAMON.CALCULOS.SEARCHING') }}
  </p>
  <p v-if="advboxError" class="mt-2 text-sm text-n-ruby-11" data-testid="advbox-error">
    {{ $t('RAMON.CALCULOS.ADVBOX_ERROR') }}
  </p>
  <template v-if="advboxSearched">
    <p class="mt-4 text-xs font-medium uppercase text-n-slate-10">
      {{ $t('RAMON.CALCULOS.ADVBOX_TITLE') }}
    </p>
    <ul v-if="advboxResults.length" class="mt-2 rounded-lg border border-n-weak divide-y divide-n-weak">
      <li v-for="c in advboxResults" :key="c.id">
        <button
          data-testid="advbox-result"
          :disabled="creating"
          class="flex items-center justify-between w-full gap-3 px-3 py-2 text-left hover:bg-n-alpha-2 disabled:opacity-50"
          @click="openAdvboxCustomer(c)"
        >
          <span class="text-sm truncate text-n-slate-12">{{ c.name }}</span>
          <span class="text-xs shrink-0 text-n-slate-10">{{ c.identification || c.cellphone || '' }}</span>
        </button>
      </li>
    </ul>
    <p v-else class="mt-2 text-sm text-n-slate-10" data-testid="advbox-empty">
      {{ $t('RAMON.CALCULOS.ADVBOX_EMPTY') }}
    </p>
  </template>
</template>
<p v-if="createError" class="mt-2 text-sm text-n-ruby-11" data-testid="create-error">
  {{ $t('RAMON.CALCULOS.CREATE_ERROR') }}
</p>
```

E no bloco `EMPTY_NO_LEAD` (trocar o `<p v-else ...>` por um bloco com o botão):

```html
<div v-else class="mt-4" data-testid="calculos-empty">
  <p class="text-sm text-n-slate-10">
    {{ $t('RAMON.CALCULOS.EMPTY_NO_LEAD', { name: selectedContact.name }) }}
  </p>
  <button
    data-testid="create-case"
    :disabled="creating"
    class="mt-2 text-sm text-n-iris-11 hover:underline disabled:opacity-50"
    @click="criarCasoParaContato"
  >
    {{ $t('RAMON.CALCULOS.CREATE_CASE') }}
  </button>
</div>
```

- [ ] **Step 4: i18n** — `pt_BR/ramon.json`, bloco `CALCULOS` (e chaves equivalentes em `en/ramon.json`):

```json
"ADVBOX_SEARCH": "Buscar no AdvBox",
"ADVBOX_TITLE": "No AdvBox",
"ADVBOX_EMPTY": "Nenhum cadastro no AdvBox com esse termo.",
"ADVBOX_ERROR": "Não deu pra consultar o AdvBox agora. Tente de novo.",
"CREATE_CASE": "Criar caso de cálculo",
"CREATE_ERROR": "Não deu pra criar o caso de cálculo. Tente de novo."
```

en: `"ADVBOX_SEARCH": "Search AdvBox"`, `"ADVBOX_TITLE": "In AdvBox"`, `"ADVBOX_EMPTY": "No AdvBox record matches."`, `"ADVBOX_ERROR": "Could not reach AdvBox. Try again."`, `"CREATE_CASE": "Create calculation case"`, `"CREATE_ERROR": "Could not create the calculation case. Try again."`

- [ ] **Step 5: Rodar local** — `npx vitest run app/javascript/dashboard/routes/dashboard/ramon` (tudo verde) e `npx eslint app/javascript/dashboard/routes/dashboard/ramon/pages/Calculos.vue app/javascript/dashboard/api/ramonCalculos.js` (ignorar `Delete ␍` de CRLF).

- [ ] **Step 6: Commit** — `git commit --no-verify -m "feat(ramon): busca advbox e criar caso de calculo na tela Calculos"`

---

### Task 6: Prettier + push + PR

- [ ] `npx prettier --write` nos arquivos JS/Vue/json tocados (CI barra sem isso).
- [ ] `npx vitest run app/javascript/dashboard/routes/dashboard/ramon` de novo (prettier não quebrou nada).
- [ ] Push `--no-verify`, `gh pr create --base ramon --title "feat(ramon): calculos a partir de cadastro do AdvBox" --body-file <arquivo>` (aspas em here-string PS quebram — usar arquivo).
- [ ] CI: `gh pr view N --json statusCheckRollup` — exigir ≥20 checks completos, zero não-success ("test" SKIPPED é normal).

## Self-review

- Spec coberto: busca sob demanda (T4/T5), caso oculto + NULL-safe (T1), superfícies (T2), adoção/open (T1), dedup contato + extra contato-sem-lead (T3/T5), i18n, erros visíveis (T5). Metabase = ressalva de doc, sem task (correto).
- Sem placeholders de código nos passos Ruby; vitest da T5 descreve casos e manda seguir os helpers do arquivo existente (padrão da suíte, não placeholder de comportamento).
- Tipos/nomes consistentes: `FONTE_CALCULO`, `funil`, contrato `{ contact, leads }`, rotas `ramon_calculos/*`.
