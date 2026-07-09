# Linha da Vida (Onda 3a) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pessoa ≠ caso: `Contact` vira a pessoa (CPF, nascimento, sexo), `Lead` vira o episódio (N por pessoa, dedup relaxado com critério novo-caso vs reengajamento), calendário de marcos etários calculado no hub e tela "Linha da Vida" (passado/presente/futuro) por pessoa.

**Architecture:** Zero entidade nova — colunas novas em `contacts`, scope `Lead.open` consumido pelos 3 caminhos de criação, serviço puro `Ramon::MarcosEtarios` (tabela constante), endpoint agregador `linha_da_vida` e página Vue no mundo Intranet. Broadcast e jbuilder do lead ganham os campos da pessoa (padrão `contact_phone`).

**Tech Stack:** Rails 7.1 (fork Chatwoot v4.15.1), Vue 3 `<script setup>`, Tailwind, RSpec.

**Spec de origem:** `docs/superpowers/specs/2026-07-07-linha-da-vida-design.md`.

## Global Constraints

- **Branch stacked sobre `feat/ramon-honorario-tese`** (PR #41) — o schema.rb evolui linearmente (version `2026_07_07_000001` → `2026_07_07_100001`). PR desta branch: base `ramon`, corpo avisa "mergear após #41".
- Sem ambiente local: **PR + CI validam**. Não rodar bundle/rspec/rake; escrever os testes e anotar "CI valida". Commits/push com `--no-verify`.
- `db/schema.rb` editado manualmente (add_column simples): colunas novas SEMPRE no fim da lista de colunas da tabela; version bump para `2026_07_07_100001`.
- Rubocop: 150 chars/linha; RSpec máx 7 expectations/exemplo.
- `Lead` tem `default_scope order(:lead_stage_id, :position, :id)` — **`.last` NÃO é o mais recente**; em specs usar `reorder(:id).last` ou `find_by`.
- `create(:account)` seeda o funil (Novo…Fechado/Perdido) + benefícios + 5 teses — specs usam `account.lead_stages.find_by(is_won: true)` etc., nunca criam etapa com nome seedado.
- Specs de controllers de leads ficam em `spec/controllers/api/v1/accounts/` (padrão do fork); specs de request novas em `spec/requests/...`. Ao adicionar exemplos em arquivo existente, seguir o setup/headers do próprio arquivo.
- Evento Vue custom SEMPRE camelCase. Vuex action: não desestruturar `state` cru.
- i18n frontend: `en/ramon.json` E `pt_BR/ramon.json`.
- CPF armazenado normalizado (11 dígitos, sem pontuação); sexo ∈ {'M','F'} ou nil.
- Critério de dedup (spec): lead **aberto** do contato → reengaja; **todos fechados (won/lost) → cria novo** lead pro mesmo contato. Captação da LP não pode quebrar (retrocompat).
- Nomes exatos das colunas: `contacts.cpf`, `contacts.data_nascimento`, `contacts.sexo`.

---

### Task 1: Migração pessoa + Contact model + CpfValidator

**Files:**
- Create: `db/migrate/20260707100001_add_pessoa_fields_to_contacts.rb`
- Create: `app/validators/cpf_validator.rb`
- Modify: `db/schema.rb` (tabela `contacts` ~linha 651-681 + `version:` linha ~13)
- Modify: `app/models/contact.rb` (associação + validações + normalização)
- Test (create): `spec/models/contact_ramon_spec.rb`

**Interfaces:**
- Produces: colunas `contacts.cpf` (string, única por conta quando presente), `contacts.data_nascimento` (date), `contacts.sexo` (string 'M'/'F'); `Contact#leads` (has_many, nullify); CPF normalizado para 11 dígitos no `before_validation`. Tasks 2-7 dependem desses nomes.

- [ ] **Step 1: Escrever os testes que falham**

Criar `spec/models/contact_ramon_spec.rb` (arquivo separado do spec nativo — marca o que é do fork):

```ruby
require 'rails_helper'

# Campos de pessoa do fork (Linha da Vida): cpf, data_nascimento, sexo.
RSpec.describe Contact do
  let(:account) { create(:account) }

  it 'normaliza o CPF para 11 dígitos e aceita CPF válido' do
    contact = create(:contact, account: account, cpf: '529.982.247-25')
    expect(contact.reload.cpf).to eq('52998224725')
  end

  it 'rejeita CPF com dígito verificador inválido' do
    contact = build(:contact, account: account, cpf: '52998224724')
    expect(contact).not_to be_valid
  end

  it 'rejeita CPF de dígitos repetidos' do
    contact = build(:contact, account: account, cpf: '111.111.111-11')
    expect(contact).not_to be_valid
  end

  it 'aceita contato sem CPF (nil) e não colide unicidade entre nulos' do
    create(:contact, account: account)
    segundo = build(:contact, account: account)
    expect(segundo).to be_valid
  end

  it 'rejeita CPF duplicado na mesma conta e aceita em outra conta' do
    create(:contact, account: account, cpf: '52998224725')
    dup = build(:contact, account: account, cpf: '529.982.247-25')
    outra = build(:contact, account: create(:account), cpf: '52998224725')
    expect(dup).not_to be_valid
    expect(outra).to be_valid
  end

  it 'valida sexo em M/F e aceita nil' do
    expect(build(:contact, account: account, sexo: 'M')).to be_valid
    expect(build(:contact, account: account, sexo: nil)).to be_valid
    expect(build(:contact, account: account, sexo: 'X')).not_to be_valid
  end

  it 'tem N leads (has_many) e anula contact_id ao destruir a pessoa' do
    contact = create(:contact, account: account)
    lead = create(:lead, account: account, contact: contact,
                        lead_stage: account.lead_stages.order(:position).first)
    expect(contact.leads).to contain_exactly(lead)
    contact.destroy!
    expect(lead.reload.contact_id).to be_nil
  end
end
```

- [ ] **Step 2: Criar a migração**

`db/migrate/20260707100001_add_pessoa_fields_to_contacts.rb`:

```ruby
class AddPessoaFieldsToContacts < ActiveRecord::Migration[7.1]
  def change
    add_column :contacts, :cpf, :string
    add_column :contacts, :data_nascimento, :date
    add_column :contacts, :sexo, :string
    add_index :contacts, [:account_id, :cpf], unique: true, where: 'cpf IS NOT NULL',
                                              name: 'uniq_cpf_per_account_contact'
  end
end
```

- [ ] **Step 3: Atualizar db/schema.rb manualmente**

Linha ~13: `version: 2026_07_07_000001` → `version: 2026_07_07_100001`.

Na `create_table "contacts"`, adicionar ao FIM da lista de colunas (depois de `t.bigint "company_id"`, antes dos índices):

```ruby
    t.string "cpf"
    t.date "data_nascimento"
    t.string "sexo"
```

E junto aos índices da MESMA tabela (ordem alfabética junto dos `t.index` existentes — colocar imediatamente antes de `t.index ["blocked"]...` se existir, senão em qualquer posição entre os índices):

```ruby
    t.index ["account_id", "cpf"], name: "uniq_cpf_per_account_contact", unique: true, where: "(cpf IS NOT NULL)"
```

- [ ] **Step 4: Criar o CpfValidator**

`app/validators/cpf_validator.rb`:

```ruby
# Valida CPF já normalizado (11 dígitos): formato + dígitos verificadores.
class CpfValidator < ActiveModel::EachValidator
  def validate_each(record, attribute, value)
    return if value.blank?

    record.errors.add(attribute, options[:message] || :invalid) unless valid_cpf?(value)
  end

  private

  def valid_cpf?(cpf)
    return false unless cpf.match?(/\A\d{11}\z/)
    return false if cpf.chars.uniq.one?

    [9, 10].all? { |len| verifier_digit(cpf, len) == cpf[len].to_i }
  end

  # dv = ((soma dos dígitos * pesos decrescentes) * 10) % 11, com 10 → 0
  def verifier_digit(cpf, len)
    sum = cpf[0, len].chars.each_with_index.sum { |digit, i| digit.to_i * (len + 1 - i) }
    mod = (sum * 10) % 11
    mod == 10 ? 0 : mod
  end
end
```

- [ ] **Step 5: Contact — associação, validações, normalização**

Em `app/models/contact.rb`:

Depois de `has_many :notes, dependent: :destroy_async` (linha ~64), adicionar:

```ruby
  has_many :leads, dependent: :nullify
```

Depois do bloco de `validates :phone_number, ...` (linha ~56), adicionar:

```ruby
  validates :cpf, allow_nil: true, uniqueness: { scope: [:account_id] }, cpf: true
  validates :sexo, allow_nil: true, inclusion: { in: %w[M F] }
```

No `before_validation :prepare_contact_attributes` já existente: adicionar a normalização dentro de `prepare_contact_attributes` (método privado, linha ~218):

```ruby
  def prepare_contact_attributes
    prepare_email_attribute
    prepare_jsonb_attributes
    prepare_cpf_attribute
  end

  def prepare_cpf_attribute
    self.cpf = cpf.to_s.gsub(/\D/, '').presence if will_save_change_to_cpf?
  end
```

- [ ] **Step 6: Commit**

```bash
git add db/migrate/20260707100001_add_pessoa_fields_to_contacts.rb db/schema.rb app/validators/cpf_validator.rb app/models/contact.rb spec/models/contact_ramon_spec.rb
git commit --no-verify -m "feat(contacts): pessoa ganha cpf, data de nascimento e sexo (Linha da Vida)"
```

---

### Task 2: Lead.open + dedup relaxado nos 3 caminhos

**Files:**
- Modify: `app/models/lead.rb` (~linha 19, junto do default_scope)
- Modify: `app/listeners/ramon_lead_listener.rb:11`
- Modify: `app/controllers/api/v1/accounts/leads_controller.rb:46-54`
- Modify: `app/controllers/public/api/v1/ramon_leads_controller.rb:58-63`
- Test: `spec/listeners/ramon_lead_listener_spec.rb`, `spec/controllers/api/v1/accounts/leads_controller_spec.rb`, `spec/requests/public/api/v1/ramon_leads_controller_spec.rb`

**Interfaces:**
- Consumes: nada da Task 1 (independente).
- Produces: `Lead.open` (scope: leads em etapa não-won/não-lost). Comportamento novo: contato cujos leads estão TODOS fechados ganha lead novo em toda porta de entrada.

- [ ] **Step 1: Escrever os testes que falham**

Em `spec/listeners/ramon_lead_listener_spec.rb`, adicionar após o exemplo `'re-aponta a conversa do lead existente (dedup por contato)'`:

```ruby
  it 'cria lead NOVO quando os leads do contato estão todos fechados (pessoa ≠ caso)' do
    won_stage = account.lead_stages.find_by(is_won: true)
    old_conversation = create(:conversation, account: account, inbox: inbox, contact: contact)
    old_lead = create(:lead, account: account, contact: contact, conversation: old_conversation,
                             lead_stage: won_stage)

    expect { listener.conversation_created(event) }.to change { account.leads.count }.by(1)
    new_lead = account.leads.reorder(:id).last
    expect(new_lead.id).not_to eq(old_lead.id)
    expect(new_lead.lead_stage).to eq(account.lead_stages.order(:position).first)
    expect(old_lead.reload.conversation_id).to eq(old_conversation.id)
  end
```

Em `spec/controllers/api/v1/accounts/leads_controller_spec.rb`, no describe do `for_conversation` (seguir o setup/headers do arquivo), adicionar:

```ruby
  it 'cria lead novo no for_conversation quando os leads do contato estão fechados' do
    lost_stage = account.lead_stages.find_by(is_lost: true)
    contact = create(:contact, account: account)
    create(:lead, account: account, contact: contact, lead_stage: lost_stage, lost_reason: 'sem viabilidade')
    conversation = create(:conversation, account: account, contact: contact)

    expect do
      post "/api/v1/accounts/#{account.id}/leads/for_conversation",
           params: { conversation_id: conversation.id },
           headers: admin.create_new_auth_token
    end.to change { account.leads.count }.by(1)
  end
```

(O controller faz `conversations.find(params[:conversation_id])` — id primário, não display_id. Seguir o setup/headers dos exemplos existentes do arquivo.)

Em `spec/requests/public/api/v1/ramon_leads_controller_spec.rb` (regressão do critério, seguir o setup de token/ENV do arquivo):

```ruby
  it 'cria lead novo quando os leads do contato estão todos fechados' do
    contact = account.contacts.create!(name: 'Maria', phone_number: '+5548999990000')
    won_stage = account.lead_stages.find_by(is_won: true)
    account.leads.create!(name: 'Caso antigo', contact_id: contact.id, lead_stage: won_stage)

    expect { post_capture(telefone: '48 99999-0000', nome: 'Maria') }
      .to change { account.leads.count }.by(1)
  end
```

(`post_capture` = o helper/estilo de POST que o arquivo já usa; replicar a chamada real com token.)

- [ ] **Step 2: Scope no model**

`app/models/lead.rb`, logo após o `default_scope` (linha ~19):

```ruby
  # Lead "vivo" no funil — nem ganho nem perdido. É o critério de reengajamento
  # (pessoa ≠ caso): aberto reengaja, fechado não trava lead novo.
  scope :open, -> { joins(:lead_stage).where(lead_stages: { is_won: false, is_lost: false }) }
```

- [ ] **Step 3: Listener**

`app/listeners/ramon_lead_listener.rb` linha 11 — trocar:

```ruby
    lead = account.leads.find_by(contact_id: contact.id)
```

por:

```ruby
    lead = account.leads.open.find_by(contact_id: contact.id)
```

- [ ] **Step 4: LeadsController#find_lead_for_contact**

`app/controllers/api/v1/accounts/leads_controller.rb` linha 49 — trocar:

```ruby
    lead = Current.account.leads.find_by(contact_id: conversation.contact_id)
```

por:

```ruby
    lead = Current.account.leads.open.find_by(contact_id: conversation.contact_id)
```

- [ ] **Step 5: Endpoint público (reusar o scope, DRY)**

`app/controllers/public/api/v1/ramon_leads_controller.rb` linhas 58-63 — trocar o método inteiro:

```ruby
  def open_lead_for(contact)
    account.leads.open.find_by(contact_id: contact.id)
  end
```

- [ ] **Step 6: Commit**

```bash
git add app/models/lead.rb app/listeners/ramon_lead_listener.rb app/controllers/api/v1/accounts/leads_controller.rb app/controllers/public/api/v1/ramon_leads_controller.rb spec/listeners/ramon_lead_listener_spec.rb spec/controllers/api/v1/accounts/leads_controller_spec.rb spec/requests/public/api/v1/ramon_leads_controller_spec.rb
git commit --no-verify -m "feat(leads): N casos por pessoa - dedup reengaja so lead aberto (Lead.open)"
```

---

### Task 3: Campos da pessoa na API (contacts permit + payload do lead)

**Files:**
- Modify: `app/controllers/api/v1/accounts/contacts_controller.rb:174` (permitted_params)
- Modify: `app/views/api/v1/accounts/leads/_lead.json.jbuilder` (bloco contact_*)
- Modify: `app/models/lead.rb` (`cadence_event_data`, ~linha 90)
- Test: `spec/requests/api/v1/accounts/contacts_ramon_spec.rb` (create)

**Interfaces:**
- Consumes: colunas da Task 1.
- Produces: `PATCH /api/v1/accounts/:id/contacts/:id` aceita `cpf`/`data_nascimento`/`sexo`; payload do lead (jbuilder E broadcast) ganha `contact_cpf`, `contact_data_nascimento`, `contact_sexo`. Tasks 6-7 consomem esses nomes.

- [ ] **Step 1: Escrever os testes que falham**

Criar `spec/requests/api/v1/accounts/contacts_ramon_spec.rb`:

```ruby
require 'rails_helper'

# Campos de pessoa do fork no CRUD nativo de contatos.
RSpec.describe 'Contacts API (campos ramon)', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:contact) { create(:contact, account: account) }

  it 'atualiza cpf, data de nascimento e sexo' do
    put "/api/v1/accounts/#{account.id}/contacts/#{contact.id}",
        params: { cpf: '529.982.247-25', data_nascimento: '1970-03-15', sexo: 'F' },
        headers: admin.create_new_auth_token
    expect(response).to have_http_status(:success)
    contact.reload
    expect(contact.cpf).to eq('52998224725')
    expect(contact.data_nascimento).to eq(Date.new(1970, 3, 15))
    expect(contact.sexo).to eq('F')
  end

  it 'rejeita cpf inválido com 422' do
    put "/api/v1/accounts/#{account.id}/contacts/#{contact.id}",
        params: { cpf: '123' },
        headers: admin.create_new_auth_token
    expect(response).to have_http_status(:unprocessable_entity)
    expect(contact.reload.cpf).to be_nil
  end

  it 'expõe os campos da pessoa no payload do lead' do
    contact.update!(cpf: '52998224725', data_nascimento: '1970-03-15', sexo: 'F')
    lead = create(:lead, account: account, contact: contact,
                         lead_stage: account.lead_stages.order(:position).first)
    get "/api/v1/accounts/#{account.id}/leads/#{lead.id}", headers: admin.create_new_auth_token
    body = response.parsed_body
    expect(body['contact_cpf']).to eq('52998224725')
    expect(body['contact_data_nascimento']).to eq('1970-03-15')
    expect(body['contact_sexo']).to eq('F')
  end
end
```

- [ ] **Step 2: Permit no contacts_controller**

`app/controllers/api/v1/accounts/contacts_controller.rb` linha 174 — trocar:

```ruby
    params.permit(:name, :identifier, :email, :phone_number, :avatar, :blocked, :avatar_url, additional_attributes: {}, custom_attributes: {})
```

por:

```ruby
    params.permit(:name, :identifier, :email, :phone_number, :avatar, :blocked, :avatar_url,
                  :cpf, :data_nascimento, :sexo,
                  additional_attributes: {}, custom_attributes: {})
```

- [ ] **Step 3: Jbuilder do lead**

`app/views/api/v1/accounts/leads/_lead.json.jbuilder` — após `json.contact_email lead.contact&.email`:

```ruby
json.contact_cpf lead.contact&.cpf
json.contact_data_nascimento lead.contact&.data_nascimento
json.contact_sexo lead.contact&.sexo
```

- [ ] **Step 4: Broadcast (push_event_data)**

`app/models/lead.rb`, dentro de `cadence_event_data` (linha ~90), após `contact_phone: contact&.phone_number,`:

```ruby
      contact_cpf: contact&.cpf,
      # Date segue o precedente de dcb_em no mesmo hash
      contact_data_nascimento: contact&.data_nascimento,
      contact_sexo: contact&.sexo,
```

- [ ] **Step 5: Commit**

```bash
git add app/controllers/api/v1/accounts/contacts_controller.rb app/views/api/v1/accounts/leads/_lead.json.jbuilder app/models/lead.rb spec/requests/api/v1/accounts/contacts_ramon_spec.rb
git commit --no-verify -m "feat(contacts): API aceita e payload do lead expoe cpf/nascimento/sexo"
```

---

### Task 4: Serviço Ramon::MarcosEtarios

**Files:**
- Create: `app/services/ramon/marcos_etarios.rb`
- Test (create): `spec/services/ramon/marcos_etarios_spec.rb`

**Interfaces:**
- Consumes: nada (serviço puro).
- Produces: `Ramon::MarcosEtarios.para(data_nascimento:, sexo: nil)` → array de hashes `{ key:, sexo:, idade:, data: (Date), atingido: (bool) }`, ordenado por data. Keys: `'aposentadoria_idade_urbana'`, `'aposentadoria_idade_rural'`, `'bpc_loas_idoso'`. Task 5 serializa isso; Task 7 traduz as keys no i18n.

- [ ] **Step 1: Escrever os testes que falham**

Criar `spec/services/ramon/marcos_etarios_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe Ramon::MarcosEtarios do
  let(:nascimento) { Date.new(1970, 3, 15) }

  it 'calcula os marcos de homem (65 urbana / 60 rural / 65 BPC)' do
    marcos = described_class.para(data_nascimento: nascimento, sexo: 'M')
    by_key = marcos.index_by { |m| m[:key] }
    expect(by_key['aposentadoria_idade_urbana'][:data]).to eq(Date.new(2035, 3, 15))
    expect(by_key['aposentadoria_idade_rural'][:data]).to eq(Date.new(2030, 3, 15))
    expect(by_key['bpc_loas_idoso'][:idade]).to eq(65)
  end

  it 'calcula os marcos de mulher (62 urbana / 55 rural)' do
    marcos = described_class.para(data_nascimento: nascimento, sexo: 'F')
    by_key = marcos.index_by { |m| m[:key] }
    expect(by_key['aposentadoria_idade_urbana'][:idade]).to eq(62)
    expect(by_key['aposentadoria_idade_rural'][:idade]).to eq(55)
  end

  it 'sem sexo: desdobra os marcos que variam e unifica os que não variam' do
    marcos = described_class.para(data_nascimento: nascimento, sexo: nil)
    urbanas = marcos.select { |m| m[:key] == 'aposentadoria_idade_urbana' }
    bpc = marcos.select { |m| m[:key] == 'bpc_loas_idoso' }
    expect(urbanas.map { |m| m[:idade] }).to contain_exactly(62, 65)
    expect(bpc.size).to eq(1)
    expect(bpc.first[:sexo]).to be_nil
  end

  it 'ordena por data e marca os já atingidos' do
    marcos = described_class.para(data_nascimento: Date.new(1950, 1, 1), sexo: 'M')
    expect(marcos.map { |m| m[:data] }).to eq(marcos.map { |m| m[:data] }.sort)
    expect(marcos).to all(include(atingido: true))
  end

  it 'retorna vazio sem data de nascimento' do
    expect(described_class.para(data_nascimento: nil)).to eq([])
  end
end
```

- [ ] **Step 2: Implementar o serviço**

`app/services/ramon/marcos_etarios.rb`:

```ruby
module Ramon
  # Calendário de direitos por idade — radar de OPORTUNIDADE, não parecer jurídico.
  # Tabela versionada das idades-alvo (pós-EC 103/2019). Não consulta o motor:
  # idade é aritmética de data + tabela fixa.
  class MarcosEtarios
    MARCOS = [
      { key: 'aposentadoria_idade_urbana', idades: { 'M' => 65, 'F' => 62 } },
      { key: 'aposentadoria_idade_rural',  idades: { 'M' => 60, 'F' => 55 } },
      { key: 'bpc_loas_idoso',             idades: { 'M' => 65, 'F' => 65 } }
    ].freeze

    def self.para(data_nascimento:, sexo: nil)
      return [] if data_nascimento.blank?

      sexo = nil unless %w[M F].include?(sexo)
      MARCOS.flat_map { |marco| entries_for(marco, data_nascimento, sexo) }
            .sort_by { |m| m[:data] }
    end

    def self.entries_for(marco, nascimento, sexo)
      idades = marco[:idades]
      return [build(marco, nascimento, sexo, idades[sexo])] if sexo.present?
      return [build(marco, nascimento, nil, idades.values.first)] if idades.values.uniq.one?

      idades.map { |s, idade| build(marco, nascimento, s, idade) }
    end

    def self.build(marco, nascimento, sexo, idade)
      data = nascimento + idade.years
      { key: marco[:key], sexo: sexo, idade: idade, data: data, atingido: data <= Time.zone.today }
    end

    private_class_method :entries_for, :build
  end
end
```

- [ ] **Step 3: Commit**

```bash
git add app/services/ramon/marcos_etarios.rb spec/services/ramon/marcos_etarios_spec.rb
git commit --no-verify -m "feat(ramon): servico MarcosEtarios - calendario de direitos por idade"
```

---

### Task 5: Endpoint linha_da_vida

**Files:**
- Modify: `config/routes.rb` (junto das rotas ramon do namespace accounts, ~linha 285-301)
- Create: `app/controllers/api/v1/accounts/linha_da_vida_controller.rb`
- Create: `app/policies/linha_da_vida_policy.rb`
- Create: `app/views/api/v1/accounts/linha_da_vida/show.json.jbuilder`
- Test (create): `spec/requests/api/v1/accounts/linha_da_vida_spec.rb`

**Interfaces:**
- Consumes: Tasks 1 (colunas), 4 (MarcosEtarios).
- Produces: `GET /api/v1/accounts/:account_id/contacts/:contact_id/linha_da_vida` → `{ contact: {...}, leads: [...], marcos: [...] }`. Task 7 consome esse contrato.

- [ ] **Step 1: Escrever o teste que falha**

Criar `spec/requests/api/v1/accounts/linha_da_vida_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe 'Linha da Vida API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:contact) do
    create(:contact, account: account, name: 'Maria', cpf: '52998224725',
                     data_nascimento: Date.new(1970, 3, 15), sexo: 'F')
  end

  it 'devolve pessoa, casos e marcos etários' do
    won_stage = account.lead_stages.find_by(is_won: true)
    open_stage = account.lead_stages.order(:position).first
    caso = create(:lead, account: account, contact: contact, lead_stage: won_stage, name: 'Caso antigo')
    interesse = create(:lead, account: account, contact: contact, lead_stage: open_stage, name: 'Interesse novo')

    get "/api/v1/accounts/#{account.id}/contacts/#{contact.id}/linha_da_vida",
        headers: agent.create_new_auth_token

    expect(response).to have_http_status(:success)
    body = response.parsed_body
    expect(body['contact']['cpf']).to eq('52998224725')
    expect(body['leads'].pluck('id')).to contain_exactly(caso.id, interesse.id)
    expect(body['leads'].find { |l| l['id'] == caso.id }['is_won']).to be(true)
    expect(body['marcos'].pluck('key')).to include('aposentadoria_idade_urbana')
  end

  it '404 para contato de outra conta' do
    estranho = create(:contact, account: create(:account))
    get "/api/v1/accounts/#{account.id}/contacts/#{estranho.id}/linha_da_vida",
        headers: agent.create_new_auth_token
    expect(response).to have_http_status(:not_found)
  end
end
```

- [ ] **Step 2: Rota**

`config/routes.rb`, junto das rotas ramon do namespace accounts (perto de `resource :ramon_dashboard`):

```ruby
        get 'contacts/:contact_id/linha_da_vida', to: 'linha_da_vida#show'
```

- [ ] **Step 3: Policy + controller**

`app/policies/linha_da_vida_policy.rb` (mesmo padrão da RamonDashboardPolicy):

```ruby
class LinhaDaVidaPolicy < ApplicationPolicy
  def show?
    @account_user.administrator? || @account_user.agent?
  end
end
```

`app/controllers/api/v1/accounts/linha_da_vida_controller.rb`:

```ruby
class Api::V1::Accounts::LinhaDaVidaController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :check_authorization

  def show
    @contact = Current.account.contacts.find(params[:contact_id])
    @leads = Current.account.leads.where(contact_id: @contact.id)
                    .reorder(:id).includes(:lead_stage, :benefit_type, :thesis)
    @marcos = Ramon::MarcosEtarios.para(data_nascimento: @contact.data_nascimento, sexo: @contact.sexo)
  end

  private

  def check_authorization
    authorize(:linha_da_vida, :show?)
  end
end
```

- [ ] **Step 4: Jbuilder**

`app/views/api/v1/accounts/linha_da_vida/show.json.jbuilder`:

```ruby
json.contact do
  json.id @contact.id
  json.name @contact.name
  json.phone_number @contact.phone_number
  json.email @contact.email
  json.cpf @contact.cpf
  json.data_nascimento @contact.data_nascimento
  json.sexo @contact.sexo
end

json.leads @leads do |lead|
  json.id lead.id
  json.name lead.name
  json.created_at lead.created_at
  json.won_at lead.won_at
  json.lost_at lead.lost_at
  json.is_won lead.lead_stage&.is_won
  json.is_lost lead.lead_stage&.is_lost
  json.stage_name lead.lead_stage&.name
  json.stage_color lead.lead_stage&.color
  json.benefit_type_name lead.benefit_type&.name
  json.thesis_name lead.thesis&.name
  json.value lead.value
  json.lost_reason lead.lost_reason
  json.dcb_em lead.dcb_em
  json.benefit_monthly_value lead.benefit_monthly_value
  json.prescription lead.prescription
  json.conversation_id lead.conversation_id
end

json.marcos @marcos do |marco|
  json.key marco[:key]
  json.sexo marco[:sexo]
  json.idade marco[:idade]
  json.data marco[:data]
  json.atingido marco[:atingido]
end
```

- [ ] **Step 5: Commit**

```bash
git add config/routes.rb app/controllers/api/v1/accounts/linha_da_vida_controller.rb app/policies/linha_da_vida_policy.rb app/views/api/v1/accounts/linha_da_vida/show.json.jbuilder spec/requests/api/v1/accounts/linha_da_vida_spec.rb
git commit --no-verify -m "feat(ramon): endpoint linha da vida (pessoa + casos + marcos etarios)"
```

---

### Task 6: Bloco Pessoa editável na gaveta do lead

**Files:**
- Create: `app/javascript/dashboard/routes/dashboard/ramon/helpers/cpf.js`
- Modify: `app/javascript/dashboard/store/modules/leads.js` (action nova)
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/components/lead/LeadFields.vue` (bloco "Só leitura: contato", ~linha 547)
- Modify: `app/javascript/dashboard/i18n/locale/en/ramon.json` + `pt_BR/ramon.json` (bloco `RAMON.DRAWER`)

**Interfaces:**
- Consumes: contrato da Task 3 (`contact_cpf`/`contact_data_nascimento`/`contact_sexo` no payload; PATCH contacts aceita os 3).
- Produces: action Vuex `leads/updateContactFields({ leadId, contactId, payload })`; helper `formatCpf(digits)`/`stripCpf(text)`.

- [ ] **Step 1: Helper de CPF**

`app/javascript/dashboard/routes/dashboard/ramon/helpers/cpf.js`:

```js
export const stripCpf = text => String(text ?? '').replace(/\D/g, '');

export const formatCpf = digits => {
  const d = stripCpf(digits);
  if (!d) return '';
  return d
    .replace(/^(\d{3})(\d)/, '$1.$2')
    .replace(/^(\d{3})\.(\d{3})(\d)/, '$1.$2.$3')
    .replace(/\.(\d{3})(\d{1,2})$/, '.$1-$2');
};
```

- [ ] **Step 2: Action no módulo leads**

Em `app/javascript/dashboard/store/modules/leads.js`: importar o api client de contatos no topo (`import ContactAPI from '../../api/contacts';` — conferir o path relativo usado pelos imports existentes do arquivo) e adicionar nas actions (seguir o estilo local; não desestruturar `state` cru):

```js
  async updateContactFields({ commit, state: moduleState }, { leadId, contactId, payload }) {
    await ContactAPI.update(contactId, payload);
    const lead = moduleState.records.find(r => r.id === leadId);
    if (!lead) return;
    commit(types.EDIT_LEAD, {
      ...lead,
      contact_cpf: payload.cpf !== undefined ? payload.cpf : lead.contact_cpf,
      contact_data_nascimento:
        payload.data_nascimento !== undefined
          ? payload.data_nascimento
          : lead.contact_data_nascimento,
      contact_sexo: payload.sexo !== undefined ? payload.sexo : lead.contact_sexo,
    });
  },
```

(A coleção do módulo é `state.records` — convenção `MutationHelpers` do Chatwoot, confirmada no módulo.)

- [ ] **Step 3: Bloco Pessoa no LeadFields.vue**

No `<script setup>`: importar helpers e criar estado local + saves:

```js
import { formatCpf, stripCpf } from '../../helpers/cpf';
```

Adicionar junto aos refs locais (após `benefitMonthlyValue`, ~linha 39):

```js
const contactCpf = ref('');
const contactNascimento = ref('');
const contactSexo = ref('');
```

No `watch(() => props.lead, ...)` (linha ~49), adicionar antes do fechamento:

```js
    contactCpf.value = formatCpf(l?.contact_cpf);
    contactNascimento.value = l?.contact_data_nascimento ?? '';
    contactSexo.value = l?.contact_sexo ?? '';
```

Adicionar as funções de save (perto de `copyPhone`, ~linha 210):

```js
const saveContactField = async payload => {
  if (!props.lead?.contact_id) return;
  try {
    await store.dispatch('leads/updateContactFields', {
      leadId: props.lead.id,
      contactId: props.lead.contact_id,
      payload,
    });
  } catch (e) {
    useAlert(t('RAMON.FUNIL.SAVE_ERROR'));
    contactCpf.value = formatCpf(props.lead?.contact_cpf);
    contactNascimento.value = props.lead?.contact_data_nascimento ?? '';
    contactSexo.value = props.lead?.contact_sexo ?? '';
  }
};

const saveContactCpf = () => {
  const digits = stripCpf(contactCpf.value);
  if (digits === stripCpf(props.lead?.contact_cpf)) return;
  contactCpf.value = formatCpf(digits);
  saveContactField({ cpf: digits || null });
};

const saveContactNascimento = () =>
  saveContactField({ data_nascimento: contactNascimento.value || null });

const saveContactSexo = () =>
  saveContactField({ sexo: contactSexo.value || null });
```

No template, dentro do bloco "Só leitura: contato" (linha ~548) — após o `<p v-if="lead.contact_email">`, adicionar (o bloco deixa de ser só leitura; só quando há pessoa vinculada):

```html
      <template v-if="lead.contact_id">
        <label class="block mt-3 mb-1 text-xs text-n-slate-10">{{
          $t('RAMON.DRAWER.PESSOA.CPF')
        }}</label>
        <input
          v-model="contactCpf"
          data-testid="field-contact-cpf"
          type="text"
          inputmode="numeric"
          placeholder="000.000.000-00"
          class="w-full px-3 py-2 mb-3 text-sm rounded-lg bg-n-alpha-1 text-n-slate-12 border border-n-weak"
          @blur="saveContactCpf"
        />

        <label class="block mb-1 text-xs text-n-slate-10">{{
          $t('RAMON.DRAWER.PESSOA.BIRTHDATE')
        }}</label>
        <input
          v-model="contactNascimento"
          data-testid="field-contact-nascimento"
          type="date"
          class="w-full px-3 py-2 mb-3 text-sm rounded-lg bg-n-alpha-1 text-n-slate-12 border border-n-weak"
          @change="saveContactNascimento"
        />

        <label class="block mb-1 text-xs text-n-slate-10">{{
          $t('RAMON.DRAWER.PESSOA.SEX')
        }}</label>
        <select
          v-model="contactSexo"
          data-testid="field-contact-sexo"
          class="w-full px-3 py-2 mb-3 text-sm rounded-lg bg-n-alpha-1 text-n-slate-12 border border-n-weak"
          @change="saveContactSexo"
        >
          <option value="">—</option>
          <option value="M">{{ $t('RAMON.DRAWER.PESSOA.SEX_M') }}</option>
          <option value="F">{{ $t('RAMON.DRAWER.PESSOA.SEX_F') }}</option>
        </select>

        <router-link
          data-testid="field-linha-da-vida-link"
          :to="{
            name: 'ramon_linha_da_vida',
            params: { contactId: lead.contact_id },
          }"
          class="inline-flex items-center gap-1 text-xs text-n-iris-11 hover:underline"
        >
          <span class="i-lucide-git-commit-vertical size-3.5" />{{
            $t('RAMON.LINHA_DA_VIDA.OPEN')
          }}
        </router-link>
      </template>
```

- [ ] **Step 4: i18n**

`en/ramon.json`, bloco `RAMON.DRAWER` (junto de NAME/STAGE/...):

```json
      "PESSOA": {
        "CPF": "CPF",
        "BIRTHDATE": "Birth date",
        "SEX": "Sex",
        "SEX_M": "Male",
        "SEX_F": "Female"
      },
```

`pt_BR/ramon.json`, mesma posição:

```json
      "PESSOA": {
        "CPF": "CPF",
        "BIRTHDATE": "Data de nascimento",
        "SEX": "Sexo",
        "SEX_M": "Masculino",
        "SEX_F": "Feminino"
      },
```

- [ ] **Step 5: Prettier + commit**

Run: `npx prettier --write` nos arquivos tocados (ignorar `Delete ␍` em arquivos não tocados).

```bash
git add app/javascript/dashboard/routes/dashboard/ramon/helpers/cpf.js app/javascript/dashboard/store/modules/leads.js app/javascript/dashboard/routes/dashboard/ramon/components/lead/LeadFields.vue app/javascript/dashboard/i18n/locale/en/ramon.json app/javascript/dashboard/i18n/locale/pt_BR/ramon.json
git commit --no-verify -m "feat(funil): bloco pessoa editavel na gaveta (cpf, nascimento, sexo)"
```

---

### Task 7: Tela Linha da Vida + navegação

**Files:**
- Create: `app/javascript/dashboard/api/linhaDaVida.js`
- Create: `app/javascript/dashboard/routes/dashboard/ramon/pages/LinhaDaVida.vue`
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/ramon.routes.js`
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/components/kanban/LeadDrawer.vue` (link)
- Modify: `app/javascript/dashboard/i18n/locale/en/ramon.json` + `pt_BR/ramon.json` (bloco novo `RAMON.LINHA_DA_VIDA`)

**Interfaces:**
- Consumes: endpoint da Task 5 (`{ contact, leads, marcos }`); keys de marcos da Task 4.
- Produces: rota `ramon_linha_da_vida` (`/accounts/:accountId/ramon/pessoa/:contactId`).

- [ ] **Step 1: API client**

`app/javascript/dashboard/api/linhaDaVida.js`:

```js
/* global axios */
import ApiClient from './ApiClient';

class LinhaDaVidaAPI extends ApiClient {
  constructor() {
    super('contacts', { accountScoped: true });
  }

  show(contactId) {
    return axios.get(`${this.url}/${contactId}/linha_da_vida`);
  }
}

export default new LinhaDaVidaAPI();
```

- [ ] **Step 2: Página**

`app/javascript/dashboard/routes/dashboard/ramon/pages/LinhaDaVida.vue`:

```html
<script setup>
import { ref, computed, watch } from 'vue';
import { useRoute } from 'vue-router';
import LinhaDaVidaAPI from 'dashboard/api/linhaDaVida';
import { formatCpf } from '../helpers/cpf';
import { formatBrl } from '../helpers/currency';
import { frontendURL } from '../../../../helper/URLHelper';

const route = useRoute();

const data = ref(null);
const loading = ref(false);
const error = ref(false);

const fetchData = async () => {
  loading.value = true;
  error.value = false;
  try {
    const response = await LinhaDaVidaAPI.show(route.params.contactId);
    data.value = response.data;
  } catch (e) {
    error.value = true;
  } finally {
    loading.value = false;
  }
};

watch(() => route.params.contactId, fetchData, { immediate: true });

const contact = computed(() => data.value?.contact ?? null);
const leads = computed(() => data.value?.leads ?? []);

// Presente = casos vivos no funil; passado = fechados (ganhos e perdidos).
const openLeads = computed(() => leads.value.filter(l => !l.is_won && !l.is_lost));
const closedLeads = computed(() =>
  leads.value
    .filter(l => l.is_won || l.is_lost)
    .sort((a, b) => new Date(b.won_at || b.lost_at) - new Date(a.won_at || a.lost_at))
);

// Futuro = marcos etários não atingidos + DCBs futuras + início da prescrição
// (DCB + 60 meses: quando a pessoa começa a perder parcelas), ordenado por data.
const addMonths = (dateStr, months) => {
  const d = new Date(`${String(dateStr).slice(0, 10)}T12:00:00`);
  d.setMonth(d.getMonth() + months);
  return d;
};

const futureItems = computed(() => {
  const now = new Date();
  const marcos = (data.value?.marcos ?? [])
    .filter(m => !m.atingido)
    .map(m => ({ type: 'marco', date: m.data, marco: m }));
  const dcbs = leads.value
    .filter(l => l.dcb_em && new Date(l.dcb_em) >= now)
    .map(l => ({ type: 'dcb', date: l.dcb_em, lead: l }));
  const prescricoes = leads.value
    .filter(l => l.dcb_em && addMonths(l.dcb_em, 60) >= now)
    .map(l => ({ type: 'prescricao', date: addMonths(l.dcb_em, 60), lead: l }));
  return [...marcos, ...dcbs, ...prescricoes].sort(
    (a, b) => new Date(a.date) - new Date(b.date)
  );
});

const conversationUrl = lead =>
  frontendURL(
    `accounts/${route.params.accountId}/conversations/${lead.conversation_id}`
  );

const fmtDate = value => {
  if (!value) return '';
  return new Date(`${String(value).slice(0, 10)}T12:00:00`).toLocaleDateString('pt-BR');
};
</script>

<template>
  <div class="flex-1 h-full p-6 overflow-y-auto">
    <p v-if="loading" class="text-sm text-n-slate-9">
      {{ $t('RAMON.LINHA_DA_VIDA.LOADING') }}
    </p>
    <p v-else-if="error" class="text-sm text-n-ruby-11">
      {{ $t('RAMON.LINHA_DA_VIDA.ERROR') }}
    </p>

    <template v-else-if="contact">
      <div class="mb-6">
        <h1 class="text-2xl font-cormorant text-n-slate-12">
          {{ contact.name }}
        </h1>
        <p class="text-sm text-n-slate-10">
          <span v-if="contact.cpf">{{ formatCpf(contact.cpf) }} · </span>
          <span v-if="contact.data_nascimento">
            {{ $t('RAMON.LINHA_DA_VIDA.BORN_AT') }}
            {{ fmtDate(contact.data_nascimento) }}
          </span>
          <span v-if="contact.phone_number"> · {{ contact.phone_number }}</span>
        </p>
        <p
          v-if="!contact.data_nascimento"
          data-testid="lifeline-no-birthdate"
          class="mt-1 text-xs text-n-amber-11"
        >
          {{ $t('RAMON.LINHA_DA_VIDA.NO_BIRTHDATE_HINT') }}
        </p>
      </div>

      <!-- FUTURO -->
      <section class="mb-8" data-testid="lifeline-future">
        <h2 class="mb-2 text-sm uppercase tracking-widest text-n-slate-9">
          {{ $t('RAMON.LINHA_DA_VIDA.FUTURE') }}
        </h2>
        <p v-if="!futureItems.length" class="text-sm text-n-slate-9">
          {{ $t('RAMON.LINHA_DA_VIDA.FUTURE_EMPTY') }}
        </p>
        <ul class="flex flex-col gap-2">
          <li
            v-for="(item, i) in futureItems"
            :key="i"
            class="flex items-baseline gap-3 p-3 rounded-lg bg-n-alpha-1 border border-n-weak"
          >
            <span class="text-xs tabular-nums text-n-slate-10 shrink-0">
              {{ fmtDate(item.date) }}
            </span>
            <template v-if="item.type === 'marco'">
              <span class="text-sm text-n-slate-12">
                {{ $t(`RAMON.LINHA_DA_VIDA.MARCOS.${item.marco.key}`) }}
                ({{ item.marco.idade }}
                <template v-if="item.marco.sexo">
                  · {{ item.marco.sexo === 'M' ? $t('RAMON.DRAWER.PESSOA.SEX_M') : $t('RAMON.DRAWER.PESSOA.SEX_F') }}</template>)
              </span>
            </template>
            <template v-else-if="item.type === 'dcb'">
              <span class="text-sm text-n-slate-12">
                {{ $t('RAMON.LINHA_DA_VIDA.DCB_OF', { name: item.lead.name }) }}
              </span>
            </template>
            <template v-else>
              <span class="text-sm text-n-slate-12">
                {{
                  $t('RAMON.LINHA_DA_VIDA.PRESCRIPTION_OF', {
                    name: item.lead.name,
                  })
                }}
              </span>
            </template>
          </li>
        </ul>
        <p class="mt-2 text-xs text-n-slate-9">
          {{ $t('RAMON.LINHA_DA_VIDA.DISCLAIMER') }}
        </p>
      </section>

      <!-- PRESENTE -->
      <section class="mb-8" data-testid="lifeline-present">
        <h2 class="mb-2 text-sm uppercase tracking-widest text-n-slate-9">
          {{ $t('RAMON.LINHA_DA_VIDA.PRESENT') }}
        </h2>
        <p v-if="!openLeads.length" class="text-sm text-n-slate-9">
          {{ $t('RAMON.LINHA_DA_VIDA.PRESENT_EMPTY') }}
        </p>
        <ul class="flex flex-col gap-2">
          <li
            v-for="lead in openLeads"
            :key="lead.id"
            class="p-3 rounded-lg bg-n-alpha-1 border border-n-weak"
          >
            <div class="flex items-center justify-between gap-2">
              <span class="text-sm text-n-slate-12">{{ lead.name }}</span>
              <span
                class="px-2 py-0.5 text-xs rounded-full"
                :style="{ backgroundColor: lead.stage_color || 'transparent' }"
              >
                {{ lead.stage_name }}
              </span>
            </div>
            <p class="text-xs text-n-slate-10">
              <span v-if="lead.benefit_type_name">{{ lead.benefit_type_name }} · </span>
              <span v-if="lead.thesis_name">{{ lead.thesis_name }} · </span>
              <span v-if="lead.value">{{ formatBrl(lead.value) }}</span>
            </p>
            <router-link
              v-if="lead.conversation_id"
              :to="conversationUrl(lead)"
              class="text-xs text-n-iris-11 hover:underline"
            >
              {{ $t('RAMON.FUNIL.OPEN_CONVERSATION') }}
            </router-link>
          </li>
        </ul>
      </section>

      <!-- PASSADO -->
      <section class="mb-8" data-testid="lifeline-past">
        <h2 class="mb-2 text-sm uppercase tracking-widest text-n-slate-9">
          {{ $t('RAMON.LINHA_DA_VIDA.PAST') }}
        </h2>
        <p v-if="!closedLeads.length" class="text-sm text-n-slate-9">
          {{ $t('RAMON.LINHA_DA_VIDA.PAST_EMPTY') }}
        </p>
        <ul class="flex flex-col gap-2">
          <li
            v-for="lead in closedLeads"
            :key="lead.id"
            class="flex items-baseline gap-3 p-3 rounded-lg bg-n-alpha-1 border border-n-weak"
          >
            <span class="text-xs tabular-nums text-n-slate-10 shrink-0">
              {{ fmtDate(lead.won_at || lead.lost_at) }}
            </span>
            <div>
              <span class="text-sm text-n-slate-12">{{ lead.name }}</span>
              <span
                class="ml-2 text-xs"
                :class="lead.is_won ? 'text-n-teal-11' : 'text-n-ruby-11'"
              >
                {{
                  lead.is_won
                    ? $t('RAMON.LINHA_DA_VIDA.WON')
                    : $t('RAMON.LINHA_DA_VIDA.LOST')
                }}
              </span>
              <p class="text-xs text-n-slate-10">
                <span v-if="lead.benefit_type_name">{{ lead.benefit_type_name }} · </span>
                <span v-if="lead.value">{{ formatBrl(lead.value) }}</span>
                <span v-if="lead.lost_reason"> · {{ lead.lost_reason }}</span>
              </p>
            </div>
          </li>
        </ul>
      </section>
    </template>
  </div>
</template>
```

- [ ] **Step 3: Rota**

`ramon.routes.js` — adicionar entry:

```js
  {
    path: frontendURL('accounts/:accountId/ramon/pessoa/:contactId'),
    name: 'ramon_linha_da_vida',
    component: () => import('./pages/LinhaDaVida.vue'),
    meta: { permissions: ['administrator', 'agent'], world: 'intranet' },
  },
```

- [ ] **Step 4: Link na gaveta**

`LeadDrawer.vue` — após o botão "abrir conversa" (linha ~53), adicionar:

```html
      <router-link
        v-if="lead.contact_id"
        data-testid="drawer-linha-da-vida"
        :to="{
          name: 'ramon_linha_da_vida',
          params: { contactId: lead.contact_id },
        }"
        class="flex items-center gap-1 mt-2 px-3 py-1.5 text-sm rounded-lg bg-n-alpha-1 text-n-slate-12 border border-n-weak hover:bg-n-alpha-2"
        @click="close"
      >
        <span class="i-lucide-git-commit-vertical size-4" />{{
          $t('RAMON.LINHA_DA_VIDA.OPEN')
        }}
      </router-link>
```

- [ ] **Step 5: i18n**

`en/ramon.json` — bloco novo no nível de PLAYBOOKS/DRAWER dentro de RAMON:

```json
    "LINHA_DA_VIDA": {
      "OPEN": "Life timeline",
      "LOADING": "Loading…",
      "ERROR": "Could not load this person's timeline",
      "BORN_AT": "born",
      "NO_BIRTHDATE_HINT": "Add the birth date to unlock the rights calendar.",
      "FUTURE": "Future",
      "FUTURE_EMPTY": "No upcoming milestones.",
      "PRESENT": "Present",
      "PRESENT_EMPTY": "No open case in the funnel.",
      "PAST": "Past",
      "PAST_EMPTY": "No closed cases yet.",
      "WON": "won",
      "LOST": "lost",
      "DCB_OF": "Benefit cessation (DCB) — {name}",
      "PRESCRIPTION_OF": "Starts losing installments (5-year limit) — {name}",
      "DISCLAIMER": "Opportunity radar based on age only — not legal advice.",
      "MARCOS": {
        "aposentadoria_idade_urbana": "Reaches urban retirement age",
        "aposentadoria_idade_rural": "Reaches rural retirement age",
        "bpc_loas_idoso": "Reaches BPC/LOAS age (elderly)"
      }
    },
```

`pt_BR/ramon.json` — mesma posição:

```json
    "LINHA_DA_VIDA": {
      "OPEN": "Linha da Vida",
      "LOADING": "Carregando…",
      "ERROR": "Não foi possível carregar a linha da vida",
      "BORN_AT": "nascimento",
      "NO_BIRTHDATE_HINT": "Cadastre a data de nascimento para ver o calendário de direitos.",
      "FUTURE": "Futuro",
      "FUTURE_EMPTY": "Nenhum marco à vista.",
      "PRESENT": "Presente",
      "PRESENT_EMPTY": "Nenhum caso aberto no funil.",
      "PAST": "Passado",
      "PAST_EMPTY": "Nenhum caso fechado ainda.",
      "WON": "ganho",
      "LOST": "perdido",
      "DCB_OF": "Cessação do benefício (DCB) — {name}",
      "PRESCRIPTION_OF": "Começa a perder parcelas (prescrição quinquenal) — {name}",
      "DISCLAIMER": "Radar de oportunidade por idade — não é parecer jurídico.",
      "MARCOS": {
        "aposentadoria_idade_urbana": "Atinge a idade da aposentadoria urbana",
        "aposentadoria_idade_rural": "Atinge a idade da aposentadoria rural",
        "bpc_loas_idoso": "Atinge a idade do BPC/LOAS (idoso)"
      }
    },
```

- [ ] **Step 6: Prettier + commit**

Run: `npx prettier --write` nos arquivos tocados.

```bash
git add app/javascript/dashboard/api/linhaDaVida.js app/javascript/dashboard/routes/dashboard/ramon/pages/LinhaDaVida.vue app/javascript/dashboard/routes/dashboard/ramon/ramon.routes.js app/javascript/dashboard/routes/dashboard/ramon/components/kanban/LeadDrawer.vue app/javascript/dashboard/i18n/locale/en/ramon.json app/javascript/dashboard/i18n/locale/pt_BR/ramon.json
git commit --no-verify -m "feat(ramon): tela Linha da Vida (passado/presente/futuro) por pessoa"
```

---

## Verificação final (whole-branch)

- Item 19 do plano mestre (aviso de duplicado no NewLeadModal) já existe e continua correto com o critério novo — registrar no PR.
- Push, PR base `ramon`, título `feat: linha da vida - pessoa != caso, N casos e calendario etario` (Conventional Commits). Corpo avisa: **mergear após o PR #41** (branch stacked; os commits do honorário somem do diff quando #41 mergear).
- CI: `gh pr view <N> --json statusCheckRollup` — N/N completed + zero não-success.
- Deploy (gate Eduardo): migração nova SEM backfill → ordem indiferente, mas manter o padrão `rails db:migrate` antes da imagem.
