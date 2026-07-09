# Import CSV de Leads (item 4c-22) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tela simples de import CSV que cria/atualiza pessoas (Contact: nome, telefone, email, CPF, nascimento, sexo) e opcionalmente casos (Lead: benefício, tese, etapa, valor, ganho) em massa — pré-requisito da Base 10.000 do AdvBox e útil pra planilhas avulsas.

**Architecture:** Reusa a infra nativa de import (`DataImport` + ActiveStorage + `failed_records`): o model passa a aceitar `data_type: 'leads'` e o `DataImportJob` ganha um branch de 1 linha que delega ao serviço novo `Ramon::LeadsCsvImport` (parse linha a linha, match de pessoa por CPF → telefone → email, caso opcional por linha, linhas ruins vão pro CSV de rejeitados). Endpoint + botão no FunilConfig (admin).

**Tech Stack:** Rails 7.1 (fork Chatwoot v4.15.1), Vue 3 `<script setup>`, RSpec.

**Contexto de branch:** stacked sobre `feat/ramon-linha-da-vida` (usa `contacts.cpf`/`data_nascimento`/`sexo` e a normalização/validação de CPF da Task 1 daquela branch). PR base `ramon`, corpo avisa "mergear após o PR da Linha da Vida".

## Global Constraints

- Sem ambiente local: **PR + CI validam**. Não rodar bundle/rspec/rake. Commits/push com `--no-verify`.
- SEM migração nesta feature (tabela `data_imports` já existe) — schema.rb não muda.
- Rubocop: 150 chars/linha; RSpec máx 7 expectations/exemplo.
- `create(:account)` seeda funil (Novo…Fechado/Perdido), benefícios e 5 teses — specs usam os nomes seedados via `find_by`, nunca criam etapa com nome seedado.
- `Lead` tem default_scope — usar `reorder(:id).last` em specs.
- Colunas do CSV (contrato do template, tudo em pt): `nome,telefone,email,cpf,data_nascimento,sexo,beneficio,tese,etapa,valor,ganho_em,canal,origem`.
- Matching de pessoa: **cpf → telefone → email** (primeira chave presente que encontrar). Campos do contato existente: só preenche os VAZIOS (nunca sobrescreve).
- Cria Lead SÓ se a linha tiver alguma coluna de caso (`beneficio`,`tese`,`etapa`,`valor`,`ganho_em`).
- `beneficio`/`tese`/`etapa` com nome não encontrado na conta → linha inteira vai pro failed_records com motivo (erro visível > dado silencioso).
- Idempotência de re-run: não duplica contato (match) nem caso (skip se o contato já tem lead com o mesmo `benefit_type_id` e mesmo `won_at`; para casos abertos, skip se já existe lead **aberto** do contato com o mesmo `benefit_type_id`).
- Datas aceitas: `dd/mm/aaaa` e `aaaa-mm-dd`. Telefone: 10-11 dígitos → prefixa +55; 12-13 dígitos começando com 55 → prefixa +. Inválido não-vazio → failed.
- i18n frontend: `en/ramon.json` E `pt_BR/ramon.json`.

---

### Task 1: Serviço Ramon::LeadsCsvImport

**Files:**
- Create: `app/services/ramon/leads_csv_import.rb`
- Test (create): `spec/services/ramon/leads_csv_import_spec.rb`

**Interfaces:**
- Consumes: `DataImport` (status enum, `import_file`/`failed_records` attachments, `total_records`/`processed_records`); colunas `contacts.cpf/data_nascimento/sexo` (branch base); `Lead.open` (branch base).
- Produces: `Ramon::LeadsCsvImport.new(data_import).perform` — processa o CSV, atualiza status/contadores e anexa `failed_records` quando houver rejeição. Task 2 chama isso do job.

- [ ] **Step 1: Escrever os testes que falham**

Criar `spec/services/ramon/leads_csv_import_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe Ramon::LeadsCsvImport do
  let(:account) { create(:account) }

  def run_import(csv)
    import = account.data_imports.new(data_type: 'leads')
    import.import_file.attach(io: StringIO.new(csv), filename: 'leads.csv', content_type: 'text/csv')
    import.save!(validate: false)
    described_class.new(import).perform
    import.reload
  end

  it 'cria pessoa nova com cpf normalizado, nascimento e sexo' do
    import = run_import(<<~CSV)
      nome,telefone,email,cpf,data_nascimento,sexo,beneficio,tese,etapa,valor,ganho_em,canal,origem
      Maria Silva,48 99999-0000,,529.982.247-25,15/03/1970,F,,,,,,,
    CSV
    contact = account.contacts.find_by(cpf: '52998224725')
    expect(contact.name).to eq('Maria Silva')
    expect(contact.phone_number).to eq('+5548999990000')
    expect(contact.data_nascimento).to eq(Date.new(1970, 3, 15))
    expect(contact.sexo).to eq('F')
    expect(import.status).to eq('completed')
    expect(account.leads.where(contact_id: contact.id)).to be_empty
  end

  it 'faz match por cpf e só preenche campos vazios do contato' do
    existente = create(:contact, account: account, name: 'Maria', cpf: '52998224725')
    run_import(<<~CSV)
      nome,telefone,email,cpf,data_nascimento,sexo,beneficio,tese,etapa,valor,ganho_em,canal,origem
      Outro Nome,,,52998224725,1970-03-15,F,,,,,,,
    CSV
    existente.reload
    expect(existente.name).to eq('Maria')
    expect(existente.data_nascimento).to eq(Date.new(1970, 3, 15))
    expect(account.contacts.where(cpf: '52998224725').count).to eq(1)
  end

  it 'cria caso ganho com won_at na data do ganho' do
    run_import(<<~CSV)
      nome,telefone,email,cpf,data_nascimento,sexo,beneficio,tese,etapa,valor,ganho_em,canal,origem
      João,4899990001,,,,M,Auxílio-acidente,,,"1500,00",10/01/2024,,advbox
    CSV
    lead = account.leads.reorder(:id).last
    expect(lead.lead_stage.is_won).to be(true)
    expect(lead.won_at.to_date).to eq(Date.new(2024, 1, 10))
    expect(lead.benefit_type.name).to eq('Auxílio-acidente')
    expect(lead.value).to eq(1500)
    expect(lead.source).to eq('advbox')
  end

  it 'cria caso aberto na primeira etapa quando etapa não informada' do
    run_import(<<~CSV)
      nome,telefone,email,cpf,data_nascimento,sexo,beneficio,tese,etapa,valor,ganho_em,canal,origem
      Ana,4899990002,,,,F,Auxílio-doença,,,,,,
    CSV
    lead = account.leads.reorder(:id).last
    expect(lead.lead_stage).to eq(account.lead_stages.order(:position).first)
    expect(lead.contact.phone_number).to eq('+554899990002')
  end

  it 'rejeita linha com benefício desconhecido e anexa failed_records' do
    import = run_import(<<~CSV)
      nome,telefone,email,cpf,data_nascimento,sexo,beneficio,tese,etapa,valor,ganho_em,canal,origem
      Zé,4899990003,,,,M,Benefício Inexistente,,,,,,
    CSV
    expect(account.leads.count).to eq(0)
    expect(import.processed_records).to eq(0)
    expect(import.total_records).to eq(1)
    expect(import.failed_records).to be_attached
  end

  it 'é idempotente: re-run não duplica pessoa nem caso' do
    csv = <<~CSV
      nome,telefone,email,cpf,data_nascimento,sexo,beneficio,tese,etapa,valor,ganho_em,canal,origem
      João,4899990001,,,,M,Auxílio-acidente,,,,10/01/2024,,advbox
    CSV
    run_import(csv)
    expect { run_import(csv) }.not_to(change { [account.contacts.count, account.leads.count] })
  end

  it 'rejeita telefone inválido não-vazio' do
    import = run_import(<<~CSV)
      nome,telefone,email,cpf,data_nascimento,sexo,beneficio,tese,etapa,valor,ganho_em,canal,origem
      Bia,123,,,,F,,,,,,,
    CSV
    expect(import.processed_records).to eq(0)
    expect(import.failed_records).to be_attached
  end
end
```

- [ ] **Step 2: Implementar o serviço**

Criar `app/services/ramon/leads_csv_import.rb`:

```ruby
require 'csv'

module Ramon
  # Import CSV de pessoas + casos (item 4c-22 / Base 10.000).
  # Template: nome,telefone,email,cpf,data_nascimento,sexo,beneficio,tese,etapa,valor,ganho_em,canal,origem
  # ponytail: linha a linha (sem bulk); ~10k linhas ok em job :low — activerecord-import se doer.
  class LeadsCsvImport
    CASE_COLUMNS = %w[beneficio tese etapa valor ganho_em].freeze

    def initialize(data_import)
      @data_import = data_import
      @account = data_import.account
      @rejected = []
      @processed = 0
      @total = 0
    end

    def perform
      @data_import.update!(status: :processing)
      csv_rows.each { |row| import_row(row) }
      finish!
    rescue CSV::MalformedCSVError => e
      @data_import.update!(status: :failed, processing_errors: e.message)
    end

    private

    def csv_rows
      CSV.parse(@data_import.import_file.download, headers: true)
    end

    def import_row(row)
      @total += 1
      attrs = row.to_h.transform_values { |v| v.to_s.strip.presence }
      ActiveRecord::Base.transaction do
        contact = upsert_contact(attrs)
        create_case(contact, attrs) if case_columns_present?(attrs)
      end
      @processed += 1
    rescue StandardError => e
      @rejected << (row.fields + [e.message])
    end

    def upsert_contact(attrs)
      cpf = attrs['cpf']&.gsub(/\D/, '').presence
      phone = normalize_phone(attrs['telefone'])
      contact = find_contact(cpf, phone, attrs['email'])
      contact ||= @account.contacts.new(name: attrs['nome'] || phone || cpf)
      fill_blank(contact, :cpf, cpf)
      fill_blank(contact, :phone_number, phone)
      fill_blank(contact, :email, attrs['email'])
      fill_blank(contact, :data_nascimento, parse_date(attrs['data_nascimento'], 'data_nascimento'))
      fill_blank(contact, :sexo, attrs['sexo']&.upcase)
      contact.save!
      contact
    end

    def find_contact(cpf, phone, email)
      (cpf && @account.contacts.find_by(cpf: cpf)) ||
        (phone && @account.contacts.find_by(phone_number: phone)) ||
        (email && @account.contacts.from_email(email)&.then { |c| c.account_id == @account.id ? c : nil })
    end

    def fill_blank(contact, attribute, value)
      contact[attribute] = value if value.present? && contact[attribute].blank?
    end

    def case_columns_present?(attrs)
      attrs.values_at(*CASE_COLUMNS).any?(&:present?)
    end

    def create_case(contact, attrs)
      benefit = find_by_name!(@account.benefit_types, attrs['beneficio'], 'beneficio')
      thesis = find_by_name!(@account.theses, attrs['tese'], 'tese')
      won_at = parse_date(attrs['ganho_em'], 'ganho_em')
      stage = target_stage(attrs['etapa'], won_at)
      return if duplicate_case?(contact, benefit, won_at)

      lead = @account.leads.create!(
        name: contact.name, contact_id: contact.id, lead_stage: stage,
        benefit_type: benefit, thesis: thesis,
        value: parse_decimal(attrs['valor']),
        source: attrs['origem'], channel: valid_channel(attrs['canal'])
      )
      lead.update!(won_at: won_at) if won_at.present?
    end

    def target_stage(etapa_name, won_at)
      return @account.lead_stages.find_by!(is_won: true) if won_at.present?
      return @account.lead_stages.order(:position).first if etapa_name.blank?

      @account.lead_stages.find_by('lower(name) = ?', etapa_name.downcase) ||
        raise("etapa desconhecida: #{etapa_name}")
    end

    def duplicate_case?(contact, benefit, won_at)
      scope = @account.leads.where(contact_id: contact.id, benefit_type: benefit)
      return scope.where(won_at: won_at.all_day).exists? if won_at.present?

      scope.open.exists?
    end

    def find_by_name!(relation, name, column)
      return nil if name.blank?

      relation.find_by('lower(name) = ?', name.downcase) || raise("#{column} desconhecido: #{name}")
    end

    def normalize_phone(raw)
      return nil if raw.blank?

      digits = raw.gsub(/\D/, '')
      return "+55#{digits}" if [10, 11].include?(digits.length)
      return "+#{digits}" if [12, 13].include?(digits.length) && digits.start_with?('55')

      raise "telefone inválido: #{raw}"
    end

    def parse_date(raw, column)
      return nil if raw.blank?

      Date.strptime(raw, '%d/%m/%Y')
    rescue Date::Error
      begin
        Date.iso8601(raw)
      rescue Date::Error
        raise "#{column} inválida: #{raw}"
      end
    end

    def parse_decimal(raw)
      return nil if raw.blank?

      raw.tr('.', '').tr(',', '.').to_d
    end

    def valid_channel(raw)
      Ramon::SourceCatalog::CHANNELS.any? { |c| c[:key] == raw } ? raw : nil
    end

    def finish!
      @data_import.update!(status: :completed, total_records: @total, processed_records: @processed)
      attach_failed_records
    end

    def attach_failed_records
      return if @rejected.empty?

      header = "nome,telefone,email,cpf,data_nascimento,sexo,beneficio,tese,etapa,valor,ganho_em,canal,origem,erro\n"
      csv = header + @rejected.map(&:to_csv).join
      @data_import.failed_records.attach(
        io: StringIO.new(csv), filename: "rejeitadas_#{@data_import.id}.csv", content_type: 'text/csv'
      )
    end
  end
end
```

(`Ramon::SourceCatalog::CHANNELS` é um array de hashes `{key:, label:}` — confirmado no código; por isso o `any?` por `c[:key]`.)

⚠️ `parse_decimal`: formato BR "1.500,00" → tr remove pontos de milhar e troca vírgula por ponto. Valor com ponto decimal americano "1500.00" viraria "150000" — o template é BR; documentar no sample que o valor usa vírgula decimal.

- [ ] **Step 3: Commit**

```bash
git add app/services/ramon/leads_csv_import.rb spec/services/ramon/leads_csv_import_spec.rb
git commit --no-verify -m "feat(ramon): servico de import CSV de pessoas + casos"
```

---

### Task 2: Wiring — DataImport aceita 'leads' e o job delega

**Files:**
- Modify: `app/models/data_import.rb` (linha da validação `inclusion`)
- Modify: `app/jobs/data_import_job.rb` (branch no `perform`)
- Test: `spec/jobs/data_import_job_spec.rb` (exemplo novo) — se o arquivo não existir, criar `spec/jobs/ramon/leads_data_import_spec.rb` com o mesmo conteúdo

**Interfaces:**
- Consumes: `Ramon::LeadsCsvImport` (Task 1).
- Produces: `DataImport.create!(data_type: 'leads')` passa a ser válido e o job roteia pro serviço ramon. Task 3 usa isso no endpoint.

- [ ] **Step 1: Escrever o teste que falha**

Adicionar (no spec de job existente ou no arquivo novo):

```ruby
  it 'delega import de leads ao servico ramon' do
    account = create(:account)
    import = account.data_imports.new(data_type: 'leads')
    import.import_file.attach(io: StringIO.new("nome\n"), filename: 'l.csv', content_type: 'text/csv')
    import.save!

    service = instance_double(Ramon::LeadsCsvImport, perform: true)
    allow(Ramon::LeadsCsvImport).to receive(:new).with(import).and_return(service)

    described_class.perform_now(import)
    expect(service).to have_received(:perform)
  end
```

- [ ] **Step 2: Model**

`app/models/data_import.rb` — trocar:

```ruby
  validates :data_type, inclusion: { in: ['contacts'], message: I18n.t('errors.data_import.data_type.invalid') }
```

por:

```ruby
  validates :data_type, inclusion: { in: %w[contacts leads], message: I18n.t('errors.data_import.data_type.invalid') }
```

- [ ] **Step 3: Job**

`app/jobs/data_import_job.rb`, no início de `perform(data_import)`:

```ruby
  def perform(data_import)
    return Ramon::LeadsCsvImport.new(data_import).perform if data_import.data_type == 'leads'

    @data_import = data_import
    ...
```

(Manter o resto intacto.)

- [ ] **Step 4: Commit**

```bash
git add app/models/data_import.rb app/jobs/data_import_job.rb spec/jobs/
git commit --no-verify -m "feat(ramon): DataImport aceita data_type leads e job delega ao servico"
```

---

### Task 3: Endpoint + sample CSV

**Files:**
- Modify: `config/routes.rb` (namespace accounts, junto das rotas ramon)
- Create: `app/controllers/api/v1/accounts/ramon_lead_imports_controller.rb`
- Create: `app/policies/ramon_lead_import_policy.rb`
- Create: `public/downloads/import-leads-sample.csv`
- Test (create): `spec/requests/api/v1/accounts/ramon_lead_imports_spec.rb`

**Interfaces:**
- Consumes: Task 2 (`data_type: 'leads'` válido; after_create enfileira o job com 1 min de espera — comportamento nativo).
- Produces: `POST /api/v1/accounts/:id/ramon_lead_imports` (multipart, campo `import_file`) → 200; `GET .../ramon_lead_imports/:id` → status/contadores. Task 4 consome.

- [ ] **Step 1: Escrever os testes que falham**

Criar `spec/requests/api/v1/accounts/ramon_lead_imports_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe 'Ramon Lead Imports API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:csv_file) do
    Rack::Test::UploadedFile.new(
      StringIO.new("nome,telefone\nMaria,4899990000\n"), 'text/csv', original_filename: 'leads.csv'
    )
  end

  it 'cria o import de leads (admin) e enfileira processamento' do
    expect do
      post "/api/v1/accounts/#{account.id}/ramon_lead_imports",
           params: { import_file: csv_file },
           headers: admin.create_new_auth_token
    end.to change { account.data_imports.where(data_type: 'leads').count }.by(1)
    expect(response).to have_http_status(:success)
  end

  it 'barra agente (admin-only)' do
    post "/api/v1/accounts/#{account.id}/ramon_lead_imports",
         params: { import_file: csv_file },
         headers: agent.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
  end

  it '422 sem arquivo' do
    post "/api/v1/accounts/#{account.id}/ramon_lead_imports", headers: admin.create_new_auth_token
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'mostra status e contadores' do
    import = account.data_imports.new(data_type: 'leads', status: :completed, total_records: 10, processed_records: 9)
    import.import_file.attach(io: StringIO.new("nome\n"), filename: 'l.csv', content_type: 'text/csv')
    import.save!
    get "/api/v1/accounts/#{account.id}/ramon_lead_imports/#{import.id}", headers: admin.create_new_auth_token
    body = response.parsed_body
    expect(body['status']).to eq('completed')
    expect(body['processed_records']).to eq(9)
  end
end
```

- [ ] **Step 2: Rota**

`config/routes.rb`, junto das rotas ramon do namespace accounts:

```ruby
        resources :ramon_lead_imports, only: [:create, :show]
```

- [ ] **Step 3: Policy + controller**

`app/policies/ramon_lead_import_policy.rb`:

```ruby
class RamonLeadImportPolicy < ApplicationPolicy
  def create?
    @account_user.administrator?
  end

  def show?
    @account_user.administrator?
  end
end
```

`app/controllers/api/v1/accounts/ramon_lead_imports_controller.rb`:

```ruby
class Api::V1::Accounts::RamonLeadImportsController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :check_authorization

  def create
    return render json: { error: 'import_file ausente' }, status: :unprocessable_entity if params[:import_file].blank?

    import = Current.account.data_imports.new(data_type: 'leads')
    import.import_file.attach(params[:import_file])
    import.save!
    render json: { id: import.id, status: import.status }
  end

  def show
    import = Current.account.data_imports.where(data_type: 'leads').find(params[:id])
    render json: import.slice(:id, :status, :total_records, :processed_records)
  end

  private

  def check_authorization
    authorize(:ramon_lead_import, "#{action_name}?".to_sym)
  end
end
```

- [ ] **Step 4: Sample CSV**

`public/downloads/import-leads-sample.csv`:

```csv
nome,telefone,email,cpf,data_nascimento,sexo,beneficio,tese,etapa,valor,ganho_em,canal,origem
Maria Silva,48 99999-0000,maria@example.com,529.982.247-25,15/03/1970,F,Auxílio-acidente,,,"1.500,00",10/01/2024,,advbox
João Souza,48 98888-1111,,,,M,Auxílio-doença,,Qualificação,,,,indicacao-dr-carlos
```

(Nota do template: valor em formato BR com vírgula decimal; colunas de caso vazias = importa só a pessoa; `ganho_em` preenchido ignora `etapa` e marca o caso como ganho.)

- [ ] **Step 5: Commit**

```bash
git add config/routes.rb app/controllers/api/v1/accounts/ramon_lead_imports_controller.rb app/policies/ramon_lead_import_policy.rb public/downloads/import-leads-sample.csv spec/requests/api/v1/accounts/ramon_lead_imports_spec.rb
git commit --no-verify -m "feat(ramon): endpoint de import CSV de leads + sample"
```

---

### Task 4: UI no FunilConfig

**Files:**
- Create: `app/javascript/dashboard/api/ramonLeadImports.js`
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/pages/FunilConfig.vue` (nova seção no fim, após a seção da linha ~139-168)
- Modify: `app/javascript/dashboard/i18n/locale/en/ramon.json` + `pt_BR/ramon.json` (bloco novo `RAMON.IMPORT`)

**Interfaces:**
- Consumes: endpoint da Task 3.

- [ ] **Step 1: API client**

`app/javascript/dashboard/api/ramonLeadImports.js`:

```js
/* global axios */
import ApiClient from './ApiClient';

class RamonLeadImportsAPI extends ApiClient {
  constructor() {
    super('ramon_lead_imports', { accountScoped: true });
  }

  create(file) {
    const formData = new FormData();
    formData.append('import_file', file);
    return axios.post(this.url, formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  }
}

export default new RamonLeadImportsAPI();
```

- [ ] **Step 2: Seção no FunilConfig.vue**

No `<script setup>`, adicionar imports e estado (junto dos existentes):

```js
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import RamonLeadImportsAPI from 'dashboard/api/ramonLeadImports';
```

```js
const { t } = useI18n();
const importFileInput = ref(null);
const importing = ref(false);

const submitImport = async () => {
  const file = importFileInput.value?.files?.[0];
  if (!file) return;
  importing.value = true;
  try {
    await RamonLeadImportsAPI.create(file);
    useAlert(t('RAMON.IMPORT.SENT'));
    importFileInput.value.value = '';
  } catch (e) {
    useAlert(t('RAMON.IMPORT.ERROR'));
  } finally {
    importing.value = false;
  }
};
```

(Se o arquivo já importa `useI18n`/`useAlert`, não duplicar imports.)

No template, adicionar como ÚLTIMA seção (após a seção que termina na linha ~168):

```html
    <section class="mt-8" data-testid="import-leads-section">
      <h2 class="mb-1 text-sm uppercase tracking-widest text-n-slate-9">
        {{ $t('RAMON.IMPORT.TITLE') }}
      </h2>
      <p class="mb-3 text-xs text-n-slate-10">
        {{ $t('RAMON.IMPORT.HINT') }}
        <a
          href="/downloads/import-leads-sample.csv"
          download
          class="text-n-iris-11 hover:underline"
        >
          {{ $t('RAMON.IMPORT.SAMPLE') }}
        </a>
      </p>
      <div class="flex items-center gap-2">
        <input
          ref="importFileInput"
          data-testid="import-leads-file"
          type="file"
          accept=".csv"
          class="text-sm text-n-slate-11"
        />
        <button
          data-testid="import-leads-submit"
          class="px-3 py-1.5 text-sm rounded-lg bg-n-iris-9 text-white disabled:opacity-50"
          :disabled="importing"
          @click="submitImport"
        >
          {{ $t('RAMON.IMPORT.SUBMIT') }}
        </button>
      </div>
    </section>
```

- [ ] **Step 3: i18n**

`en/ramon.json`, bloco novo dentro de RAMON (mesmo nível de PLAYBOOKS):

```json
    "IMPORT": {
      "TITLE": "Import leads (CSV)",
      "HINT": "Creates/updates people (matched by CPF → phone → email) and, when case columns are present, their cases. Invalid rows come back as a rejected-rows CSV.",
      "SAMPLE": "Download template",
      "SUBMIT": "Import",
      "SENT": "Import queued — it runs in about a minute.",
      "ERROR": "Import failed — check the file and try again."
    },
```

`pt_BR/ramon.json`:

```json
    "IMPORT": {
      "TITLE": "Importar leads (CSV)",
      "HINT": "Cria/atualiza pessoas (match por CPF → telefone → email) e, quando as colunas de caso vierem preenchidas, os casos. Linhas inválidas voltam num CSV de rejeitadas.",
      "SAMPLE": "Baixar modelo",
      "SUBMIT": "Importar",
      "SENT": "Import na fila — processa em cerca de um minuto.",
      "ERROR": "Falha no import — confira o arquivo e tente de novo."
    },
```

- [ ] **Step 4: Prettier + commit**

Run: `npx prettier --write` nos arquivos tocados.

```bash
git add app/javascript/dashboard/api/ramonLeadImports.js app/javascript/dashboard/routes/dashboard/ramon/pages/FunilConfig.vue app/javascript/dashboard/i18n/locale/en/ramon.json app/javascript/dashboard/i18n/locale/pt_BR/ramon.json
git commit --no-verify -m "feat(funil): import CSV de leads na tela de config"
```

---

## Verificação final (whole-branch)

- Push, PR base `ramon`, título `feat: import CSV de leads (pessoas + casos)`. Corpo avisa: **mergear após o PR da Linha da Vida** (stacked).
- CI: `gh pr view <N> --json statusCheckRollup` — N/N completed + zero não-success.
- Sem migração → deploy = imagem nova apenas.
