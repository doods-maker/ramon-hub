# Painel do Cliente — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cliente da banca entra em `cliente.ramonantonio.adv.br` com e-mail + código, vê só os processos dele (espelho do ADVBOX em linguagem simples), envia documentos pedidos (foto/PDF → Drive + tarefa ADVBOX) e assina documentos do ZapSign embutidos na página.

**Architecture:** Tudo dentro do ramon-hub (Rails 7 + Vue 3). Controllers ERB server-rendered em `Cliente::` (namespace `Portal` já é do help center), sessão em cookie criptografado, espelho = 1 JSON por cliente (`portal_clientes.processos`) refeito à noite pelo Sidekiq (`Ramon::PortalSyncJob`). Tela do escritório = página Vue "Painel do cliente" + API JSON `portal_clientes`. Upload → ActiveStorage → job (Drive → `create_post` ADVBOX → ntfy). ZapSign: hub cria doc por modelo, portal embute o widget, webhook com header secreto confirma via `GET /docs/{token}/`.

**Tech Stack:** Rails 7 (ERB, ActiveStorage/R2, Sidekiq + sidekiq-cron via `config/schedule.yml`, HTTParty, Marcel, rack_attack), Vue 3 `<script setup>` + Tailwind, RSpec request specs (CI valida — não há ambiente local), Google Drive API (service account), ZapSign API v1, ADVBOX API v1.

**Spec:** `docs/superpowers/specs/2026-09-08-painel-do-cliente-design.md`

## Global Constraints

- **Sem ambiente de teste local** (`CLAUDE.md`): cada "Run test" abaixo é verificado pelo CI do PR. Não mergear com CI vermelho. Merge/deploy autônomos com CI verde (regime desde 09/07).
- **Texto que fala com cliente = gate do Eduardo** (dicionário de etapas, e-mails, termos, textos do painel): o código sobe com rascunho; só vai ao ar com aprovado.
- **Nada sai automático para o cliente**: convite e assinatura só por clique humano no hub; ZapSign com `send_automatic_email: false`.
- **Sem valores, sem download, rodapé de compliance OAB** (já no layout `ramon_portal`).
- **ADVBOX: 500 chamadas/dia por rota**; `User-Agent` obrigatório (já no client).
- **Migração nova → regenerar `db/schema.rb` via scratch DB na VPS** (CI carrega o schema). **Entrypoint não roda migrate** → `db:migrate` à mão na VPS no deploy.
- Vue: eventos camelCase; Composition API `<script setup>`; Tailwind only; i18n em `locale/en/ramon.json` **e** `locale/pt_BR/ramon.json`.
- Ruby: RuboCop 150 colunas; `with_modified_env` nos specs; `bundle exec`.
- Commits: Conventional Commits `type(painel): ...` + trailers de atribuição da sessão.
- Namespace Ruby `Cliente::` (controllers) e prefixo `Portal*` (models/tabelas `portal_*`).

---

## File map

| Arquivo | Responsabilidade |
|---|---|
| `db/migrate/2026090900000{1,2,3}_create_portal_*.rb` | Tabelas `portal_clientes`, `portal_assinaturas`, `portal_envios` |
| `app/models/portal_cliente.rb` | Conta do cliente: código de acesso, termos, espelho, recados |
| `app/models/portal_assinatura.rb`, `app/models/portal_envio.rb` | Doc ZapSign do cliente; arquivo enviado |
| `config/ramon/portal_etapas.yml` | Dicionário etapa→texto simples + regex de marcos (gate Eduardo) |
| `lib/ramon/portal_texto.rb` | Lê o YAML: `etapa`, `marcos`, `encerrado?` |
| `app/services/ramon/portal_sync_service.rb` | Espelha ADVBOX → `processos` de 1 cliente |
| `app/jobs/ramon/portal_sync_job.rb` + `config/schedule.yml` | Sync noturno de todos |
| `app/controllers/cliente/base_controller.rb` | Sessão por cookie, layout, helpers |
| `app/controllers/cliente/sessoes_controller.rb` | E-mail → código → entrar / sair |
| `app/controllers/cliente/painel_controller.rb` | Termos, lista, processo, atualizar, enviar, assinatura |
| `app/views/cliente/**` + `app/views/layouts/ramon_portal.html.erb` | Telas do cliente |
| `app/mailers/ramon/portal_mailer.rb` + views | E-mails de código e convite |
| `config/routes.rb`, `config/initializers/rack_attack.rb` | Rotas `/cliente/*`, throttles |
| `app/controllers/api/v1/accounts/portal_clientes_controller.rb` + `app/policies/portal_cliente_policy.rb` | API do hub |
| `app/javascript/dashboard/api/portalClientes.js`, `.../ramon/pages/PortalClientes.vue`, `ramon.routes.js`, `IntranetSidebar.vue`, `ramon.json` (en + pt_BR) | Tela do hub |
| `app/jobs/ramon/portal_envio_job.rb` | Drive → tarefa ADVBOX → ntfy |
| `lib/ramon/zapsign_client.rb`, `app/jobs/ramon/zapsign_status_job.rb`, `app/controllers/public/api/v1/zapsign_webhooks_controller.rb` | Assinatura |

---

# PR 1 — Modelos

### Task 1: Migrations + models + factories

**Files:**
- Create: `db/migrate/20260909000001_create_portal_clientes.rb`
- Create: `db/migrate/20260909000002_create_portal_assinaturas.rb`
- Create: `db/migrate/20260909000003_create_portal_envios.rb`
- Create: `app/models/portal_cliente.rb`, `app/models/portal_assinatura.rb`, `app/models/portal_envio.rb`
- Modify: `app/models/account.rb:89` (associação)
- Create: `spec/factories/portal_clientes.rb`
- Create: `spec/models/portal_cliente_spec.rb`
- Modify: `db/schema.rb` (regenerado na VPS)

**Interfaces:**
- Produces: `PortalCliente` (`account`, `advbox_customer_id`, `nome`, `cpf`, `email`, `processos` Array<Hash>, `recados` Hash, `gerar_codigo!` → String de 6 dígitos, `codigo_valido?(codigo)` → Boolean, `termos_aceitos?`, `pode_atualizar?`, `processo(lawsuit_id)` → Hash|nil, `has_many :assinaturas`, `has_many :envios`); `PortalAssinatura` (`doc_token`, `signer_token`, `nome`, `status` in `pendente|signed|refused`, `assinado_em`); `PortalEnvio` (`lawsuit_id`, `solicitacao_post_id`, `item`, `drive_file_id`, `advbox_post_id`, `arquivo` attached).

- [ ] **Step 1: Escrever o spec do model (falha: tabela não existe)**

```ruby
# spec/models/portal_cliente_spec.rb
require 'rails_helper'

RSpec.describe PortalCliente do
  let(:cliente) { create(:portal_cliente) }

  it 'gera código de 6 dígitos que valida uma vez e expira em 10 minutos' do
    codigo = cliente.gerar_codigo!
    expect(codigo).to match(/\A\d{6}\z/)
    expect(cliente.codigo_valido?(codigo)).to be true
    expect(cliente.codigo_valido?('000000')).to be false

    travel_to(11.minutes.from_now) { expect(cliente.codigo_valido?(codigo)).to be false }
  end

  it 'consome o código ao validar' do
    codigo = cliente.gerar_codigo!
    cliente.consumir_codigo!
    expect(cliente.codigo_valido?(codigo)).to be false
  end

  it 'só permite atualizar a cada 6 horas' do
    expect(cliente.pode_atualizar?).to be true
    cliente.update!(atualizacao_pedida_em: 1.hour.ago)
    expect(cliente.pode_atualizar?).to be false
    cliente.update!(atualizacao_pedida_em: 7.hours.ago)
    expect(cliente.pode_atualizar?).to be true
  end

  it 'acha o processo do espelho pelo id' do
    cliente.update!(processos: [{ 'id' => 42, 'numero' => '500' }])
    expect(cliente.processo(42)['numero']).to eq '500'
    expect(cliente.processo(1)).to be_nil
  end

  it 'normaliza e-mail e CPF' do
    c = create(:portal_cliente, email: ' Maria@Exemplo.COM ', cpf: '123.456.789-01')
    expect(c.email).to eq 'maria@exemplo.com'
    expect(c.cpf).to eq '12345678901'
  end
end
```

- [ ] **Step 2: Factories**

```ruby
# spec/factories/portal_clientes.rb
FactoryBot.define do
  factory :portal_cliente do
    account
    sequence(:advbox_customer_id) { |n| 14_000_000 + n }
    nome { 'Maria de Lourdes' }
    cpf { '12345678901' }
    sequence(:email) { |n| "cliente#{n}@exemplo.com" }
  end

  factory :portal_assinatura do
    portal_cliente
    sequence(:doc_token) { |n| "doc-#{n}" }
    sequence(:signer_token) { |n| "signer-#{n}" }
    nome { 'Procuração' }
  end

  factory :portal_envio do
    portal_cliente
    lawsuit_id { 14_039_119 }
    solicitacao_post_id { 270_197_305 }
    item { 'CNIS atualizado' }
  end
end
```

- [ ] **Step 3: Migrations** (molde `db/migrate/20260728000001_create_ramon_reunioes.rb`)

```ruby
# db/migrate/20260909000001_create_portal_clientes.rb
class CreatePortalClientes < ActiveRecord::Migration[7.1]
  def change
    create_table :portal_clientes do |t|
      t.references :account, null: false, foreign_key: true
      t.bigint :advbox_customer_id, null: false
      t.string :nome, null: false
      t.string :cpf
      t.string :email, null: false
      t.string :codigo_digest
      t.datetime :codigo_expira_em
      t.datetime :convidado_em
      t.datetime :termos_aceitos_em
      t.datetime :sincronizado_em
      t.datetime :atualizacao_pedida_em
      t.jsonb :processos, null: false, default: []
      t.jsonb :recados, null: false, default: {}
      t.timestamps
    end
    add_index :portal_clientes, [:account_id, :advbox_customer_id], unique: true
    add_index :portal_clientes, [:account_id, :email], unique: true
  end
end
```

```ruby
# db/migrate/20260909000002_create_portal_assinaturas.rb
class CreatePortalAssinaturas < ActiveRecord::Migration[7.1]
  def change
    create_table :portal_assinaturas do |t|
      t.references :portal_cliente, null: false, foreign_key: true
      t.string :doc_token, null: false
      t.string :signer_token
      t.string :nome
      t.string :status, null: false, default: 'pendente'
      t.datetime :assinado_em
      t.timestamps
    end
    add_index :portal_assinaturas, :doc_token, unique: true
  end
end
```

```ruby
# db/migrate/20260909000003_create_portal_envios.rb
class CreatePortalEnvios < ActiveRecord::Migration[7.1]
  def change
    create_table :portal_envios do |t|
      t.references :portal_cliente, null: false, foreign_key: true
      t.bigint :lawsuit_id
      t.bigint :solicitacao_post_id
      t.string :item
      t.string :drive_file_id
      t.string :advbox_post_id
      t.timestamps
    end
    add_index :portal_envios, [:portal_cliente_id, :solicitacao_post_id]
  end
end
```

- [ ] **Step 4: Models**

```ruby
# app/models/portal_cliente.rb
# Conta do Painel do Cliente (cliente.ramonantonio.adv.br): 1 linha por cliente
# do ADVBOX convidado. `processos` é o espelho JSON do ADVBOX (refeito à noite
# pelo Ramon::PortalSyncJob); `recados` = { lawsuit_id => texto } escrito no hub.
# Login = e-mail + código de 6 dígitos (sem senha); o cookie é a sessão.
class PortalCliente < ApplicationRecord
  CODIGO_VALIDADE = 10.minutes
  INTERVALO_ATUALIZACAO = 6.hours

  belongs_to :account
  has_many :assinaturas, class_name: 'PortalAssinatura', dependent: :destroy
  has_many :envios, class_name: 'PortalEnvio', dependent: :destroy

  before_validation :normalizar

  validates :nome, :email, :advbox_customer_id, presence: true
  validates :email, uniqueness: { scope: :account_id }, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :advbox_customer_id, uniqueness: { scope: :account_id }

  def gerar_codigo!
    codigo = format('%06d', SecureRandom.random_number(1_000_000))
    update!(codigo_digest: digest(codigo), codigo_expira_em: CODIGO_VALIDADE.from_now)
    codigo
  end

  def codigo_valido?(codigo)
    return false if codigo_digest.blank? || codigo_expira_em.blank? || codigo_expira_em.past?

    ActiveSupport::SecurityUtils.secure_compare(codigo_digest, digest(codigo.to_s.strip))
  end

  def consumir_codigo!
    update!(codigo_digest: nil, codigo_expira_em: nil)
  end

  def termos_aceitos? = termos_aceitos_em.present?

  def pode_atualizar?
    atualizacao_pedida_em.blank? || atualizacao_pedida_em < INTERVALO_ATUALIZACAO.ago
  end

  def processo(lawsuit_id)
    processos.find { |p| p['id'].to_s == lawsuit_id.to_s }
  end

  def primeiro_nome = nome.to_s.split.first.to_s.capitalize

  private

  def normalizar
    self.email = email.to_s.strip.downcase
    self.cpf = cpf.to_s.delete('^0-9').presence
  end

  # SHA256 com o secret_key_base basta: código de 10 min + throttle no rack_attack.
  def digest(codigo)
    Digest::SHA256.hexdigest("#{codigo}#{Rails.application.secret_key_base}")
  end
end
```

```ruby
# app/models/portal_assinatura.rb
# Documento criado no ZapSign pelo hub para o cliente assinar no painel.
# status espelha o ZapSign: pendente | signed | refused.
class PortalAssinatura < ApplicationRecord
  belongs_to :portal_cliente

  validates :doc_token, presence: true, uniqueness: true

  scope :pendentes, -> { where(status: 'pendente') }

  def sign_url = "https://app.zapsign.com.br/verificar/#{signer_token}"
end
```

```ruby
# app/models/portal_envio.rb
# Arquivo que o cliente subiu pelo painel para um item pedido (tarefa ADVBOX
# "SOLICITAR DOCUMENTOS" = solicitacao_post_id). O job leva pro Drive e abre
# a tarefa "ANALISAR DOCUMENTAÇÃO ENVIADA PELO CLIENTE" (advbox_post_id).
class PortalEnvio < ApplicationRecord
  belongs_to :portal_cliente
  has_one_attached :arquivo

  validates :item, presence: true
end
```

- [ ] **Step 5: Associação na conta** — em `app/models/account.rb` logo após a linha 89 (`has_many :reunioes ...`):

```ruby
  has_many :portal_clientes, dependent: :destroy_async
```

- [ ] **Step 6: Regenerar `db/schema.rb` na VPS** (scratch DB, lição do `CLAUDE.md`). Eduardo roda via `!` se o classificador barrar o ssh:

```bash
ssh root@185.194.216.67 'cd /opt/intranet-ramon && docker compose exec -T postgres psql -U postgres -c "DROP DATABASE IF EXISTS schema_scratch;" -c "CREATE DATABASE schema_scratch;"'
# na branch, com as migrations: copiar db/ pro container web e rodar
ssh root@185.194.216.67 'cd /opt/intranet-ramon && docker compose exec -T -e RAILS_ENV=production -e POSTGRES_DATABASE=schema_scratch chatwoot-web bundle exec rails db:schema:load db:migrate db:schema:dump'
```
Então copiar o `db/schema.rb` gerado de volta para a branch (`docker compose cp chatwoot-web:/app/db/schema.rb ./schema.rb` + scp). Conferir no diff que só entraram as 3 tabelas.

- [ ] **Step 7: Commit + PR 1**

```bash
git add db/migrate/20260909000001_create_portal_clientes.rb db/migrate/20260909000002_create_portal_assinaturas.rb db/migrate/20260909000003_create_portal_envios.rb db/schema.rb app/models/portal_cliente.rb app/models/portal_assinatura.rb app/models/portal_envio.rb app/models/account.rb spec/factories/portal_clientes.rb spec/models/portal_cliente_spec.rb
git commit -m "feat(painel): modelos do Painel do Cliente (portal_clientes, assinaturas, envios)"
```
Run (CI): `bundle exec rspec spec/models/portal_cliente_spec.rb` → 5 exemplos verdes.

---

# PR 2 — Dicionário de etapas + sync noturno

### Task 2: `config/ramon/portal_etapas.yml` + `Ramon::PortalTexto`

**Files:**
- Create: `config/ramon/portal_etapas.yml`
- Create: `lib/ramon/portal_texto.rb`
- Create: `spec/lib/ramon/portal_texto_spec.rb`

**Interfaces:**
- Produces: `Ramon::PortalTexto.etapa(stage) → { 'titulo' =>, 'o_que_esperar' => }`; `Ramon::PortalTexto.marcos(andamentos) → Array<{ 'data', 'titulo', 'tipo', 'explicacao' }>` (mais recente por tipo, ordem cronológica); `Ramon::PortalTexto.encerrado?(step) → Boolean`; `Ramon::PortalTexto.normalizar(str)` (transliterado, upcase, squish).

- [ ] **Step 1: Spec**

```ruby
# spec/lib/ramon/portal_texto_spec.rb
require 'rails_helper'

RSpec.describe Ramon::PortalTexto do
  it 'traduz etapa conhecida (case/acento insensível)' do
    etapa = described_class.etapa('Pericia Agendada')
    expect(etapa['titulo']).to eq 'Perícia agendada'
    expect(etapa['o_que_esperar']).to be_present
  end

  it 'etapa desconhecida cai no texto neutro' do
    expect(described_class.etapa('ETAPA NOVA')['titulo']).to eq 'Etapa nova'
    expect(described_class.etapa(nil)['titulo']).to eq 'Em andamento'
  end

  it 'cobre todas as etapas da conta (settings de 08/09/2026)' do
    etapas = YAML.load_file(Rails.root.join('spec/fixtures/advbox_stages.yml'))
    faltando = etapas.reject { |nome| described_class::ETAPAS.key?(described_class.normalizar(nome)) }
    expect(faltando).to eq([])
  end

  it 'reconhece marcos e mantém só o mais recente de cada tipo, em ordem cronológica' do
    andamentos = [
      { 'data' => '2026-03-01', 'titulo' => 'Juntada de petição' },
      { 'data' => '2026-04-10', 'titulo' => 'Perícia médica designada' },
      { 'data' => '2026-06-01', 'titulo' => 'Perícia realizada' },
      { 'data' => '2026-08-15', 'titulo' => 'Sentença proferida' }
    ]
    marcos = described_class.marcos(andamentos)
    expect(marcos.map { |m| m['tipo'] }).to eq %w[pericia sentenca]
    expect(marcos.first['data']).to eq '2026-06-01'
  end

  it 'encerrado só na fase ARQUIVAMENTO' do
    expect(described_class.encerrado?('ARQUIVAMENTO')).to be true
    expect(described_class.encerrado?('RH/FINANCEIRO')).to be false
  end
end
```

Fixture `spec/fixtures/advbox_stages.yml` = lista YAML das 60 etapas (nomes exatos do `/settings` de 08/09/2026, uma por linha com `- `): CONTRATO FECHADO, REUNIÃO PÓS VENDA, DOCUMENTOS SOLICITADOS - MKT, DOCUMENTOS RECEBIDOS - CONFERIR - MKT, DISTRIBUIR AO TIME OPERACIONAL - MKT, ATENDIMENTO INICIAL, CONTRATO FECHADO / AG. DOCTOS, DOCTOS RECEBIDOS - CONFERIR, DISTRIBUIR AO TIME OPERACIONAL, BENEFÍCIO FUTURO / ANOTAR NA AGENDA, ELABORAÇÃO DE CONTRATO, PLANEJAMENTO PREVIDENCIÁRIO, AGUARDANDO RETORNO/DOCUMENTOS, BENEFÍCIO CONCEDIDO / IMPLANTAÇÃO, IMPROCEDENTE / MONTAR INICIAL, TAREFAS ADMINISTRATIVAS, AGUARDANDO PROTOCOLO, REQUERIMENTO PROTOCOLADO, CARTA DE EXIGÊNCIAS, PERICIA AGENDADA, DECISÃO PROFERIDA, RECURSO ADMINISTRATIVO PROTOCOLADO, DECISÃO DO RECURSO PROFERIDA, AGUARDANDO PAGAMENTO HONORÁRIOS, AGUARDANDO CÓPIA DO PROCESSO ADMINISTRATIVO, CONFERIR SAQUE, AGUARDANDO DOCUMENTOS, SENTENÇA PROFERIDA, NEGADO / AVISAR CLIENTE, AÇÃO PROTOCOLADA, PROCESSO SUBSTABELECIDO PARA OUTRO(A) ADV, DESENVOLVENDO INICIAL / DEFESA, INICIAL / DEFESA PROTOCOLADA, FASE DE INSTRUÇÃO, AUDIÊNCIA / PERÍCIA REALIZADA, PROPOSTA DE ACORDO - ANALISAR, PRAZO MANIF / RÉPLICA / RAZÕES FINAIS, PROCESSO SOBRESTADO, RECURSO PROTOCOLADO, PRAZO DE CONTRARRAZÕES, AGUARDANDO JULGAMENTO DO RECURSO, RECURSO JULGADO, PRAZO RECURSAL, AGUARDANDO EXECUÇÃO, EXECUÇÃO COMO EXEQUENTE, EXECUÇÃO COMO DEVEDOR, PENHORA REALIZADA, PRAZO DE EMBARGOS / IMPUGNAÇÃO, RPV / PRECATÓRIO EMITIDO, PAGAMENTO RECEBIDO / PAGAR CLIENTE, EXECUÇÃO FINALIZADA / CUSTAS PENDENTES, AGUARDANDO ARQUIVAMENTO, PAGAMENTO REALIZADO, PRESTAR CONTAS E PAGAR AO CLIENTE, ANALISADO E NÃO DISTRIBUÍDO, ARQUIVADO POR DESINTERESSE CLIENTE, ARQUIVADO POR DETERMINAÇÃO JUDICIAL, ARQUIVADO/ENCERRADO.

- [ ] **Step 2: YAML** — chaves = nome da etapa **normalizado** (sem acento, maiúsculo). Textos abaixo são **rascunho para o Eduardo aprovar** (voz "médico de confiança", sem prazo, sem promessa). Escrever as 60; exemplos do padrão:

```yaml
# config/ramon/portal_etapas.yml
# Dicionário do Painel do Cliente. Chave = nome da etapa do ADVBOX normalizado
# (Ramon::PortalTexto.normalizar). Texto fala com o cliente: simples, sem prazo,
# sem promessa de resultado (Prov. 205/2021 OAB). RASCUNHO — aprovação do Eduardo.
etapas:
  'CONTRATO FECHADO':
    titulo: 'Contrato assinado'
    o_que_esperar: 'Seu caso entrou na nossa fila de preparação. Em breve pediremos os documentos que faltam.'
  'REQUERIMENTO PROTOCOLADO':
    titulo: 'Pedido protocolado no INSS'
    o_que_esperar: 'O INSS recebeu o pedido e vai analisar. Acompanhamos e avisamos você a cada novidade.'
  'CARTA DE EXIGENCIAS':
    titulo: 'INSS pediu documentos'
    o_que_esperar: 'O INSS pediu algo a mais. Se precisarmos de você, o pedido aparece aqui em "Documentos".'
  'PERICIA AGENDADA':
    titulo: 'Perícia agendada'
    o_que_esperar: 'Leve todos os laudos, exames e receitas no dia. Em caso de dúvida, fale com a equipe.'
  'DECISAO PROFERIDA':
    titulo: 'INSS decidiu o pedido'
    o_que_esperar: 'Estamos analisando a decisão e o melhor caminho a seguir. Entraremos em contato.'
  'ACAO PROTOCOLADA':
    titulo: 'Ação protocolada na Justiça'
    o_que_esperar: 'O processo está com o juiz. A Justiça tem o próprio ritmo; acompanhamos de perto.'
  'FASE DE INSTRUCAO':
    titulo: 'Fase de provas'
    o_que_esperar: 'O juiz está reunindo provas: pode marcar perícia ou audiência. Se for o caso, avisamos você.'
  'SENTENCA PROFERIDA':
    titulo: 'Juiz deu a sentença'
    o_que_esperar: 'Estamos analisando a sentença. Explicaremos o resultado e os próximos passos.'
  'RECURSO PROTOCOLADO':
    titulo: 'Recurso apresentado'
    o_que_esperar: 'Levamos o caso para a instância superior. O julgamento não tem data fixa.'
  'RPV / PRECATORIO EMITIDO':
    titulo: 'Pagamento em processamento'
    o_que_esperar: 'A Justiça emitiu a ordem de pagamento. Avisamos quando o valor for liberado.'
  'ARQUIVADO/ENCERRADO':
    titulo: 'Processo encerrado'
    o_que_esperar: 'Este processo foi concluído. Se precisar de algo, fale com a equipe.'
  # ... (as demais 49 etapas no mesmo formato)
marcos:
  - { tipo: pericia,   regex: 'per[ií]cia',                    titulo: 'Perícia',              explicacao: 'Avaliação médica do INSS ou da Justiça.' }
  - { tipo: audiencia, regex: 'audi[êe]ncia',                  titulo: 'Audiência',            explicacao: 'Encontro com o juiz para ouvir as partes e testemunhas.' }
  - { tipo: protocolo, regex: 'distribu[ií]d|protocol|autuad', titulo: 'Processo protocolado', explicacao: 'O pedido entrou oficialmente.' }
  - { tipo: sentenca,  regex: 'senten[çc]a|ac[óo]rd[ãa]o',      titulo: 'Decisão do juiz',      explicacao: 'O juiz decidiu. Nossa equipe explica o resultado.' }
  - { tipo: concessao, regex: 'implanta|concedid|deferid',     titulo: 'Benefício concedido',  explicacao: 'O benefício foi liberado.' }
```

- [ ] **Step 3: Implementação**

```ruby
# lib/ramon/portal_texto.rb
# Tradução do ADVBOX para a língua do cliente (config/ramon/portal_etapas.yml).
# Calculado no render: mudar o YAML não exige re-sincronizar o espelho.
module Ramon::PortalTexto
  DADOS = YAML.load_file(Rails.root.join('config/ramon/portal_etapas.yml')).freeze
  ETAPAS = DADOS['etapas'].freeze
  MARCOS = DADOS['marcos'].map { |m| m.merge('re' => Regexp.new(m['regex'], Regexp::IGNORECASE)) }.freeze
  FASE_ENCERRADA = 'ARQUIVAMENTO'.freeze

  module_function

  def normalizar(str)
    I18n.transliterate(str.to_s).upcase.squish
  end

  def etapa(stage)
    return { 'titulo' => 'Em andamento', 'o_que_esperar' => 'Nossa equipe está cuidando do seu caso.' } if stage.blank?

    ETAPAS[normalizar(stage)] || { 'titulo' => stage.to_s.downcase.capitalize,
                                   'o_que_esperar' => 'Nossa equipe está cuidando desta etapa. Avisamos você a cada avanço.' }
  end

  # andamentos: [{ 'data' => 'YYYY-MM-DD', 'titulo' => }] em qualquer ordem.
  def marcos(andamentos)
    por_tipo = {}
    Array(andamentos).sort_by { |a| a['data'].to_s }.each do |a|
      texto = I18n.transliterate(a['titulo'].to_s)
      marco = MARCOS.find { |m| m['re'].match?(texto) }
      next unless marco

      por_tipo[marco['tipo']] = { 'data' => a['data'], 'tipo' => marco['tipo'],
                                  'titulo' => marco['titulo'], 'explicacao' => marco['explicacao'] }
    end
    por_tipo.values.sort_by { |m| m['data'].to_s }
  end

  def encerrado?(step)
    normalizar(step) == FASE_ENCERRADA
  end
end
```

- [ ] **Step 4: Commit**

```bash
git add config/ramon/portal_etapas.yml lib/ramon/portal_texto.rb spec/lib/ramon/portal_texto_spec.rb spec/fixtures/advbox_stages.yml
git commit -m "feat(painel): dicionário de etapas e marcos em linguagem de cliente"
```

### Task 3: `Ramon::PortalSyncService` + `Ramon::PortalSyncJob` + schedule

**Files:**
- Create: `app/services/ramon/portal_sync_service.rb`
- Create: `app/jobs/ramon/portal_sync_job.rb`
- Modify: `config/schedule.yml` (append)
- Create: `spec/services/ramon/portal_sync_service_spec.rb`

**Interfaces:**
- Consumes: `Ramon::AdvboxClient.lawsuits(identification:, limit:)`, `.movements(id, limit:)`, `.posts(lawsuit_id:, limit:)` — envelopes `{ 'data' => [...] }`.
- Produces: `Ramon::PortalSyncService.new(cliente).perform → Array<Hash>` e grava `processos` + `sincronizado_em`. Shape de cada processo:
  `{ 'id', 'numero', 'tipo', 'inicio', 'responsavel', 'responsavel_id', 'etapa', 'fase', 'andamentos' => [{ 'data', 'titulo' }], 'docs_pendentes' => [{ 'item', 'post_id' }] }`.
  Constante `Ramon::PortalSyncService::TAREFA_SOLICITAR = 'SOLICITAR DOCUMENTOS'`.

- [ ] **Step 1: Spec com payload no formato real da API**

```ruby
# spec/services/ramon/portal_sync_service_spec.rb
require 'rails_helper'

RSpec.describe Ramon::PortalSyncService do
  let(:cliente) { create(:portal_cliente, cpf: '12345678901') }
  let(:lawsuits) do
    { 'data' => [{ 'id' => 14_039_119, 'process_number' => '5003800-40.2022.4.04.7207', 'type' => 'AUXÍLIO-ACIDENTE',
                   'process_date' => '2022-05-02', 'responsible' => 'RAMON ANTONIO', 'responsible_id' => 259_713,
                   'stage' => 'FASE DE INSTRUÇÃO', 'step' => 'JUDICIAL' }] }
  end
  let(:movements) { { 'data' => [{ 'date' => '2026-06-01', 'title' => 'Perícia realizada', 'header' => 'x' }] } }
  let(:posts) do
    { 'data' => [
      { 'id' => 1, 'task' => 'SOLICITAR DOCUMENTOS', 'notes' => "CNIS atualizado\nLaudo médico\n",
        'users' => [{ 'user_id' => 259_713, 'completed' => nil }] },
      { 'id' => 2, 'task' => 'SOLICITAR DOCUMENTOS', 'notes' => 'RG', 'users' => [{ 'completed' => '2026-08-01 10:00:00' }] },
      { 'id' => 3, 'task' => 'ACOMPANHAR PERÍCIA', 'notes' => 'interno', 'users' => [{ 'completed' => nil }] }
    ] }
  end

  before do
    allow(Ramon::AdvboxClient).to receive(:lawsuits).with(identification: '12345678901', limit: 20).and_return(lawsuits)
    allow(Ramon::AdvboxClient).to receive(:movements).with(14_039_119, limit: 30).and_return(movements)
    allow(Ramon::AdvboxClient).to receive(:posts).with(lawsuit_id: 14_039_119, limit: 50).and_return(posts)
  end

  it 'espelha processos, andamentos e só os pedidos de documento abertos' do
    processos = described_class.new(cliente).perform
    p = processos.first
    expect(p.slice('id', 'numero', 'etapa', 'fase', 'responsavel_id'))
      .to eq('id' => 14_039_119, 'numero' => '5003800-40.2022.4.04.7207', 'etapa' => 'FASE DE INSTRUÇÃO',
             'fase' => 'JUDICIAL', 'responsavel_id' => 259_713)
    expect(p['andamentos']).to eq([{ 'data' => '2026-06-01', 'titulo' => 'Perícia realizada' }])
    expect(p['docs_pendentes']).to eq([{ 'item' => 'CNIS atualizado', 'post_id' => 1 }, { 'item' => 'Laudo médico', 'post_id' => 1 }])
    expect(cliente.reload.sincronizado_em).to be_present
  end

  it 'sem CPF não chama a API e mantém o espelho' do
    cliente.update!(cpf: nil, processos: [{ 'id' => 1 }])
    expect(described_class.new(cliente).perform).to eq([{ 'id' => 1 }])
    expect(Ramon::AdvboxClient).not_to have_received(:lawsuits)
  end
end
```

- [ ] **Step 2: Service**

```ruby
# app/services/ramon/portal_sync_service.rb
# Espelho do ADVBOX para 1 cliente do painel: processos por CPF + andamentos +
# pedidos de documento abertos. 1 + 2×N chamadas (limite 500/dia/rota).
# ponytail: sync cheio por cliente; passando de ~250 clientes, varrer
# /last_movements e re-buscar só os processos cuja última data mudou.
class Ramon::PortalSyncService
  TAREFA_SOLICITAR = 'SOLICITAR DOCUMENTOS'.freeze
  LIMITE_PROCESSOS = 20
  LIMITE_ANDAMENTOS = 30
  LIMITE_TAREFAS = 50

  def initialize(cliente)
    @cliente = cliente
  end

  def perform
    return @cliente.processos if @cliente.cpf.blank?

    processos = lista(Ramon::AdvboxClient.lawsuits(identification: @cliente.cpf, limit: LIMITE_PROCESSOS))
                .map { |l| espelho(l) }
    @cliente.update!(processos: processos, sincronizado_em: Time.current)
    processos
  end

  private

  def espelho(lawsuit)
    id = lawsuit['id']
    {
      'id' => id,
      'numero' => lawsuit['process_number'],
      'tipo' => lawsuit['type'],
      'inicio' => lawsuit['process_date'] || lawsuit['date'],
      'responsavel' => lawsuit['responsible'],
      'responsavel_id' => lawsuit['responsible_id'],
      'etapa' => lawsuit['stage'],
      'fase' => lawsuit['step'],
      'andamentos' => andamentos(id),
      'docs_pendentes' => docs_pendentes(id)
    }
  end

  def andamentos(id)
    lista(Ramon::AdvboxClient.movements(id, limit: LIMITE_ANDAMENTOS))
      .map { |m| { 'data' => m['date'].to_s[0, 10], 'titulo' => m['title'] } }
  end

  def docs_pendentes(id)
    lista(Ramon::AdvboxClient.posts(lawsuit_id: id, limit: LIMITE_TAREFAS))
      .select { |p| p['task'].to_s.casecmp?(TAREFA_SOLICITAR) && aberta?(p) }
      .flat_map { |p| p['notes'].to_s.lines.map(&:strip).reject(&:blank?).map { |item| { 'item' => item, 'post_id' => p['id'] } } }
  end

  def aberta?(post)
    Array(post['users']).none? { |u| u['completed'].present? }
  end

  # Envelope das listas do ADVBOX: { offset, limit, totalCount, data } — nunca Array.
  def lista(resposta)
    Array(resposta.is_a?(Hash) ? resposta['data'] : resposta)
  end
end
```

- [ ] **Step 3: Job + schedule**

```ruby
# app/jobs/ramon/portal_sync_job.rb
# Espelho noturno do Painel do Cliente. Falha de um cliente não derruba os outros.
class Ramon::PortalSyncJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    PortalCliente.where.not(convidado_em: nil).find_each do |cliente|
      Ramon::PortalSyncService.new(cliente).perform
    rescue Ramon::AdvboxClient::UnavailableError, Ramon::AdvboxClient::RequestError => e
      Rails.logger.warn("[Ramon::PortalSyncJob] cliente=#{cliente.id} #{e.class}: #{e.message}")
    end
  end
end
```

Append em `config/schedule.yml`:

```yaml

# executed daily at 0330 UTC = 00:30 America/Sao_Paulo (UTC-3)
# espelho do Painel do Cliente (processos/andamentos/pedidos do ADVBOX por cliente)
ramon_portal_sync_job:
  cron: '30 3 * * *'
  class: 'Ramon::PortalSyncJob'
  queue: scheduled_jobs
```

- [ ] **Step 4: Commit + PR 2**

```bash
git add app/services/ramon/portal_sync_service.rb app/jobs/ramon/portal_sync_job.rb config/schedule.yml spec/services/ramon/portal_sync_service_spec.rb
git commit -m "feat(painel): espelho noturno do ADVBOX por cliente (PortalSyncService/Job)"
```
Run (CI): `bundle exec rspec spec/services/ramon/portal_sync_service_spec.rb spec/lib/ramon/portal_texto_spec.rb spec/configs/schedule_spec.rb`.

---

# PR 3 — Portal do cliente (leitura)

### Task 4: Base + sessões (e-mail → código → cookie) + mailer

**Files:**
- Create: `app/controllers/cliente/base_controller.rb`, `app/controllers/cliente/sessoes_controller.rb`
- Create: `app/views/cliente/sessoes/new.html.erb`, `app/views/cliente/sessoes/codigo.html.erb`
- Create: `app/mailers/ramon/portal_mailer.rb`, `app/views/mailers/ramon/portal_mailer/codigo.html.erb`, `app/views/mailers/ramon/portal_mailer/convite.html.erb`
- Modify: `config/routes.rb` (após a linha 709, fora do `namespace :public`)
- Modify: `config/initializers/rack_attack.rb` (após o bloco `public/portal_upload`, ~linha 221)
- Modify: `app/views/layouts/ramon_portal.html.erb` (CSS de formulário)
- Create: `spec/requests/cliente/sessoes_spec.rb`

**Interfaces:**
- Produces: cookie `cookies.encrypted[:ramon_cliente]` = id; helper `current_cliente` em `Cliente::BaseController`; rotas `cliente_root_path` (GET /cliente), `cliente_codigo_path` (POST /cliente/codigo), `cliente_entrar_path` (POST /cliente/entrar), `cliente_sair_path` (DELETE /cliente/sair), `cliente_inicio_path` (GET /cliente/inicio); `Ramon::PortalMailer.with(account:, cliente:, codigo:).codigo` e `.with(account:, cliente:).convite`. ENV `PORTAL_URL` (link do convite).

- [ ] **Step 1: Spec**

```ruby
# spec/requests/cliente/sessoes_spec.rb
require 'rails_helper'

RSpec.describe 'Painel do cliente — sessões', type: :request do
  let(:account) { create(:account) }
  let!(:cliente) { create(:portal_cliente, account: account, email: 'maria@exemplo.com', convidado_em: 1.day.ago) }

  it 'GET /cliente mostra o formulário de e-mail' do
    get '/cliente'
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Seu e-mail')
  end

  it 'e-mail desconhecido recebe a mesma tela neutra e não manda e-mail' do
    expect { post '/cliente/codigo', params: { email: 'ninguem@exemplo.com' } }
      .not_to have_enqueued_mail(Ramon::PortalMailer, :codigo)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Se este e-mail estiver cadastrado')
  end

  it 'e-mail conhecido gera código e enfileira o e-mail' do
    expect { post '/cliente/codigo', params: { email: ' Maria@Exemplo.com ' } }
      .to have_enqueued_mail(Ramon::PortalMailer, :codigo)
    expect(cliente.reload.codigo_digest).to be_present
  end

  it 'código certo entra, consome o código e redireciona pro início' do
    codigo = cliente.gerar_codigo!
    post '/cliente/entrar', params: { email: 'maria@exemplo.com', codigo: codigo }
    expect(response).to redirect_to('/cliente/inicio')
    expect(cliente.reload.codigo_digest).to be_nil
    get '/cliente/inicio'
    expect(response).to have_http_status(:ok)
  end

  it 'código errado devolve 422 sem sessão' do
    cliente.gerar_codigo!
    post '/cliente/entrar', params: { email: 'maria@exemplo.com', codigo: '000000' }
    expect(response).to have_http_status(:unprocessable_entity)
    get '/cliente/inicio'
    expect(response).to redirect_to('/cliente')
  end

  it 'sair apaga a sessão' do
    post '/cliente/entrar', params: { email: 'maria@exemplo.com', codigo: cliente.gerar_codigo! }
    delete '/cliente/sair'
    get '/cliente/inicio'
    expect(response).to redirect_to('/cliente')
  end
end
```

- [ ] **Step 2: Rotas** — em `config/routes.rb`, depois da linha 709 (`post 'portal/:token/upload' ...`):

```ruby
  # Painel do Cliente (cliente.ramonantonio.adv.br → Caddy redir / → /cliente).
  # Fora do namespace :public (força JSON) e fora de Portal:: (help center).
  scope path: 'cliente', module: :cliente, as: :cliente do
    get '/', to: 'sessoes#new', as: :root
    post 'codigo', to: 'sessoes#create', as: :codigo
    post 'entrar', to: 'sessoes#verificar', as: :entrar
    delete 'sair', to: 'sessoes#destroy', as: :sair
    get 'inicio', to: 'painel#show', as: :inicio
    post 'termos', to: 'painel#aceitar_termos', as: :termos
    post 'atualizar', to: 'painel#atualizar', as: :atualizar
    get 'processos/:lawsuit_id', to: 'painel#processo', as: :processo
    post 'processos/:lawsuit_id/envios', to: 'painel#enviar', as: :envios
    get 'assinaturas/:id', to: 'painel#assinatura', as: :assinatura
  end
```

- [ ] **Step 3: Throttles** — `config/initializers/rack_attack.rb`, após o bloco `public/portal_upload`:

```ruby
  ## Ramon — Painel do Cliente: código por e-mail (força bruta) ###
  throttle('cliente/codigo/email', limit: 5, period: 15.minutes) do |req|
    req.params['email'].to_s.strip.downcase.presence if req.post? && req.path.in?(%w[/cliente/codigo /cliente/entrar])
  end
  throttle('cliente/codigo/ip', limit: 10, period: 15.minutes) do |req|
    req.ip if req.post? && req.path.in?(%w[/cliente/codigo /cliente/entrar])
  end
  throttle('cliente/envios', limit: 20, period: 1.hour) do |req|
    req.ip if req.post? && req.path.match?(%r{\A/cliente/processos/\d+/envios\z})
  end
```

- [ ] **Step 4: Controllers**

```ruby
# app/controllers/cliente/base_controller.rb
# Painel do Cliente: páginas ERB server-rendered com sessão em cookie
# criptografado (30 dias, host-only — não vaza pro chat.). Herda de
# ActionController::Base direto (CSRF padrão do Rails nos forms), como o
# Public::PortalController do link mágico.
class Cliente::BaseController < ActionController::Base
  COOKIE = :ramon_cliente
  SESSAO = 30.days

  layout 'ramon_portal'

  helper_method :current_cliente

  private

  def current_cliente
    @current_cliente ||= PortalCliente.find_by(id: cookies.encrypted[COOKIE])
  end

  def require_cliente
    redirect_to cliente_root_path if current_cliente.nil?
  end

  def entrar!(cliente)
    cookies.encrypted[COOKIE] = { value: cliente.id, expires: SESSAO.from_now, httponly: true, same_site: :lax,
                                  secure: ActiveModel::Type::Boolean.new.cast(ENV.fetch('FORCE_SSL', false)) }
  end

  def sair!
    cookies.delete(COOKIE)
  end
end
```

```ruby
# app/controllers/cliente/sessoes_controller.rb
class Cliente::SessoesController < Cliente::BaseController
  MENSAGEM_NEUTRA = 'Se este e-mail estiver cadastrado, você recebe um código em instantes.'.freeze

  def new
    redirect_to cliente_inicio_path if current_cliente
  end

  # Resposta igual para e-mail conhecido e desconhecido (não revela quem tem conta).
  def create
    @email = email_param
    cliente = PortalCliente.find_by(email: @email)
    if cliente&.convidado_em.present?
      codigo = cliente.gerar_codigo!
      Ramon::PortalMailer.with(account: cliente.account, cliente: cliente, codigo: codigo).codigo.deliver_later
    end
    flash.now[:portal_notice] = MENSAGEM_NEUTRA
    render :codigo
  end

  def verificar
    @email = email_param
    cliente = PortalCliente.find_by(email: @email)
    if cliente&.codigo_valido?(params[:codigo])
      cliente.consumir_codigo!
      entrar!(cliente)
      redirect_to cliente_inicio_path
    else
      flash.now[:portal_alert] = 'Código inválido ou vencido. Peça um novo código.'
      render :codigo, status: :unprocessable_entity
    end
  end

  def destroy
    sair!
    redirect_to cliente_root_path
  end

  private

  def email_param = params[:email].to_s.strip.downcase
end
```

- [ ] **Step 5: Views** (classes do layout: `eyebrow`, `divider`, `flash`, `btn-bronze`, `neutral-card`)

```erb
<%# app/views/cliente/sessoes/new.html.erb %>
<p class="eyebrow">Painel do cliente</p>
<h1>Acompanhe o seu caso</h1>
<div class="divider"></div>
<%= form_with url: cliente_codigo_path, method: :post, local: true, class: 'form-portal' do |f| %>
  <%= f.label :email, 'Seu e-mail', class: 'label' %>
  <%= f.email_field :email, required: true, autocomplete: 'email', inputmode: 'email', class: 'input', placeholder: 'nome@exemplo.com' %>
  <%= f.submit 'Receber código', class: 'btn-bronze' %>
<% end %>
<div class="neutral-card">Você recebe um código de 6 dígitos no e-mail cadastrado com o escritório. Não precisa de senha.</div>
```

```erb
<%# app/views/cliente/sessoes/codigo.html.erb %>
<p class="eyebrow">Painel do cliente</p>
<h1>Digite o código</h1>
<div class="divider"></div>
<% if flash[:portal_notice] %><p class="flash flash-notice"><%= flash[:portal_notice] %></p><% end %>
<% if flash[:portal_alert] %><p class="flash flash-alert"><%= flash[:portal_alert] %></p><% end %>
<%= form_with url: cliente_entrar_path, method: :post, local: true, class: 'form-portal' do |f| %>
  <%= f.hidden_field :email, value: @email %>
  <%= f.label :codigo, 'Código de 6 dígitos', class: 'label' %>
  <%= f.text_field :codigo, required: true, inputmode: 'numeric', pattern: '[0-9]{6}', autocomplete: 'one-time-code', class: 'input input-codigo' %>
  <%= f.submit 'Entrar', class: 'btn-bronze' %>
<% end %>
<%= form_with url: cliente_codigo_path, method: :post, local: true do |f| %>
  <%= f.hidden_field :email, value: @email %>
  <%= f.submit 'Pedir outro código', class: 'btn-link' %>
<% end %>
```

CSS a acrescentar no `<style>` de `app/views/layouts/ramon_portal.html.erb` (antes de `</style>`):

```css
    .form-portal { display: flex; flex-direction: column; gap: 10px; margin-bottom: 18px; }
    .label { font-size: 13px; color: #5b4a3a; }
    .input { padding: 12px 14px; border: 1px solid #d9c7ad; border-radius: 10px; font-size: 16px; background: #fff; }
    .input-codigo { letter-spacing: .4em; text-align: center; font-size: 22px; }
    .btn-link { background: none; border: 0; color: #7d5432; text-decoration: underline; font-size: 13px; cursor: pointer; }
    .card { background: #fff; border: 1px solid #e8dcc8; border-radius: 14px; padding: 16px; margin-bottom: 14px; }
    .card h2 { font-family: 'Fraunces', Georgia, serif; font-size: 18px; margin-bottom: 4px; }
    .muted { font-size: 12px; color: #8a7a68; }
    .badge { display: inline-block; font-size: 11px; padding: 2px 8px; border-radius: 99px; background: #efe3cf; color: #7d5432; }
    .iframe-assinatura { width: 100%; height: 80vh; border: 0; border-radius: 12px; background: #fff; }
```
Trocar o `<title>` fixo por `<%= content_for?(:title) ? yield(:title) : 'Acompanhamento do seu caso' %> · Ramon Antonio Advogados`.

- [ ] **Step 6: Mailer** (molde `AdministratorNotifications::RamonDigestMailer`)

```ruby
# app/mailers/ramon/portal_mailer.rb
# E-mails do Painel do Cliente: código de acesso e convite. Texto = gate do Eduardo.
class Ramon::PortalMailer < ApplicationMailer
  def codigo
    return unless smtp_config_set_or_development?

    @cliente = params[:cliente]
    @codigo = params[:codigo]
    mail(to: @cliente.email, subject: "Seu código de acesso: #{@codigo}") { |f| f.html { render layout: false } }
  end

  def convite
    return unless smtp_config_set_or_development?

    @cliente = params[:cliente]
    @url = ENV.fetch('PORTAL_URL', "#{ENV.fetch('FRONTEND_URL', nil)}/cliente")
    mail(to: @cliente.email, subject: 'Acompanhe o seu caso pelo Painel do Cliente') { |f| f.html { render layout: false } }
  end
end
```

```erb
<%# app/views/mailers/ramon/portal_mailer/codigo.html.erb %>
<p>Olá, <%= @cliente.primeiro_nome %>.</p>
<p>Seu código de acesso ao Painel do Cliente é:</p>
<p style="font-size:28px;letter-spacing:.3em;font-weight:bold"><%= @codigo %></p>
<p>Ele vale por 10 minutos. Se você não pediu este código, ignore este e-mail.</p>
<p>Ramon Antonio Advogados</p>
```

```erb
<%# app/views/mailers/ramon/portal_mailer/convite.html.erb %>
<p>Olá, <%= @cliente.primeiro_nome %>.</p>
<p>Agora você pode acompanhar o seu caso, enviar documentos e assinar pelo celular no Painel do Cliente:</p>
<p><a href="<%= @url %>"><%= @url %></a></p>
<p>Para entrar, use este e-mail. Você recebe um código de 6 dígitos; não precisa de senha.</p>
<p>Ramon Antonio Advogados</p>
```

- [ ] **Step 7: Commit**

```bash
git add app/controllers/cliente app/views/cliente/sessoes app/mailers/ramon/portal_mailer.rb app/views/mailers/ramon app/views/layouts/ramon_portal.html.erb config/routes.rb config/initializers/rack_attack.rb spec/requests/cliente/sessoes_spec.rb
git commit -m "feat(painel): login por e-mail + código e sessão em cookie do Painel do Cliente"
```

### Task 5: Painel — termos, lista e tela do processo, "Atualizar"

**Files:**
- Create: `app/controllers/cliente/painel_controller.rb`
- Create: `app/views/cliente/painel/termos.html.erb`, `show.html.erb`, `processo.html.erb`, `_processo_card.html.erb`
- Create: `spec/requests/cliente/painel_spec.rb`

**Interfaces:**
- Consumes: `current_cliente`, `Ramon::PortalTexto`, `Ramon::PortalSyncService`, `PortalAssinatura.pendentes`.
- Produces: `painel#show`, `#aceitar_termos`, `#atualizar`, `#processo`; `#enviar` e `#assinatura` entram nos PRs 5 e 6 (deixar os métodos com `head :not_found` por enquanto NÃO — simplesmente não declarar as rotas até lá? As rotas já existem; declarar os métodos vazios abaixo devolvendo 404 para o CI passar).

- [ ] **Step 1: Spec**

```ruby
# spec/requests/cliente/painel_spec.rb
require 'rails_helper'

RSpec.describe 'Painel do cliente — painel', type: :request do
  let(:account) { create(:account) }
  let(:processos) do
    [{ 'id' => 1, 'numero' => '5003800-40.2022.4.04.7207', 'tipo' => 'AUXÍLIO-ACIDENTE', 'inicio' => '2022-05-02',
       'responsavel' => 'RAMON ANTONIO', 'responsavel_id' => 259_713, 'etapa' => 'PERICIA AGENDADA', 'fase' => 'ADMINISTRATIVO',
       'andamentos' => [{ 'data' => '2026-06-01', 'titulo' => 'Perícia realizada' }],
       'docs_pendentes' => [{ 'item' => 'CNIS atualizado', 'post_id' => 9 }] },
     { 'id' => 2, 'numero' => '000', 'tipo' => 'PENSÃO', 'etapa' => 'ARQUIVADO/ENCERRADO', 'fase' => 'ARQUIVAMENTO',
       'andamentos' => [], 'docs_pendentes' => [] }]
  end
  let(:cliente) { create(:portal_cliente, account: account, convidado_em: 1.day.ago, termos_aceitos_em: 1.day.ago, processos: processos) }

  def entrar(c = cliente)
    post '/cliente/entrar', params: { email: c.email, codigo: c.gerar_codigo! }
  end

  it 'sem sessão redireciona pro login' do
    get '/cliente/inicio'
    expect(response).to redirect_to('/cliente')
  end

  it 'primeiro acesso pede aceite dos termos e grava o timestamp' do
    cliente.update!(termos_aceitos_em: nil)
    entrar
    get '/cliente/inicio'
    expect(response.body).to include('Termos de uso')
    post '/cliente/termos', params: { aceite: '1' }
    expect(cliente.reload.termos_aceitos_em).to be_present
    expect(response).to redirect_to('/cliente/inicio')
  end

  it 'lista ativos e encerrados com a etapa traduzida' do
    entrar
    get '/cliente/inicio'
    expect(response.body).to include('Perícia agendada')
    expect(response.body).to include('Encerrados')
    expect(response.body).to include('Processo encerrado')
    expect(response.body).not_to include('ARQUIVADO/ENCERRADO')
  end

  it 'tela do processo mostra marcos, identificação e pendências' do
    entrar
    get '/cliente/processos/1'
    expect(response.body).to include('Perícia')
    expect(response.body).to include('5003800-40.2022.4.04.7207')
    expect(response.body).to include('CNIS atualizado')
    expect(response.body).to include('Falta 1 documento')
  end

  it 'processo de outro cliente dá 404' do
    entrar
    get '/cliente/processos/999'
    expect(response).to have_http_status(:not_found)
  end

  it 'atualizar chama o sync uma vez e bloqueia a segunda em menos de 6h' do
    sync = instance_double(Ramon::PortalSyncService, perform: [])
    allow(Ramon::PortalSyncService).to receive(:new).and_return(sync)
    entrar
    post '/cliente/atualizar'
    post '/cliente/atualizar'
    expect(sync).to have_received(:perform).once
    expect(response).to redirect_to('/cliente/inicio')
  end
end
```

- [ ] **Step 2: Controller**

```ruby
# app/controllers/cliente/painel_controller.rb
class Cliente::PainelController < Cliente::BaseController
  before_action :require_cliente
  before_action :require_termos, except: [:aceitar_termos]
  before_action :fetch_processo, only: [:processo, :enviar]

  def show
    @ativos, @encerrados = current_cliente.processos.partition { |p| !Ramon::PortalTexto.encerrado?(p['fase']) }
    @assinaturas = current_cliente.assinaturas.pendentes
  end

  def aceitar_termos
    current_cliente.update!(termos_aceitos_em: Time.current) if params[:aceite] == '1'
    redirect_to cliente_inicio_path
  end

  def atualizar
    if current_cliente.pode_atualizar?
      current_cliente.update!(atualizacao_pedida_em: Time.current)
      Ramon::PortalSyncService.new(current_cliente).perform
      flash[:portal_notice] = 'Dados atualizados.'
    else
      flash[:portal_notice] = 'Já atualizamos há pouco. Tente de novo mais tarde.'
    end
    redirect_to cliente_inicio_path
  rescue Ramon::AdvboxClient::UnavailableError, Ramon::AdvboxClient::RequestError
    flash[:portal_alert] = 'Não conseguimos atualizar agora. Mostrando os últimos dados que temos.'
    redirect_to cliente_inicio_path
  end

  def processo
    @etapa = Ramon::PortalTexto.etapa(@processo['etapa'])
    @marcos = Ramon::PortalTexto.marcos(@processo['andamentos'])
    @recado = current_cliente.recados[@processo['id'].to_s]
    @pendentes = pendentes_com_status
  end

  # PR 5
  def enviar = head(:not_found)

  # PR 6
  def assinatura = head(:not_found)

  private

  def require_termos
    render :termos unless current_cliente.termos_aceitos?
  end

  def fetch_processo
    @processo = current_cliente.processo(params[:lawsuit_id])
    head :not_found if @processo.nil?
  end

  # Item pedido vira "enviado" quando existe PortalEnvio do mesmo pedido (post_id) e item.
  def pendentes_com_status
    enviados = current_cliente.envios.where(lawsuit_id: @processo['id']).pluck(:solicitacao_post_id, :item).to_set
    @processo['docs_pendentes'].map { |d| d.merge('enviado' => enviados.include?([d['post_id'], d['item']])) }
  end
end
```

- [ ] **Step 3: Views**

```erb
<%# app/views/cliente/painel/termos.html.erb — RASCUNHO do texto (gate Eduardo) %>
<p class="eyebrow">Antes de começar</p>
<h1>Termos de uso</h1>
<div class="divider"></div>
<div class="card">
  <p>O Painel do Cliente mostra informações sobre os seus processos com a Ramon Antonio Advogados, permite enviar documentos e assinar documentos eletronicamente. Os dados são usados só para o seu atendimento, conforme a nossa Política de Privacidade. O conteúdo é informativo e não substitui a orientação individual do(a) advogado(a).</p>
</div>
<%= form_with url: cliente_termos_path, method: :post, local: true, class: 'form-portal' do |f| %>
  <label class="label"><%= f.check_box :aceite, { required: true }, '1', '0' %> Li e aceito os termos de uso e a política de privacidade.</label>
  <%= f.submit 'Continuar', class: 'btn-bronze' %>
<% end %>
```

```erb
<%# app/views/cliente/painel/show.html.erb %>
<p class="eyebrow">Olá, <%= current_cliente.primeiro_nome %></p>
<h1>Seus processos</h1>
<div class="divider"></div>
<% if flash[:portal_notice] %><p class="flash flash-notice"><%= flash[:portal_notice] %></p><% end %>
<% if flash[:portal_alert] %><p class="flash flash-alert"><%= flash[:portal_alert] %></p><% end %>

<% @assinaturas.each do |a| %>
  <div class="docs-card">
    <p class="docs-title">Assinatura pendente: <%= a.nome %></p>
    <%= link_to 'Assinar agora', cliente_assinatura_path(a), class: 'btn-bronze' %>
  </div>
<% end %>

<% if @ativos.empty? && @encerrados.empty? %>
  <div class="neutral-card">Ainda não encontramos processos no seu nome. Se acha que é um engano, fale com a equipe.</div>
<% end %>
<% @ativos.each do |p| %><%= render 'processo_card', processo: p %><% end %>
<% if @encerrados.any? %>
  <p class="eyebrow" style="margin-top:18px">Encerrados</p>
  <% @encerrados.each do |p| %><%= render 'processo_card', processo: p %><% end %>
<% end %>

<%= form_with url: cliente_atualizar_path, method: :post, local: true do |f| %>
  <%= f.submit 'Atualizar', class: 'btn-link' %>
<% end %>
<p class="muted">Última atualização: <%= current_cliente.sincronizado_em ? l(current_cliente.sincronizado_em, format: :short) : '—' %></p>
<%= button_to 'Sair', cliente_sair_path, method: :delete, class: 'btn-link' %>
```

```erb
<%# app/views/cliente/painel/_processo_card.html.erb %>
<% etapa = Ramon::PortalTexto.etapa(processo['etapa']) %>
<%= link_to cliente_processo_path(processo['id']), class: 'card', style: 'display:block;text-decoration:none;color:inherit' do %>
  <span class="badge"><%= processo['tipo'].to_s.downcase.capitalize %></span>
  <h2><%= etapa['titulo'] %></h2>
  <p class="muted"><%= etapa['o_que_esperar'] %></p>
  <% if processo['docs_pendentes'].any? %><p class="badge">Documentos pendentes: <%= processo['docs_pendentes'].size %></p><% end %>
<% end %>
```

```erb
<%# app/views/cliente/painel/processo.html.erb %>
<% content_for :title, @etapa['titulo'] %>
<%= link_to '← Seus processos', cliente_inicio_path, class: 'btn-link' %>
<p class="eyebrow"><%= @processo['tipo'] %></p>
<h1><%= @etapa['titulo'] %></h1>
<div class="divider"></div>
<% if flash[:portal_notice] %><p class="flash flash-notice"><%= flash[:portal_notice] %></p><% end %>
<% if flash[:portal_alert] %><p class="flash flash-alert"><%= flash[:portal_alert] %></p><% end %>
<div class="card"><p><%= @etapa['o_que_esperar'] %></p></div>

<% if @recado.present? %>
  <div class="docs-card"><p class="docs-title">Recado da equipe</p><p><%= simple_format(@recado) %></p></div>
<% end %>

<% if @pendentes.any? %>
  <div class="docs-card">
    <p class="docs-title"><%= @pendentes.size == 1 ? 'Falta 1 documento' : "Faltam #{@pendentes.size} documentos" %></p>
    <ul>
      <% @pendentes.each do |d| %>
        <li>
          <%= d['item'] %>
          <% if d['enviado'] %>
            <span class="badge">Enviado — em conferência</span>
          <% else %>
            <%= form_tag cliente_envios_path(@processo['id']), multipart: true, class: 'upload-form' do %>
              <%= hidden_field_tag :item, d['item'] %>
              <%= hidden_field_tag :post_id, d['post_id'] %>
              <%= file_field_tag :file, accept: 'image/*,application/pdf', required: true %>
              <%= submit_tag 'Enviar', class: 'btn-bronze' %>
            <% end %>
          <% end %>
        </li>
      <% end %>
    </ul>
  </div>
<% end %>

<% if @marcos.any? %>
  <div class="timeline">
    <% @marcos.each_with_index do |m, i| %>
      <div class="step">
        <div class="step-rail"><span class="dot-done"></span><% unless i == @marcos.size - 1 %><span class="rail-done"></span><% end %></div>
        <div class="step-text">
          <p class="step-title"><%= m['titulo'] %> <span class="muted"><%= m['data'] %></span></p>
          <p class="step-sub"><%= m['explicacao'] %></p>
        </div>
      </div>
    <% end %>
  </div>
<% end %>

<div class="card">
  <p class="muted">Número: <%= @processo['numero'].presence || '—' %></p>
  <p class="muted">Início: <%= @processo['inicio'].presence || '—' %></p>
  <p class="muted">Advogado(a) responsável: <%= @processo['responsavel'].to_s.titleize.presence || 'equipe' %></p>
  <a class="btn-bronze" href="https://wa.me/<%= ENV.fetch('PORTAL_WHATSAPP', '5548988319115') %>">Falar com a equipe no WhatsApp</a>
</div>
```

- [ ] **Step 4: Commit + PR 3**

```bash
git add app/controllers/cliente/painel_controller.rb app/views/cliente/painel spec/requests/cliente/painel_spec.rb
git commit -m "feat(painel): termos, lista de processos e tela do processo com etapa traduzida e marcos"
```
Run (CI): `bundle exec rspec spec/requests/cliente`.

**Deploy do PR 3 (gates Eduardo):** DNS `A cliente.ramonantonio.adv.br → 185.194.216.67`; bloco no `/opt/intranet-ramon/Caddyfile` (backup antes) com `redir / /cliente 302` + o mesmo `reverse_proxy` do bloco `chat.`; `caddy reload`; envs `PORTAL_URL=https://cliente.ramonantonio.adv.br` e `PORTAL_WHATSAPP=<número>`; `db:migrate` à mão; `.env.example` documentado.

---

# PR 4 — Tela do hub "Painel do cliente"

### Task 6: API `portal_clientes` + policy

**Files:**
- Create: `app/controllers/api/v1/accounts/portal_clientes_controller.rb`
- Create: `app/policies/portal_cliente_policy.rb`
- Modify: `config/routes.rb:299` (após `ramon_reunioes`)
- Create: `spec/requests/api/v1/accounts/portal_clientes_spec.rb`

**Interfaces:**
- Produces: `GET /api/v1/accounts/:id/portal_clientes` → `{ payload: [linha] }`; `POST` `{ advbox_customer_id, nome, cpf, email }` → cria + sync + convite → `linha`; `POST :id/convidar` reenvia; `PATCH :id` `{ recados: { "<lawsuit_id>": "texto" } }`; `GET :id` → `linha + envios + assinaturas`; `POST :id/assinatura` (PR 6). `linha = { id, nome, cpf, email, convidado_em, termos_aceitos_em, sincronizado_em, processos: [{id, numero, tipo, etapa, fase, docs_pendentes}], envios_count, assinaturas_pendentes }`.

- [ ] **Step 1: Spec** (molde `spec/requests/api/v1/accounts/ramon_reunioes_spec.rb`)

```ruby
# spec/requests/api/v1/accounts/portal_clientes_spec.rb
require 'rails_helper'

RSpec.describe 'Portal Clientes API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:headers) { agent.create_new_auth_token }
  let(:base) { "/api/v1/accounts/#{account.id}/portal_clientes" }

  before { allow(Ramon::PortalSyncService).to receive(:new).and_return(instance_double(Ramon::PortalSyncService, perform: [])) }

  it 'exige autenticação' do
    get base
    expect(response).to have_http_status(:unauthorized)
  end

  it 'cria o cliente, sincroniza e envia o convite' do
    expect do
      post base, params: { advbox_customer_id: 14_688_380, nome: 'Venicio Schmidt', cpf: '123.456.789-01', email: 'v@exemplo.com' }, headers: headers
    end.to have_enqueued_mail(Ramon::PortalMailer, :convite)
    expect(response).to have_http_status(:success)
    cliente = PortalCliente.last
    expect(cliente.convidado_em).to be_present
    expect(cliente.cpf).to eq '12345678901'
    expect(Ramon::PortalSyncService).to have_received(:new).with(cliente)
  end

  it 'e-mail duplicado devolve 422' do
    create(:portal_cliente, account: account, email: 'v@exemplo.com')
    post base, params: { advbox_customer_id: 1, nome: 'X', email: 'v@exemplo.com' }, headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'lista, reenvia convite e grava recado' do
    cliente = create(:portal_cliente, account: account, processos: [{ 'id' => 7, 'docs_pendentes' => [] }])
    get base, headers: headers
    expect(response.parsed_body['payload'].first['id']).to eq cliente.id

    expect { post "#{base}/#{cliente.id}/convidar", headers: headers }.to have_enqueued_mail(Ramon::PortalMailer, :convite)
    patch "#{base}/#{cliente.id}", params: { recados: { '7' => 'Leve os exames' } }, headers: headers, as: :json
    expect(cliente.reload.recados).to eq('7' => 'Leve os exames')
  end
end
```

- [ ] **Step 2: Policy + rotas**

```ruby
# app/policies/portal_cliente_policy.rb
class PortalClientePolicy < ApplicationPolicy
  def index?
    @account_user.administrator? || @account_user.agent?
  end

  def show? = index?
  def create? = index?
  def update? = index?
  def convidar? = index?
  def assinatura? = index?
end
```

Em `config/routes.rb`, logo após o bloco `resources :ramon_reunioes ... end` (~linha 299-301):

```ruby
          resources :portal_clientes, only: [:index, :show, :create, :update], controller: 'portal_clientes' do
            member do
              post :convidar
              post :assinatura
            end
          end
```

- [ ] **Step 3: Controller**

```ruby
# app/controllers/api/v1/accounts/portal_clientes_controller.rb
# Tela "Painel do cliente" do hub: convidar cliente do ADVBOX, recado por
# processo, enviar documento pra assinatura. Convite é sempre clique humano.
class Api::V1::Accounts::PortalClientesController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :fetch_cliente, only: [:show, :update, :convidar, :assinatura]
  before_action :check_authorization

  def index
    render json: { payload: Current.account.portal_clientes.order(:nome).map { |c| linha(c) } }
  end

  def show
    render json: detalhe(@cliente)
  end

  def create
    cliente = Current.account.portal_clientes.create!(params.permit(:advbox_customer_id, :nome, :cpf, :email))
    sincronizar(cliente)
    convidar!(cliente)
    render json: linha(cliente)
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.join(', ') }, status: :unprocessable_entity
  end

  def update
    @cliente.update!(recados: params[:recados].to_unsafe_h.transform_values(&:to_s).compact_blank) if params.key?(:recados)
    @cliente.update!(email: params[:email]) if params[:email].present?
    render json: detalhe(@cliente)
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.join(', ') }, status: :unprocessable_entity
  end

  def convidar
    convidar!(@cliente)
    render json: linha(@cliente)
  end

  # PR 6
  def assinatura = head(:not_found)

  private

  def fetch_cliente
    @cliente = Current.account.portal_clientes.find(params[:id])
  end

  def check_authorization
    authorize(:portal_cliente, :"#{action_name}?")
  end

  def sincronizar(cliente)
    Ramon::PortalSyncService.new(cliente).perform
  rescue Ramon::AdvboxClient::UnavailableError, Ramon::AdvboxClient::RequestError => e
    Rails.logger.warn("[PortalClientes] sync falhou cliente=#{cliente.id}: #{e.message}")
  end

  def convidar!(cliente)
    Ramon::PortalMailer.with(account: Current.account, cliente: cliente).convite.deliver_later
    cliente.update!(convidado_em: Time.current)
  end

  def linha(c)
    {
      id: c.id, nome: c.nome, cpf: c.cpf, email: c.email, advbox_customer_id: c.advbox_customer_id,
      convidado_em: c.convidado_em&.iso8601, termos_aceitos_em: c.termos_aceitos_em&.iso8601,
      sincronizado_em: c.sincronizado_em&.iso8601,
      processos: c.processos.map { |p| p.slice('id', 'numero', 'tipo', 'etapa', 'fase', 'docs_pendentes') },
      envios_count: c.envios.count, assinaturas_pendentes: c.assinaturas.pendentes.count
    }
  end

  def detalhe(c)
    linha(c).merge(
      recados: c.recados,
      envios: c.envios.order(created_at: :desc).map do |e|
        { id: e.id, item: e.item, lawsuit_id: e.lawsuit_id, drive_file_id: e.drive_file_id, advbox_post_id: e.advbox_post_id,
          created_at: e.created_at.iso8601 }
      end,
      assinaturas: c.assinaturas.order(created_at: :desc).map do |a|
        { id: a.id, nome: a.nome, status: a.status, assinado_em: a.assinado_em&.iso8601, created_at: a.created_at.iso8601 }
      end
    )
  end
end
```

- [ ] **Step 4: Commit**

```bash
git add app/controllers/api/v1/accounts/portal_clientes_controller.rb app/policies/portal_cliente_policy.rb config/routes.rb spec/requests/api/v1/accounts/portal_clientes_spec.rb
git commit -m "feat(painel): API do hub para convidar clientes e escrever recados"
```

### Task 7: Página Vue "Painel do cliente"

**Files:**
- Create: `app/javascript/dashboard/api/portalClientes.js`
- Create: `app/javascript/dashboard/routes/dashboard/ramon/pages/PortalClientes.vue`
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/ramon.routes.js` (antes de `ramon_relatorios`)
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/components/IntranetSidebar.vue:78` (após o item `reunioes`)
- Modify: `app/javascript/dashboard/i18n/locale/en/ramon.json` e `.../pt_BR/ramon.json` (`NAV.PORTAL` + bloco `PORTAL`)

**Interfaces:**
- Consumes: `RamonCalculosAPI.advboxCustomers(q)` → `{ payload: [{ id, name, identification, cellphone, birthdate, email }] }`; API da Task 6; `GET leads/zapsign_templates` (PR 6).
- Produces: `PortalClientesAPI` (`get()`, `show(id)`, `create(payload)`, `update(id, payload)`, `convidar(id)`, `assinatura(id, payload)`).

- [ ] **Step 1: API client**

```js
/* global axios */
// app/javascript/dashboard/api/portalClientes.js
import ApiClient from './ApiClient';

class PortalClientesAPI extends ApiClient {
  constructor() {
    super('portal_clientes', { accountScoped: true });
  }

  convidar(id) {
    return axios.post(`${this.url}/${id}/convidar`);
  }

  assinatura(id, payload) {
    return axios.post(`${this.url}/${id}/assinatura`, payload);
  }
}

export default new PortalClientesAPI();
```

- [ ] **Step 2: Rota, sidebar, i18n**

`ramon.routes.js` (antes do objeto de `ramon_relatorios`):
```js
  {
    path: frontendURL('accounts/:accountId/ramon/portal'),
    name: 'ramon_portal_clientes',
    component: () => import('./pages/PortalClientes.vue'),
    meta: { permissions: ['administrator', 'agent'], world: 'intranet' },
  },
```

`IntranetSidebar.vue` (após o item `reunioes`):
```js
        {
          key: 'portal',
          label: t('RAMON.NAV.PORTAL'),
          icon: 'i-lucide-users',
          to: accountScopedRoute('ramon_portal_clientes'),
          names: ['ramon_portal_clientes'],
        },
```

`ramon.json` (en): em `NAV` adicionar `"PORTAL": "Client portal"`; novo bloco no mesmo nível de `REUNIOES`:
```json
    "PORTAL": {
      "TITLE": "Client portal",
      "SUBTITLE": "Clients invited to cliente.ramonantonio.adv.br",
      "SEARCH": "Search ADVBOX client (name or CPF)",
      "INVITE": "Invite",
      "REINVITE": "Resend invite",
      "EMAIL": "E-mail",
      "INVITED": "Invited",
      "NOT_INVITED": "Not invited",
      "TERMS_OK": "Terms accepted",
      "SYNCED": "Synced",
      "PENDING_DOCS": "pending docs",
      "UPLOADS": "uploads",
      "SIGNATURES": "pending signatures",
      "RECADO": "Message to client",
      "RECADO_SAVE": "Save message",
      "SEND_SIGNATURE": "Send for signature",
      "TEMPLATE": "ZapSign template",
      "EMPTY": "No client invited yet.",
      "LOAD_ERROR": "Could not load the list.",
      "SAVED": "Saved."
    },
```
`ramon.json` (pt_BR): `"PORTAL": "Painel do cliente"` em `NAV` e o bloco traduzido (Painel do cliente / Clientes convidados… / Buscar cliente no ADVBOX (nome ou CPF) / Convidar / Reenviar convite / E-mail / Convidado / Não convidado / Termos aceitos / Sincronizado / docs pendentes / envios / assinaturas pendentes / Recado ao cliente / Salvar recado / Enviar pra assinatura / Modelo do ZapSign / Nenhum cliente convidado ainda. / Não deu pra carregar a lista. / Salvo.).

- [ ] **Step 3: Página** (molde `Reunioes.vue`; sem Vuex)

```vue
<script setup>
// app/javascript/dashboard/routes/dashboard/ramon/pages/PortalClientes.vue
import { onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import PortalClientesAPI from 'dashboard/api/portalClientes';
import RamonCalculosAPI from 'dashboard/api/ramonCalculos';
import RamonPageHeader from '../components/RamonPageHeader.vue';

defineOptions({ name: 'RamonPortalClientes' });

const { t } = useI18n();
const clientes = ref([]);
const isLoading = ref(false);
const hasError = ref(false);
const busca = ref('');
const resultados = ref([]);
const candidato = ref(null); // cliente do ADVBOX escolhido pra convidar
const emailConvite = ref('');
const aberto = ref(null); // detalhe expandido
const recados = ref({});
const aviso = ref('');

const carregar = async () => {
  isLoading.value = true;
  hasError.value = false;
  try {
    const { data } = await PortalClientesAPI.get();
    clientes.value = data.payload;
  } catch {
    hasError.value = true;
  } finally {
    isLoading.value = false;
  }
};

const buscar = async () => {
  if (busca.value.trim().length < 3) return;
  const { data } = await RamonCalculosAPI.advboxCustomers(busca.value.trim());
  resultados.value = data.payload;
};

const escolher = c => {
  candidato.value = c;
  emailConvite.value = (c.email || '').toLowerCase();
};

const convidar = async () => {
  const c = candidato.value;
  await PortalClientesAPI.create({
    advbox_customer_id: c.id,
    nome: c.name,
    cpf: c.identification,
    email: emailConvite.value,
  });
  candidato.value = null;
  resultados.value = [];
  busca.value = '';
  await carregar();
};

const reenviar = async id => {
  await PortalClientesAPI.convidar(id);
  await carregar();
};

const abrir = async id => {
  if (aberto.value?.id === id) {
    aberto.value = null;
    return;
  }
  const { data } = await PortalClientesAPI.show(id);
  aberto.value = data;
  recados.value = { ...data.recados };
};

const salvarRecados = async () => {
  await PortalClientesAPI.update(aberto.value.id, { recados: recados.value });
  aviso.value = t('RAMON.PORTAL.SAVED');
  setTimeout(() => {
    aviso.value = '';
  }, 2000);
};

const dataCurta = iso => (iso ? new Date(iso).toLocaleDateString('pt-BR') : '—');

onMounted(carregar);
</script>

<template>
  <div class="flex h-full w-full flex-col overflow-y-auto p-8">
    <RamonPageHeader
      :title="t('RAMON.PORTAL.TITLE')"
      :subtitle="t('RAMON.PORTAL.SUBTITLE')"
    />

    <div class="mb-6 rounded-xl border border-n-weak bg-n-solid-1 p-4">
      <div class="flex gap-2">
        <input
          v-model="busca"
          type="search"
          class="flex-1 rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-sm"
          :placeholder="t('RAMON.PORTAL.SEARCH')"
          @keyup.enter="buscar"
        />
        <button
          type="button"
          class="rounded-lg bg-n-iris-9 px-3 py-2 text-sm text-white"
          @click="buscar"
        >
          🔍
        </button>
      </div>
      <ul v-if="resultados.length" class="mt-3 flex flex-col divide-y divide-n-weak">
        <li
          v-for="c in resultados"
          :key="c.id"
          class="flex items-center justify-between py-2 text-sm"
        >
          <span>{{ c.name }} <span class="text-n-slate-11">{{ c.identification }}</span></span>
          <button type="button" class="text-n-iris-11 hover:underline" @click="escolher(c)">
            {{ t('RAMON.PORTAL.INVITE') }}
          </button>
        </li>
      </ul>
      <div v-if="candidato" class="mt-3 flex items-center gap-2">
        <span class="text-sm font-medium">{{ candidato.name }}</span>
        <input
          v-model="emailConvite"
          type="email"
          class="flex-1 rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-sm"
          :placeholder="t('RAMON.PORTAL.EMAIL')"
        />
        <button
          type="button"
          class="rounded-lg bg-n-iris-9 px-3 py-2 text-sm text-white"
          :disabled="!emailConvite"
          @click="convidar"
        >
          {{ t('RAMON.PORTAL.INVITE') }}
        </button>
      </div>
    </div>

    <div v-if="isLoading" class="h-12 animate-pulse rounded-lg bg-n-solid-2" />
    <p v-else-if="hasError" class="text-sm text-n-ruby-11">{{ t('RAMON.PORTAL.LOAD_ERROR') }}</p>
    <p v-else-if="!clientes.length" class="text-sm text-n-slate-11">{{ t('RAMON.PORTAL.EMPTY') }}</p>
    <ul v-else class="flex flex-col divide-y divide-n-weak rounded-xl border border-n-weak bg-n-solid-1">
      <li v-for="c in clientes" :key="c.id" class="px-4 py-3 text-sm">
        <div class="flex items-center justify-between gap-4">
          <button type="button" class="min-w-0 flex-1 truncate text-start font-medium" @click="abrir(c.id)">
            {{ c.nome }} <span class="font-normal text-n-slate-11">{{ c.email }}</span>
          </button>
          <span class="text-xs text-n-slate-11">
            {{ c.convidado_em ? t('RAMON.PORTAL.INVITED') : t('RAMON.PORTAL.NOT_INVITED') }}
            · {{ c.termos_aceitos_em ? t('RAMON.PORTAL.TERMS_OK') : '—' }}
            · {{ t('RAMON.PORTAL.SYNCED') }} {{ dataCurta(c.sincronizado_em) }}
          </span>
          <span class="text-xs">{{ c.envios_count }} {{ t('RAMON.PORTAL.UPLOADS') }}</span>
          <button type="button" class="text-xs text-n-iris-11 hover:underline" @click="reenviar(c.id)">
            {{ t('RAMON.PORTAL.REINVITE') }}
          </button>
        </div>
        <div v-if="aberto && aberto.id === c.id" class="mt-3 flex flex-col gap-3">
          <div v-for="p in aberto.processos" :key="p.id" class="rounded-lg border border-n-weak p-3">
            <p class="text-xs text-n-slate-11">{{ p.numero }} · {{ p.tipo }} · {{ p.etapa }}</p>
            <p v-if="p.docs_pendentes.length" class="text-xs">
              {{ p.docs_pendentes.length }} {{ t('RAMON.PORTAL.PENDING_DOCS') }}
            </p>
            <label class="mt-2 block text-xs">{{ t('RAMON.PORTAL.RECADO') }}</label>
            <textarea
              v-model="recados[p.id]"
              rows="2"
              class="w-full rounded-lg border border-n-weak bg-n-solid-1 px-2 py-1 text-sm"
            />
          </div>
          <div class="flex items-center gap-3">
            <button type="button" class="rounded-lg bg-n-iris-9 px-3 py-1.5 text-xs text-white" @click="salvarRecados">
              {{ t('RAMON.PORTAL.RECADO_SAVE') }}
            </button>
            <span v-if="aviso" class="text-xs text-n-teal-11">{{ aviso }}</span>
          </div>
          <ul v-if="aberto.envios.length" class="text-xs text-n-slate-11">
            <li v-for="e in aberto.envios" :key="e.id">{{ dataCurta(e.created_at) }} · {{ e.item }} · Drive {{ e.drive_file_id ? '✓' : '…' }}</li>
          </ul>
        </div>
      </li>
    </ul>
  </div>
</template>
```

- [ ] **Step 4: Lint + commit + PR 4**

```bash
./node_modules/.bin/eslint app/javascript/dashboard/routes/dashboard/ramon/pages/PortalClientes.vue app/javascript/dashboard/api/portalClientes.js
git add app/javascript/dashboard/api/portalClientes.js app/javascript/dashboard/routes/dashboard/ramon/pages/PortalClientes.vue app/javascript/dashboard/routes/dashboard/ramon/ramon.routes.js app/javascript/dashboard/routes/dashboard/ramon/components/IntranetSidebar.vue app/javascript/dashboard/i18n/locale/en/ramon.json app/javascript/dashboard/i18n/locale/pt_BR/ramon.json
git commit -m "feat(painel): página \"Painel do cliente\" no hub (convite, recados, envios)"
```
(`pnpm eslint` roda o repo inteiro — usar o binário direto, lição do plano mestre.)

---

# PR 5 — Upload → Drive → tarefa ADVBOX → aviso

### Task 8: `painel#enviar` + `Ramon::PortalEnvioJob`

**Files:**
- Modify: `app/controllers/cliente/painel_controller.rb` (substituir `def enviar = head(:not_found)`)
- Create: `app/jobs/ramon/portal_envio_job.rb`
- Modify: `spec/requests/cliente/painel_spec.rb` (novos exemplos)
- Create: `spec/jobs/ramon/portal_envio_job_spec.rb`

**Interfaces:**
- Consumes: `Ramon::DriveClient.configured?`, `.root_id`, `.ensure_folder(name, parent_id)`, `.upload(name:, io:, content_type:, parent_id:)`; `Ramon::AdvboxClient.create_post(body)` → `{ 'posts_id' => }`; `Ramon::NtfyPushJob.perform_later(nil, title:, body:)`; `Ramon::AdvboxClosingService::USERS_ID` (fallback do responsável).
- Produces: `Ramon::PortalEnvioJob.perform(envio_id)`; constante `Ramon::PortalEnvioJob::TASKS_ID_ANALISAR = '9502039'`.

- [ ] **Step 1: Specs**

Acrescentar em `spec/requests/cliente/painel_spec.rb`:

```ruby
  describe 'POST /cliente/processos/:id/envios' do
    let(:pdf) { fixture_file_upload(Rails.root.join('spec/assets/sample.pdf'), 'application/pdf') }

    it 'grava o envio com o pedido e enfileira o job' do
      entrar
      expect do
        post '/cliente/processos/1/envios', params: { file: pdf, item: 'CNIS atualizado', post_id: 9 }
      end.to change(PortalEnvio, :count).by(1).and have_enqueued_job(Ramon::PortalEnvioJob)
      envio = PortalEnvio.last
      expect(envio.solicitacao_post_id).to eq 9
      expect(envio.arquivo).to be_attached
      expect(response).to redirect_to('/cliente/processos/1')
      get '/cliente/processos/1'
      expect(response.body).to include('Enviado — em conferência')
    end

    it 'recusa arquivo com content_type mentiroso' do
      entrar
      falso = fixture_file_upload(Rails.root.join('spec/assets/sample.mp3'), 'application/pdf')
      expect { post '/cliente/processos/1/envios', params: { file: falso, item: 'CNIS', post_id: 9 } }.not_to change(PortalEnvio, :count)
      expect(response).to redirect_to('/cliente/processos/1')
    end
  end
```

```ruby
# spec/jobs/ramon/portal_envio_job_spec.rb
require 'rails_helper'

RSpec.describe Ramon::PortalEnvioJob do
  let(:cliente) do
    create(:portal_cliente, nome: 'Maria de Lourdes', cpf: '12345678901',
                            processos: [{ 'id' => 14_039_119, 'numero' => '500', 'responsavel_id' => 259_713 }])
  end
  let(:envio) { create(:portal_envio, portal_cliente: cliente, lawsuit_id: 14_039_119, item: 'CNIS atualizado') }

  before do
    envio.arquivo.attach(io: File.open(Rails.root.join('spec/assets/sample.pdf')), filename: 'cnis.pdf', content_type: 'application/pdf')
    allow(Ramon::DriveClient).to receive_messages(configured?: true, root_id: 'root')
    allow(Ramon::DriveClient).to receive(:ensure_folder).with('Clientes', 'root').and_return('clientes')
    allow(Ramon::DriveClient).to receive(:ensure_folder).with('Maria de Lourdes — 12345678901', 'clientes').and_return('pasta')
    allow(Ramon::DriveClient).to receive(:upload).and_return('file-1')
    allow(Ramon::AdvboxClient).to receive(:create_post).and_return('posts_id' => 555)
  end

  it 'sobe pro Drive, abre a tarefa ANALISAR pro responsável e avisa' do
    expect { described_class.perform_now(envio.id) }.to have_enqueued_job(Ramon::NtfyPushJob)
    expect(envio.reload.drive_file_id).to eq 'file-1'
    expect(envio.advbox_post_id).to eq '555'
    expect(Ramon::AdvboxClient).to have_received(:create_post).with(hash_including(
      from: '259713', guests: [259_713], tasks_id: '9502039', lawsuits_id: '14039119'
    ))
  end

  it 'é idempotente: não repete Drive nem ADVBOX' do
    envio.update!(drive_file_id: 'file-1', advbox_post_id: '555')
    described_class.perform_now(envio.id)
    expect(Ramon::DriveClient).not_to have_received(:upload)
    expect(Ramon::AdvboxClient).not_to have_received(:create_post)
  end
end
```

- [ ] **Step 2: Controller** — substituir `def enviar = head(:not_found)` em `Cliente::PainelController`:

```ruby
  MAX_UPLOAD_BYTES = 10.megabytes
  ALLOWED_CONTENT_TYPES = %w[application/pdf image/jpeg image/jpg image/png image/heic image/heif].freeze

  def enviar
    unless upload_valido?
      flash[:portal_alert] = 'Não foi possível receber o arquivo — envie um PDF ou foto (JPG/PNG/HEIC) de até 10 MB.'
      return redirect_to cliente_processo_path(@processo['id'])
    end

    envio = current_cliente.envios.create!(lawsuit_id: @processo['id'], solicitacao_post_id: params[:post_id].presence,
                                           item: params[:item].to_s.strip.first(120))
    envio.arquivo.attach(params[:file])
    Ramon::PortalEnvioJob.perform_later(envio.id)
    flash[:portal_notice] = 'Recebemos seu documento. Obrigado!'
    redirect_to cliente_processo_path(@processo['id'])
  end
```
e no `private`:
```ruby
  # Tipo real por magic bytes (Marcel) — o content_type do browser mente fácil.
  def upload_valido?
    file = params[:file]
    return false unless file.respond_to?(:tempfile) && params[:item].present?

    ALLOWED_CONTENT_TYPES.include?(Marcel::MimeType.for(file.tempfile)) && file.size.to_i.positive? && file.size <= MAX_UPLOAD_BYTES
  end
```

- [ ] **Step 3: Job**

```ruby
# app/jobs/ramon/portal_envio_job.rb
# Documento enviado pelo painel: Drive (Clientes/<Nome — CPF>/) → tarefa ADVBOX
# "ANALISAR DOCUMENTAÇÃO ENVIADA PELO CLIENTE" pro responsável → push ntfy.
# Cada passo é idempotente (checa a coluna antes) pra suportar retry.
class Ramon::PortalEnvioJob < ApplicationJob
  queue_as :low
  retry_on Ramon::AdvboxClient::UnavailableError, wait: :polynomially_longer, attempts: 5

  TASKS_ID_ANALISAR = '9502039'.freeze # ANALISAR DOCUMENTAÇÃO ENVIADA PELO CLIENTE (/settings 08/09/2026)

  def perform(envio_id)
    @envio = PortalEnvio.find_by(id: envio_id)
    return if @envio.nil? || !@envio.arquivo.attached?

    @cliente = @envio.portal_cliente
    @processo = @cliente.processo(@envio.lawsuit_id) || {}
    subir_drive if @envio.drive_file_id.blank? && Ramon::DriveClient.configured?
    abrir_tarefa if @envio.advbox_post_id.blank?
    Ramon::NtfyPushJob.perform_later(nil, title: "Documento do cliente #{@cliente.nome}",
                                          body: "#{@envio.item} · processo #{@processo['numero'].presence || @envio.lawsuit_id}")
  end

  private

  def subir_drive
    clientes = Ramon::DriveClient.ensure_folder('Clientes', Ramon::DriveClient.root_id)
    # ponytail: DriveExportService renomeia a pasta pra "… — COMPLETO" ao fechar o checklist;
    # ensure_folder cria uma nova se o nome mudou — aceitável (fica ao lado da antiga).
    pasta = Ramon::DriveClient.ensure_folder([@cliente.nome, @cliente.cpf.presence].compact.join(' — '), clientes)
    nome = "#{@envio.item} — #{Time.zone.today.iso8601}#{File.extname(@envio.arquivo.filename.to_s)}"
    id = @envio.arquivo.blob.open do |io|
      Ramon::DriveClient.upload(name: nome, io: io, content_type: @envio.arquivo.content_type, parent_id: pasta)
    end
    @envio.update!(drive_file_id: id)
  end

  def abrir_tarefa
    responsavel = (@processo['responsavel_id'].presence || Ramon::AdvboxClosingService::USERS_ID).to_i
    link = @envio.drive_file_id.present? ? " Drive: https://drive.google.com/file/d/#{@envio.drive_file_id}" : ''
    resp = Ramon::AdvboxClient.create_post(
      from: responsavel.to_s, guests: [responsavel], tasks_id: TASKS_ID_ANALISAR, lawsuits_id: @envio.lawsuit_id.to_s,
      start_date: Time.zone.today.iso8601,
      comments: "Cliente enviou pelo Painel do Cliente: #{@envio.item}.#{link} (envio ##{@envio.id})"
    )
    @envio.update!(advbox_post_id: resp&.dig('posts_id').to_s.presence || 'sem-id')
  rescue Ramon::AdvboxClient::RequestError => e
    Rails.logger.warn("[Ramon::PortalEnvioJob] envio=#{@envio.id} advbox recusou: #{e.code}")
  end
end
```

- [ ] **Step 4: Commit + PR 5**

```bash
git add app/controllers/cliente/painel_controller.rb app/jobs/ramon/portal_envio_job.rb spec/requests/cliente/painel_spec.rb spec/jobs/ramon/portal_envio_job_spec.rb
git commit -m "feat(painel): upload do cliente → Drive + tarefa ADVBOX + aviso"
```

---

# PR 6 — Assinatura ZapSign

### Task 9: Client ZapSign (`doc`, `update_signer`) + criação pelo hub

**Files:**
- Modify: `lib/ramon/zapsign_client.rb` (extrair `request`, adicionar `doc`, `update_signer`)
- Modify: `app/controllers/api/v1/accounts/portal_clientes_controller.rb` (`assinatura`)
- Modify: `spec/requests/api/v1/accounts/portal_clientes_spec.rb`

**Interfaces:**
- Produces: `Ramon::ZapsignClient.doc(token) → Hash` (`GET /docs/{token}/`), `Ramon::ZapsignClient.update_signer(signer_token, body) → Hash` (`POST /signers/{token}/`); `POST portal_clientes/:id/assinatura { template_id, nome, variaveis: { '{{x}}' => 'y' } }` → `{ id, nome, status }`.

- [ ] **Step 1: Spec** (acrescentar em `portal_clientes_spec.rb`)

```ruby
  it 'cria o documento no ZapSign sem e-mail automático e guarda os tokens' do
    cliente = create(:portal_cliente, account: account, nome: 'Maria', email: 'm@exemplo.com')
    allow(Ramon::ZapsignClient).to receive(:create_doc_from_template)
      .with(hash_including(template_id: 'tpl', signer_name: 'Maria', signer_email: 'm@exemplo.com', send_automatic_email: false))
      .and_return('token' => 'doc-1', 'signers' => [{ 'token' => 'sig-1' }])
    allow(Ramon::ZapsignClient).to receive(:update_signer)

    post "#{base}/#{cliente.id}/assinatura", params: { template_id: 'tpl', nome: 'Procuração', variaveis: { '{{nome}}' => 'Maria' } },
                                              headers: headers, as: :json
    expect(response).to have_http_status(:success)
    a = cliente.assinaturas.last
    expect([a.doc_token, a.signer_token, a.status]).to eq %w[doc-1 sig-1 pendente]
    expect(Ramon::ZapsignClient).to have_received(:update_signer).with('sig-1', hash_including(auth_mode: 'assinaturaTela'))
  end
```

- [ ] **Step 2: Client** — em `lib/ramon/zapsign_client.rb`, refatorar `create_doc_from_template` para usar um `request` genérico e adicionar:

```ruby
  def self.create_doc_from_template(body)
    request(:post, '/models/create-doc/', body)
  end

  def self.doc(token)
    request(:get, "/docs/#{token}/")
  end

  # auth_mode/cpf/redirect_link do signatário depois da criação (o endpoint de
  # modelo não aceita esses campos de forma confiável).
  def self.update_signer(signer_token, body)
    request(:post, "/signers/#{signer_token}/", body)
  end

  def self.request(verb, path, body = nil)
    token = ENV.fetch('ZAPSIGN_API_TOKEN', nil)
    raise UnavailableError, 'ZapSign indisponível: ZAPSIGN_API_TOKEN não configurado' if token.blank?

    opts = { headers: { 'Authorization' => "Bearer #{token}", 'Accept' => 'application/json' },
             open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT }
    if body
      opts[:body] = body.to_json
      opts[:headers]['Content-Type'] = 'application/json'
    end
    response = HTTParty.public_send(verb, "#{BASE}#{path}", **opts)
    return response.parsed_response if response.success?
    raise UnavailableError, "ZapSign respondeu HTTP #{response.code}" if response.code >= 500

    raise RequestError.new(response.code, response.parsed_response)
  rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ECONNRESET, Errno::ETIMEDOUT,
         SocketError, Timeout::Error, OpenSSL::SSL::SSLError, EOFError => e
    raise UnavailableError, "ZapSign indisponível: #{e.message}"
  end
  private_class_method :request
```
(`templates` continua com o `get_json` paginado que já existe; só `create_doc_from_template` migra pro `request`.)

- [ ] **Step 3: Action `assinatura`** — substituir `def assinatura = head(:not_found)`:

```ruby
  def assinatura
    variaveis = params.fetch(:variaveis, {}).to_unsafe_h
    doc = Ramon::ZapsignClient.create_doc_from_template(
      template_id: params[:template_id], signer_name: @cliente.nome, signer_email: @cliente.email,
      send_automatic_email: false, send_automatic_whatsapp: false,
      data: variaveis.map { |de, para| { de: de, para: para.presence || '________' } }
    )
    signer = doc.dig('signers', 0, 'token')
    Ramon::ZapsignClient.update_signer(signer, auth_mode: 'assinaturaTela') if signer.present?
    a = @cliente.assinaturas.create!(doc_token: doc['token'], signer_token: signer, nome: params[:nome].presence || 'Documento')
    render json: { id: a.id, nome: a.nome, status: a.status }
  rescue Ramon::ZapsignClient::UnavailableError, Ramon::ZapsignClient::RequestError => e
    render json: { error: e.message }, status: :service_unavailable
  end
```

- [ ] **Step 4: Commit**

```bash
git add lib/ramon/zapsign_client.rb app/controllers/api/v1/accounts/portal_clientes_controller.rb spec/requests/api/v1/accounts/portal_clientes_spec.rb
git commit -m "feat(painel): hub cria documento ZapSign para o cliente assinar no painel"
```

### Task 10: Webhook ZapSign + job de status + iframe no portal + botão no hub

**Files:**
- Create: `app/controllers/public/api/v1/zapsign_webhooks_controller.rb`
- Create: `app/jobs/ramon/zapsign_status_job.rb`
- Modify: `config/routes.rb:688` (após `advbox_webhooks`), `config/initializers/rack_attack.rb`
- Modify: `app/controllers/cliente/painel_controller.rb` (`assinatura`), Create: `app/views/cliente/painel/assinatura.html.erb`
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/pages/PortalClientes.vue` (botão "Enviar pra assinatura")
- Create: `spec/requests/public/api/v1/zapsign_webhooks_spec.rb`; Modify: `spec/requests/cliente/painel_spec.rb`
- Modify: `.env.example` (`ZAPSIGN_WEBHOOK_SECRET`, `PORTAL_URL`, `PORTAL_WHATSAPP`)

**Interfaces:**
- Produces: `POST /public/api/v1/zapsign_webhooks` (header `X-Ramon-Secret` = `ENV['ZAPSIGN_WEBHOOK_SECRET']`, body com `token`); `Ramon::ZapsignStatusJob.perform(assinatura_id)`; `GET /cliente/assinaturas/:id`.

- [ ] **Step 1: Specs**

```ruby
# spec/requests/public/api/v1/zapsign_webhooks_spec.rb
require 'rails_helper'

RSpec.describe 'Public ZapSign Webhooks API', type: :request do
  let(:assinatura) { create(:portal_assinatura, doc_token: 'doc-1') }
  let(:secret) { 'segredo' }

  def post_webhook(body, header: secret, env: secret)
    with_modified_env(ZAPSIGN_WEBHOOK_SECRET: env) do
      post '/public/api/v1/zapsign_webhooks', params: body.to_json,
                                              headers: { 'CONTENT_TYPE' => 'application/json', 'X-Ramon-Secret' => header }
    end
  end

  it 'rejeita segredo errado ou ausente no servidor' do
    post_webhook({ token: 'doc-1' }, header: 'x')
    expect(response).to have_http_status(:unauthorized)
    post_webhook({ token: 'doc-1' }, env: nil)
    expect(response).to have_http_status(:unauthorized)
  end

  it 'token conhecido enfileira a conferência; desconhecido responde 200 sem job' do
    assinatura
    expect { post_webhook(token: 'doc-1', event_type: 'doc_signed') }.to have_enqueued_job(Ramon::ZapsignStatusJob).with(assinatura.id)
    expect { post_webhook(token: 'outro') }.not_to have_enqueued_job(Ramon::ZapsignStatusJob)
    expect(response).to have_http_status(:ok)
  end
end
```

Acrescentar em `spec/requests/cliente/painel_spec.rb`:
```ruby
  it 'tela de assinatura embute o widget do ZapSign do próprio cliente' do
    a = create(:portal_assinatura, portal_cliente: cliente, signer_token: 'sig-1')
    entrar
    get "/cliente/assinaturas/#{a.id}"
    expect(response.body).to include('https://app.zapsign.com.br/verificar/sig-1')
    outro = create(:portal_assinatura)
    get "/cliente/assinaturas/#{outro.id}"
    expect(response).to have_http_status(:not_found)
  end
```

E `spec/jobs/ramon/zapsign_status_job_spec.rb`:
```ruby
require 'rails_helper'

RSpec.describe Ramon::ZapsignStatusJob do
  it 'marca assinado quando o ZapSign confirma' do
    a = create(:portal_assinatura, doc_token: 'doc-1')
    allow(Ramon::ZapsignClient).to receive(:doc).with('doc-1').and_return('status' => 'signed')
    described_class.perform_now(a.id)
    expect(a.reload.status).to eq 'signed'
    expect(a.assinado_em).to be_present
  end
end
```

- [ ] **Step 2: Webhook + job + rota + throttle**

```ruby
# app/controllers/public/api/v1/zapsign_webhooks_controller.rb
# Webhook do ZapSign (cadastrado por conta no painel deles, evento doc_signed).
# O ZapSign não assina HMAC: a auth é um header customizado com segredo fixo
# (X-Ramon-Secret) + rate-limit. O payload nunca é a verdade — o job re-consulta
# GET /docs/{token}/ antes de marcar assinado.
class Public::Api::V1::ZapsignWebhooksController < PublicController
  before_action :verify_secret

  def create
    assinatura = PortalAssinatura.find_by(doc_token: params[:token].to_s)
    Ramon::ZapsignStatusJob.perform_later(assinatura.id) if assinatura
    render json: { ok: true }
  end

  private

  def verify_secret
    secret = ENV.fetch('ZAPSIGN_WEBHOOK_SECRET', nil)
    provided = request.headers['X-Ramon-Secret'].to_s
    return if secret.present? && provided.present? && ActiveSupport::SecurityUtils.secure_compare(provided, secret)

    head :unauthorized
  end
end
```

```ruby
# app/jobs/ramon/zapsign_status_job.rb
class Ramon::ZapsignStatusJob < ApplicationJob
  queue_as :low
  retry_on Ramon::ZapsignClient::UnavailableError, wait: :polynomially_longer, attempts: 5

  def perform(assinatura_id)
    a = PortalAssinatura.find_by(id: assinatura_id)
    return if a.nil?

    doc = Ramon::ZapsignClient.doc(a.doc_token)
    status = doc['status'].to_s
    a.update!(status: status.presence || a.status, assinado_em: (status == 'signed' ? Time.current : a.assinado_em))
  end
end
```

`config/routes.rb` (após a linha 688): `post 'zapsign_webhooks', to: 'zapsign_webhooks#create'`.
`rack_attack.rb` (após `public/advbox_webhooks`):
```ruby
  ## Ramon — ZapSign webhook (assinaturas do painel) ###
  throttle('public/zapsign_webhooks', limit: 60, period: 1.minute) do |req|
    req.ip if req.path.start_with?('/public/api/v1/zapsign_webhooks') && req.post?
  end
```

- [ ] **Step 3: Portal** — substituir `def assinatura = head(:not_found)` em `Cliente::PainelController`:

```ruby
  def assinatura
    @assinatura = current_cliente.assinaturas.find_by(id: params[:id])
    head :not_found if @assinatura.nil?
  end
```

```erb
<%# app/views/cliente/painel/assinatura.html.erb %>
<% content_for :title, 'Assinatura' %>
<%= link_to '← Seus processos', cliente_inicio_path, class: 'btn-link' %>
<p class="eyebrow">Assinatura eletrônica</p>
<h1><%= @assinatura.nome %></h1>
<div class="divider"></div>
<% if @assinatura.status == 'signed' %>
  <div class="neutral-card">Documento assinado. Obrigado!</div>
<% else %>
  <p id="aviso-assinatura" class="flash flash-notice" hidden>Assinatura recebida. Estamos confirmando…</p>
  <iframe class="iframe-assinatura" src="<%= @assinatura.sign_url %>" allow="camera" title="Assinar documento"></iframe>
  <script>
    // Widget oficial do ZapSign: avisa por postMessage; a verdade vem do webhook.
    window.addEventListener('message', function (e) {
      if (e.data === 'zs-doc-signed') {
        document.getElementById('aviso-assinatura').hidden = false;
        setTimeout(function () { window.location.href = '<%= cliente_inicio_path %>'; }, 4000);
      }
    });
  </script>
<% end %>
```

- [ ] **Step 4: Botão no hub** — em `PortalClientes.vue`, dentro do detalhe expandido (antes da lista de envios): select de modelo (`GET /api/v1/accounts/:id/leads/zapsign_templates` via `axios.get(\`/api/v1/accounts/${accountId}/leads/zapsign_templates\`)` — reusar `useAccount().accountId`), campo "nome do documento" e botão que chama `PortalClientesAPI.assinatura(id, { template_id, nome, variaveis: { '{{nome}}': aberto.nome, '{{CPF}}': aberto.cpf, '{{email}}': aberto.email, '{{data de hoje}}': hoje } })`; depois `abrir(id)` de novo pra listar `assinaturas` com status. i18n: `RAMON.PORTAL.SEND_SIGNATURE`, `TEMPLATE`, `DOC_NAME` ("Nome do documento" / "Document name").

- [ ] **Step 5: `.env.example`** (perto da linha 276, bloco Ramon):

```
# Painel do Cliente (cliente.ramonantonio.adv.br)
PORTAL_URL=https://cliente.ramonantonio.adv.br
PORTAL_WHATSAPP=5548988319115
# Webhook do ZapSign: header X-Ramon-Secret cadastrado no painel do ZapSign
ZAPSIGN_WEBHOOK_SECRET=
```

- [ ] **Step 6: Commit + PR 6**

```bash
git add app/controllers/public/api/v1/zapsign_webhooks_controller.rb app/jobs/ramon/zapsign_status_job.rb config/routes.rb config/initializers/rack_attack.rb app/controllers/cliente/painel_controller.rb app/views/cliente/painel/assinatura.html.erb app/javascript/dashboard/routes/dashboard/ramon/pages/PortalClientes.vue app/javascript/dashboard/i18n/locale/en/ramon.json app/javascript/dashboard/i18n/locale/pt_BR/ramon.json spec/requests/public/api/v1/zapsign_webhooks_spec.rb spec/requests/cliente/painel_spec.rb spec/jobs/ramon/zapsign_status_job_spec.rb .env.example
git commit -m "feat(painel): assinatura ZapSign embutida no painel com webhook de confirmação"
```

**Deploy do PR 6 (gates Eduardo):** `ZAPSIGN_WEBHOOK_SECRET` no `.env`; cadastrar no painel do ZapSign (Configurações › Integrações › Webhooks) a URL `https://chat.ramonantonio.adv.br/public/api/v1/zapsign_webhooks`, evento `doc_signed`, header `X-Ramon-Secret: <segredo>`.

---

## Smoke ponta a ponta (doc `comercial/docs/2026-09-XX-smoke-painel-do-cliente.md`)

1. Hub › Painel do cliente › buscar o próprio Eduardo (CPF com processo real) › Convidar. E-mail chega.
2. Celular › `cliente.ramonantonio.adv.br` › e-mail › código › termos › lista com etapa traduzida.
3. ADVBOX › criar tarefa SOLICITAR DOCUMENTOS no processo com "CNIS atualizado" › hub: `rails runner 'Ramon::PortalSyncJob.perform_now'` › painel mostra "Falta 1 documento".
4. Celular › Enviar › câmera › foto › "Enviado — em conferência". Conferir Drive `Clientes/<Nome — CPF>/`, tarefa ANALISAR no ADVBOX, push ntfy.
5. Concluir a tarefa SOLICITAR no ADVBOX › sync › item some.
6. Hub › Enviar pra assinatura (modelo de teste) › painel › "Assinar agora" › widget › assinar › webhook › hub mostra `signed`.
7. Botão "Atualizar" duas vezes seguidas: a 2ª avisa "já atualizamos há pouco".
8. Registrar no `comercial/decision-log.md` a reversão de 13/08.
