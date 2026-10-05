# Automações em fluxo — B1 (motor) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Motor de fluxos do hub rodando no backend — 3 tabelas, gatilhos de conversa/lead/manual, passos básicos (se, escolha, esperar, parar, rascunho, nota, ação do Chatwoot, mover etapa, tarefa, sino, push), espera que sobrevive a reinício, ensaio, versão congelada, limite/dia, falhou→3 tentativas→aviso — e a API que a tela (B2) vai consumir.

**Architecture:** Fluxo = desenho JSON (`nos` + `setas`) versionado; um ouvinte novo (`RamonFluxoListener`) traduz eventos em `Ramon::Fluxos::Disparo`, que cria `FluxoExecucao` e enfileira `Ramon::FluxoAvancarJob`; o `Ramon::Fluxos::Executor` anda passo a passo (cada tipo = um método pequeno em `Ramon::Fluxos::Passos::*`), grava a trilha e, em "esperar", só anota `retomar_em` — o `Ramon::FluxoRelogioJob` (cron 1/min) retoma quem venceu.

**Tech Stack:** Rails 7.1 · Postgres (jsonb, índice único parcial) · Sidekiq/ActiveJob (strict_args: só IDs) · RSpec/FactoryBot.

**Spec:** `docs/superpowers/specs/2026-10-05-automacoes-em-fluxo-design.md`

## Global Constraints

- Mensagem ao cliente **sempre rascunho**: nenhum passo envia mensagem pública; `send_message`/`send_attachment` são **proibidas** em `acao_chatwoot`.
- Rascunho usa o prefixo exato `Ramon::RascunhoCarimbo::PREFIXO` (`'RASCUNHO (revisar antes de enviar):'`).
- Fuso do escritório: `America/Sao_Paulo` (servidor em UTC) — "hoje", horário comercial e prazos.
- Horário comercial: seg–sex, 08:00–18:00 SP.
- Tentativas após erro: +1, +5, +15 min; na 4ª falha → `falhou` + aviso.
- Profundidade de cadeia entre fluxos: máx. **3**; fluxo nunca redispara a si mesmo.
- Guarda de passos por avanço: **50**.
- Código fora de `enterprise/` (namespace `Ramon::Fluxos`), para os specs rodarem no CI FOSS.
- Jobs recebem só IDs/valores JSON (Sidekiq strict_args).
- API **só administrador**.
- Strings de UI/backend novas: `en.yml` + `pt_BR.yml` (backend) e `en/*.json` + `pt_BR/*.json` (front), como os `ramon_*` existentes.
- **Não há Ruby/Postgres local**: os specs rodam no CI (`run_foss_spec.yml`). "Rodar o teste" = empurrar a branch e ler o CI. Rubocop também só no CI (linha ≤ 150, AbcSize/Complexity — quebrar método grande).
- Migração: `db/schema.rb` editado à mão (padrão do fork); na VPS a migração roda à mão no deploy.

## Review Focus

1. **Rajada de mensagens** — cliente manda 5 mensagens em 10 s numa conversa com fluxo `mensagem_recebida` → **uma** execução ativa (índice único), sem erro no log. → teste na Task 6.
2. **Passo de lead numa conversa sem lead** (ex.: `mover_etapa` com gatilho de conversa) → `falhou` na hora com mensagem clara, **sem** gastar 3 tentativas. → teste na Task 5 (`PassoImpossivel`).
3. **Alvo apagado durante a espera** (lead/conversa excluídos) → execução `cancelada`, sem exceção no Sidekiq. → teste na Task 5.
4. **Relógio enfileira duas vezes** a mesma execução vencida antes do job rodar → anda **uma** vez só (2º avanço vê `retomar_em` no futuro ou status final e sai). → teste na Task 5.
5. **Fluxo encadeado** — fluxo A move etapa, fluxo B escuta etapa e move de volta → para na profundidade 3, sem laço infinito; A não redispara A. → teste na Task 6.

---

## Mapa de arquivos

| Arquivo | Papel |
|---|---|
| `db/migrate/20261005000002_create_ramon_fluxos.rb` | 3 tabelas |
| `db/schema.rb` | idem, à mão |
| `app/models/fluxo.rb` · `fluxo_versao.rb` · `fluxo_execucao.rb` | modelos |
| `app/models/account.rb` | `has_many :fluxos` |
| `app/services/ramon/fluxos/grafo.rb` | navegar e validar o desenho |
| `app/services/ramon/fluxos/horario.rb` | horário comercial SP |
| `app/services/ramon/fluxos/condicao.rb` | `se` (E/OU) e `escolha` |
| `app/services/ramon/fluxos/contexto.rb` | dados do alvo + `{variáveis}` |
| `app/services/ramon/fluxos/passo_impossivel.rb` | erro sem nova tentativa |
| `app/services/ramon/fluxos/passos/logica.rb` | se, escolha, esperar, parar |
| `app/services/ramon/fluxos/passos/conversa.rb` | rascunho_texto, nota_privada, acao_chatwoot |
| `app/services/ramon/fluxos/passos/lead.rb` | mover_etapa, criar_tarefa |
| `app/services/ramon/fluxos/passos/aviso.rb` | avisar_sino, avisar_push |
| `app/services/ramon/fluxos/acao_chatwoot_service.rb` | ações nativas com a execução como autora |
| `app/services/ramon/fluxos/executor.rb` | anda o fluxo |
| `app/services/ramon/fluxos/disparo.rb` | cria execuções (evento, manual, ensaio) |
| `app/jobs/ramon/fluxo_avancar_job.rb` · `fluxo_relogio_job.rb` | jobs |
| `app/listeners/ramon_fluxo_listener.rb` | eventos → disparo |
| `app/dispatchers/async_dispatcher.rb` | registra o ouvinte |
| `app/models/lead.rb` | evento de lead leva `changed_attributes` + `performed_by` |
| `app/models/notification.rb` + locales | tipos `ramon_fluxo_aviso` / `ramon_fluxo_falhou` |
| `config/schedule.yml` | relógio a cada minuto |
| `app/policies/ramon_fluxo_policy.rb` | só admin |
| `app/controllers/api/v1/accounts/ramon_fluxos_controller.rb` · `ramon_fluxo_execucoes_controller.rb` | API |
| `config/routes.rb` | rotas |
| `spec/support/fluxo_helpers.rb` + `spec/rails_helper.rb` | helper de desenho |
| `spec/...` | um spec por unidade (listados nas tasks) |

---

### Task 1: Tabelas e modelos

**Files:**
- Create: `db/migrate/20261005000002_create_ramon_fluxos.rb`
- Modify: `db/schema.rb` (versão + 3 `create_table` entre `ramon_chegadas` e `ramon_metas_comerciais`)
- Create: `app/models/fluxo.rb`, `app/models/fluxo_versao.rb`, `app/models/fluxo_execucao.rb`
- Modify: `app/models/account.rb:90` (ao lado de `has_many :chegadas`)
- Create: `spec/support/fluxo_helpers.rb`; Modify: `spec/rails_helper.rb:78` (include)
- Test: `spec/models/fluxo_spec.rb`

**Interfaces:**
- Produces: `Fluxo` (`publicar!(user) -> FluxoVersao`, `execucoes_hoje`, `limite_atingido?`, `scope :executaveis`, `ZONA`), `FluxoVersao(numero, grafo)`, `FluxoExecucao` (`STATUS`, `lead`, `conversa`, `alvo`), helpers `no_fluxo/grafo_linear/fluxo_publicado`. `Fluxo#publicar!` usa `Ramon::Fluxos::Grafo` (Task 2) — os specs desta task que publicam só passam depois da Task 2; escreva-os aqui, rode no CI ao fim da Task 2.

- [ ] **Step 1: Migração**

```ruby
# Automações em fluxo (spec 2026-10-05): fluxo = desenho versionado; execução = uma
# passada por um lead/conversa, com trilha. Ensaio tem versao_id nulo (roda o rascunho).
class CreateRamonFluxos < ActiveRecord::Migration[7.1]
  def change
    create_table :ramon_fluxos do |t|
      t.bigint :account_id, null: false
      t.string :nome, null: false
      t.text :descricao
      t.string :gatilho_tipo
      t.boolean :ativo, null: false, default: false
      t.integer :limite_dia
      t.string :origem, null: false, default: 'usuario'
      t.string :sistema_chave
      t.string :modo, null: false, default: 'normal'
      t.jsonb :rascunho, null: false, default: {}
      t.bigint :versao_publicada_id
      t.datetime :ultimo_disparo_em
      t.bigint :created_by_id
      t.timestamps
      t.index [:account_id, :gatilho_tipo]
    end

    create_table :ramon_fluxo_versoes do |t|
      t.bigint :fluxo_id, null: false
      t.integer :numero, null: false
      t.jsonb :grafo, null: false, default: {}
      t.bigint :publicado_por_id
      t.datetime :created_at, null: false
      t.index [:fluxo_id, :numero], unique: true
    end

    create_table :ramon_fluxo_execucoes do |t|
      t.bigint :account_id, null: false
      t.bigint :fluxo_id, null: false
      t.bigint :versao_id
      t.string :alvo_type, null: false
      t.bigint :alvo_id, null: false
      t.string :status, null: false, default: 'rodando'
      t.boolean :ensaio, null: false, default: false
      t.string :no_atual
      t.datetime :retomar_em
      t.integer :tentativas, null: false, default: 0
      t.integer :profundidade, null: false, default: 0
      t.jsonb :contexto, null: false, default: {}
      t.jsonb :trilha, null: false, default: []
      t.text :erro
      t.timestamps
      t.index [:fluxo_id, :created_at]
      t.index [:fluxo_id, :alvo_type, :alvo_id], unique: true, name: 'index_ramon_fluxo_execucoes_unica_ativa',
                                                 where: "status IN ('rodando', 'esperando') AND NOT ensaio"
      t.index :retomar_em, name: 'index_ramon_fluxo_execucoes_retomar', where: "status = 'esperando'"
    end
  end
end
```

- [ ] **Step 2: `db/schema.rb` à mão**

Trocar a linha `ActiveRecord::Schema[7.1].define(version: 2026_10_03_000002) do` por `version: 2026_10_05_000002` (a `20261005000001` é a migração do portal, PR #195; se já houver versão maior na base, manter a maior). Inserir, logo depois do bloco `create_table "ramon_chegadas"`:

```ruby
  create_table "ramon_fluxo_execucoes", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "fluxo_id", null: false
    t.bigint "versao_id"
    t.string "alvo_type", null: false
    t.bigint "alvo_id", null: false
    t.string "status", default: "rodando", null: false
    t.boolean "ensaio", default: false, null: false
    t.string "no_atual"
    t.datetime "retomar_em"
    t.integer "tentativas", default: 0, null: false
    t.integer "profundidade", default: 0, null: false
    t.jsonb "contexto", default: {}, null: false
    t.jsonb "trilha", default: [], null: false
    t.text "erro"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["fluxo_id", "alvo_type", "alvo_id"], name: "index_ramon_fluxo_execucoes_unica_ativa", unique: true, where: "(((status)::text = ANY ((ARRAY['rodando'::character varying, 'esperando'::character varying])::text[])) AND (NOT ensaio))"
    t.index ["fluxo_id", "created_at"], name: "index_ramon_fluxo_execucoes_on_fluxo_id_and_created_at"
    t.index ["retomar_em"], name: "index_ramon_fluxo_execucoes_retomar", where: "((status)::text = 'esperando'::text)"
  end

  create_table "ramon_fluxo_versoes", force: :cascade do |t|
    t.bigint "fluxo_id", null: false
    t.integer "numero", null: false
    t.jsonb "grafo", default: {}, null: false
    t.bigint "publicado_por_id"
    t.datetime "created_at", null: false
    t.index ["fluxo_id", "numero"], name: "index_ramon_fluxo_versoes_on_fluxo_id_and_numero", unique: true
  end

  create_table "ramon_fluxos", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "nome", null: false
    t.text "descricao"
    t.string "gatilho_tipo"
    t.boolean "ativo", default: false, null: false
    t.integer "limite_dia"
    t.string "origem", default: "usuario", null: false
    t.string "sistema_chave"
    t.string "modo", default: "normal", null: false
    t.jsonb "rascunho", default: {}, null: false
    t.bigint "versao_publicada_id"
    t.datetime "ultimo_disparo_em"
    t.bigint "created_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "gatilho_tipo"], name: "index_ramon_fluxos_on_account_id_and_gatilho_tipo"
  end
```

- [ ] **Step 3: Modelos**

`app/models/fluxo.rb`:

```ruby
# Automação desenhada no quadro (spec automacoes-em-fluxo): 1 gatilho + passos.
# Edita-se o `rascunho`; publicar congela uma FluxoVersao — execuções em andamento
# seguem na versão em que começaram.
class Fluxo < ApplicationRecord
  self.table_name = 'ramon_fluxos'

  ORIGENS = %w[usuario convertido sistema].freeze
  MODOS = %w[normal sombra].freeze
  ZONA = 'America/Sao_Paulo'.freeze

  belongs_to :account
  belongs_to :created_by, class_name: 'User', optional: true
  belongs_to :versao_publicada, class_name: 'FluxoVersao', optional: true
  has_many :versoes, class_name: 'FluxoVersao', dependent: :destroy_async
  has_many :execucoes, class_name: 'FluxoExecucao', dependent: :destroy_async

  validates :nome, presence: true
  validates :origem, inclusion: { in: ORIGENS }
  validates :modo, inclusion: { in: MODOS }
  validates :limite_dia, numericality: { greater_than: 0 }, allow_nil: true

  # Fluxo do sistema é só desenho (o código de hoje ainda roda) — o motor nunca executa.
  scope :executaveis, -> { where(ativo: true).where.not(origem: 'sistema').where.not(versao_publicada_id: nil) }

  def publicar!(user)
    grafo = Ramon::Fluxos::Grafo.new(rascunho)
    erros = grafo.erros
    raise Ramon::Fluxos::Grafo::Invalido, erros.join(' · ') if erros.any?

    transaction do
      versao = versoes.create!(numero: (versoes.maximum(:numero) || 0) + 1, grafo: rascunho, publicado_por_id: user&.id)
      update!(versao_publicada: versao, gatilho_tipo: grafo.gatilho.dig('config', 'tipo'))
      versao
    end
  end

  def execucoes_hoje = execucoes.where(ensaio: false, created_at: Time.find_zone!(ZONA).now.all_day)

  def limite_atingido? = limite_dia.present? && execucoes_hoje.count >= limite_dia
end
```

`app/models/fluxo_versao.rb`:

```ruby
# Foto publicada do desenho de um Fluxo. Nunca é editada depois de criada.
class FluxoVersao < ApplicationRecord
  self.table_name = 'ramon_fluxo_versoes'

  belongs_to :fluxo
end
```

`app/models/fluxo_execucao.rb`:

```ruby
# Uma passada de um Fluxo por um lead ou conversa. `trilha` = passos percorridos
# (o que acende o caminho no quadro); `contexto` = gatilho, variáveis, etapa inicial.
# Ensaio: não executa ações; versao_id nulo quando ensaia o rascunho (contexto['grafo']).
class FluxoExecucao < ApplicationRecord
  self.table_name = 'ramon_fluxo_execucoes'

  STATUS = %w[rodando esperando concluida falhou cancelada].freeze

  belongs_to :account
  belongs_to :fluxo
  belongs_to :versao, class_name: 'FluxoVersao', optional: true
  belongs_to :alvo, polymorphic: true, optional: true

  validates :status, inclusion: { in: STATUS }

  def grafo = Ramon::Fluxos::Grafo.new(contexto['grafo'] || versao&.grafo)

  def lead
    return alvo if alvo.is_a?(Lead)
    return if alvo.nil?

    account.leads.where(conversation_id: alvo.id).reorder(id: :desc).first
  end

  def conversa = alvo.is_a?(Conversation) ? alvo : alvo&.conversation
end
```

`app/models/account.rb` — logo abaixo de `has_many :chegadas, …`:

```ruby
  has_many :fluxos, class_name: 'Fluxo', dependent: :destroy_async
```

- [ ] **Step 4: Helper de spec**

`spec/support/fluxo_helpers.rb`:

```ruby
# Monta desenhos de fluxo nos specs: gatilho → passos em fila pela saída 's'.
module FluxoHelpers
  def no_fluxo(id, tipo, config = {})
    { 'id' => id, 'tipo' => tipo, 'config' => config, 'posicao' => { 'x' => 0, 'y' => 0 } }
  end

  # passos: [['nota_privada', { 'texto' => 'oi' }], ['parar', {}]]
  def grafo_linear(gatilho_config, *passos)
    nos = [no_fluxo('g', 'gatilho', gatilho_config)]
    passos.each_with_index { |(tipo, config), i| nos << no_fluxo("p#{i + 1}", tipo, config || {}) }
    setas = nos.each_cons(2).map { |a, b| { 'de' => a['id'], 'saida' => 's', 'para' => b['id'] } }
    { 'nos' => nos, 'setas' => setas }
  end

  def fluxo_publicado(account, grafo, **attrs)
    fluxo = Fluxo.create!({ account: account, nome: 'Fluxo de teste', ativo: true, rascunho: grafo }.merge(attrs))
    fluxo.publicar!(nil)
    fluxo.reload
  end
end
```

`spec/rails_helper.rb` — abaixo de `config.include ConversationsUnreadCountsHelpers`:

```ruby
  config.include FluxoHelpers
```

- [ ] **Step 5: Spec do modelo**

`spec/models/fluxo_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe Fluxo do
  let(:account) { create(:account) }
  let(:grafo) { grafo_linear({ 'tipo' => 'manual' }, ['nota_privada', { 'texto' => 'oi' }]) }

  it 'publicar cria versões numeradas e fixa o gatilho' do
    fluxo = described_class.create!(account: account, nome: 'X', rascunho: grafo)
    expect(fluxo.publicar!(nil).numero).to eq(1)
    expect(fluxo.publicar!(nil).numero).to eq(2)
    expect(fluxo.reload.gatilho_tipo).to eq('manual')
    expect(fluxo.versao_publicada.numero).to eq(2)
  end

  it 'não publica desenho inválido' do
    fluxo = described_class.create!(account: account, nome: 'X', rascunho: { 'nos' => [], 'setas' => [] })
    expect { fluxo.publicar!(nil) }.to raise_error(Ramon::Fluxos::Grafo::Invalido)
    expect(fluxo.versoes.count).to eq(0)
  end

  it 'limite do dia conta só execuções reais de hoje (fuso SP)' do
    fluxo = fluxo_publicado(account, grafo, limite_dia: 1)
    lead = create(:lead, account: account)
    travel_to Time.zone.parse('2026-10-06 02:30:00 UTC') do # 05/10 23:30 em SP
      fluxo.execucoes.create!(account: account, versao: fluxo.versao_publicada, alvo: lead, status: 'concluida')
    end
    travel_to Time.zone.parse('2026-10-06 13:00:00 UTC') do
      expect(fluxo.limite_atingido?).to be(false)
      fluxo.execucoes.create!(account: account, alvo: lead, status: 'concluida', ensaio: true)
      expect(fluxo.limite_atingido?).to be(false)
      fluxo.execucoes.create!(account: account, versao: fluxo.versao_publicada, alvo: lead, status: 'concluida')
      expect(fluxo.limite_atingido?).to be(true)
    end
  end

  it 'fluxo do sistema nunca é executável' do
    fluxo_publicado(account, grafo, origem: 'sistema')
    expect(described_class.executaveis).to be_empty
  end
end
```

- [ ] **Step 6: Commit**

```bash
git add db/migrate/20261005000002_create_ramon_fluxos.rb db/schema.rb app/models/fluxo.rb app/models/fluxo_versao.rb app/models/fluxo_execucao.rb app/models/account.rb spec/support/fluxo_helpers.rb spec/rails_helper.rb spec/models/fluxo_spec.rb
git commit -m "feat(fluxos): tabelas e modelos do motor de fluxos"
```

---

### Task 2: Grafo — navegar e validar

**Files:**
- Create: `app/services/ramon/fluxos/grafo.rb`
- Test: `spec/services/ramon/fluxos/grafo_spec.rb`

**Interfaces:**
- Produces: `Ramon::Fluxos::Grafo.new(hash)`; `#nos`, `#setas`, `#no(id) -> Hash|nil`, `#gatilho -> Hash|nil`, `#proximo(id, saida) -> String|nil`, `#erros -> Array<String>`; constantes `GATILHOS`, `TIPOS_PASSO`; exceção `Ramon::Fluxos::Grafo::Invalido`.

- [ ] **Step 1: Spec**

```ruby
require 'rails_helper'

RSpec.describe Ramon::Fluxos::Grafo do
  def grafo(dados) = described_class.new(dados)

  let(:valido) { grafo_linear({ 'tipo' => 'lead_criado' }, ['nota_privada', { 'texto' => 'oi' }]) }

  it 'navega pela saída' do
    g = grafo(valido)
    expect(g.gatilho['id']).to eq('g')
    expect(g.proximo('g', 's')).to eq('p1')
    expect(g.proximo('p1', 's')).to be_nil
  end

  it 'aceita desenho válido' do
    expect(grafo(valido).erros).to eq([])
  end

  it 'exige exatamente 1 gatilho conhecido' do
    expect(grafo({ 'nos' => [], 'setas' => [] }).erros).to include('O fluxo precisa de exatamente 1 gatilho')
    expect(grafo(grafo_linear({ 'tipo' => 'inventado' })).erros).to include('Gatilho desconhecido: inventado')
  end

  it 'recusa ciclo, passo solto e seta para passo inexistente' do
    d = grafo_linear({ 'tipo' => 'manual' }, ['nota_privada', { 'texto' => 'a' }], ['nota_privada', { 'texto' => 'b' }])
    d['setas'] << { 'de' => 'p2', 'saida' => 's', 'para' => 'p1' }
    expect(grafo(d).erros).to include('O fluxo não pode voltar para um passo anterior')

    solto = grafo_linear({ 'tipo' => 'manual' })
    solto['nos'] << no_fluxo('x', 'nota_privada', { 'texto' => 'a' })
    expect(grafo(solto).erros).to include('Passo x não está ligado ao gatilho')

    fantasma = grafo_linear({ 'tipo' => 'manual' })
    fantasma['setas'] << { 'de' => 'g', 'saida' => 's', 'para' => 'zz' }
    expect(grafo(fantasma).erros).to include('Seta aponta para passo inexistente: zz')
  end

  it 'valida saídas de se e escolha' do
    d = grafo_linear({ 'tipo' => 'manual' }, ['se', { 'condicoes' => [{ 'campo' => 'tese', 'operador' => 'existe' }] }])
    expect(grafo(d).erros).to include('Passo p1 (Se) precisa de pelo menos uma saída')

    e = grafo_linear({ 'tipo' => 'manual' },
                     ['escolha', { 'campo' => 'tese', 'casos' => [{ 'chave' => 'c1', 'rotulo' => 'A', 'valores' => ['x'] }] }])
    expect(grafo(e).erros).to include('Passo p1 (Escolha) precisa de pelo menos 2 casos')
  end

  it 'proíbe mensagem pública na ação do Chatwoot' do
    d = grafo_linear({ 'tipo' => 'manual' }, ['acao_chatwoot', { 'acoes' => [{ 'action_name' => 'send_message' }] }])
    expect(grafo(d).erros).to include('Passo p1: mensagem ao cliente só como rascunho')
  end

  it 'exige configuração obrigatória' do
    d = grafo_linear({ 'tipo' => 'manual' }, ['mover_etapa', {}], ['esperar', {}])
    expect(grafo(d).erros).to include('Passo p1: falta etapa_id', 'Passo p2: falta o tempo de espera')
  end
end
```

- [ ] **Step 2: Implementação**

```ruby
# Desenho de um fluxo: { 'nos' => [{id, tipo, config, posicao}], 'setas' => [{de, saida, para}] }.
# Regras de publicação (spec §5): 1 gatilho; sem ciclo; tudo ligado ao gatilho;
# saídas válidas por tipo; mensagem ao cliente só como rascunho.
class Ramon::Fluxos::Grafo
  class Invalido < StandardError; end

  GATILHOS = %w[conversa_criada mensagem_recebida conversa_resolvida conversa_reaberta conversa_atribuida
                lead_criado lead_mudou_etapa lead_ganho lead_perdido manual].freeze
  TIPOS_PASSO = %w[se escolha esperar parar rascunho_texto nota_privada acao_chatwoot
                   mover_etapa criar_tarefa avisar_sino avisar_push].freeze
  OBRIGATORIOS = {
    'rascunho_texto' => %w[texto], 'nota_privada' => %w[texto], 'mover_etapa' => %w[etapa_id],
    'criar_tarefa' => %w[titulo], 'escolha' => %w[campo], 'avisar_sino' => %w[texto], 'avisar_push' => %w[texto]
  }.freeze
  PROIBIDAS_CHATWOOT = %w[send_message send_attachment].freeze

  attr_reader :nos, :setas

  def initialize(dados)
    dados = (dados || {}).to_h.deep_stringify_keys
    @nos = Array(dados['nos'])
    @setas = Array(dados['setas'])
  end

  def no(id) = nos.find { |n| n['id'] == id }

  def gatilho = nos.find { |n| n['tipo'] == 'gatilho' }

  def proximo(id, saida) = setas.find { |s| s['de'] == id && s['saida'] == saida }&.dig('para')

  def erros
    e = erros_gatilho
    return e if e.any?

    e + erros_setas + erros_alcance + nos.flat_map { |n| erros_passo(n) }
  end

  private

  def erros_gatilho
    gatilhos = nos.select { |n| n['tipo'] == 'gatilho' }
    return ['O fluxo precisa de exatamente 1 gatilho'] unless gatilhos.one?

    tipo = gatilhos.first.dig('config', 'tipo')
    GATILHOS.include?(tipo) ? [] : ["Gatilho desconhecido: #{tipo}"]
  end

  def erros_setas
    ids = nos.map { |n| n['id'] }
    fantasmas = setas.flat_map { |s| [s['de'], s['para']] }.uniq - ids
    erros = fantasmas.map { |id| "Seta aponta para passo inexistente: #{id}" }
    repetidas = setas.group_by { |s| [s['de'], s['saida']] }.select { |_, v| v.size > 1 }.keys
    erros + repetidas.map { |de, saida| "Passo #{de}: mais de uma seta na saída #{saida}" }
  end

  def erros_alcance
    return ['O fluxo não pode voltar para um passo anterior'] if ciclo?

    alcancados = alcancaveis(gatilho['id'])
    nos.reject { |n| alcancados.include?(n['id']) }.map { |n| "Passo #{n['id']} não está ligado ao gatilho" }
  end

  def alcancaveis(inicio)
    vistos = Set.new
    fila = [inicio]
    while (id = fila.shift)
      next unless vistos.add?(id)

      fila.concat(setas.select { |s| s['de'] == id }.pluck('para'))
    end
    vistos
  end

  def ciclo?
    estado = {}
    visita = lambda do |id|
      return true if estado[id] == :aberto
      return false if estado[id] == :fechado

      estado[id] = :aberto
      achou = setas.select { |s| s['de'] == id }.any? { |s| visita.call(s['para']) }
      estado[id] = :fechado
      achou
    end
    nos.any? { |n| visita.call(n['id']) }
  end

  def erros_passo(no)
    return [] if no['tipo'] == 'gatilho'
    return ["Passo #{no['id']}: tipo desconhecido (#{no['tipo']})"] unless TIPOS_PASSO.include?(no['tipo'])

    config = no['config'] || {}
    erros = Array(OBRIGATORIOS[no['tipo']]).select { |k| config[k].blank? }.map { |k| "Passo #{no['id']}: falta #{k}" }
    erros + erros_especificos(no, config)
  end

  def erros_especificos(no, config)
    case no['tipo']
    when 'se' then erros_se(no, config)
    when 'escolha' then erros_escolha(no, config)
    when 'esperar' then espera_valida?(config) ? [] : ["Passo #{no['id']}: falta o tempo de espera"]
    when 'acao_chatwoot' then erros_chatwoot(no, config)
    else []
    end
  end

  def erros_se(no, config)
    erros = []
    erros << "Passo #{no['id']} (Se) precisa de condições" if Array(config['condicoes']).empty?
    erros << "Passo #{no['id']} (Se) precisa de pelo menos uma saída" if setas.none? { |s| s['de'] == no['id'] }
    erros
  end

  def erros_escolha(no, config)
    casos = Array(config['casos'])
    return ["Passo #{no['id']} (Escolha) precisa de pelo menos 2 casos"] if casos.size < 2

    erros = []
    erros << "Passo #{no['id']} (Escolha): casos com a mesma chave" if casos.pluck('chave').uniq.size < casos.size
    valores = casos.flat_map { |c| Array(c['valores']).map { |v| v.to_s.downcase } }
    erros << "Passo #{no['id']} (Escolha): o mesmo valor em dois casos" if valores.uniq.size < valores.size
    erros
  end

  def espera_valida?(config)
    config['ate'] == 'horario_comercial' ||
      (config['quantidade'].to_i.positive? && %w[minutos horas dias].include?(config['unidade']))
  end

  def erros_chatwoot(no, config)
    nomes = Array(config['acoes']).map { |a| a['action_name'] }
    return ["Passo #{no['id']}: escolha pelo menos uma ação"] if nomes.empty?

    (nomes & PROIBIDAS_CHATWOOT).any? ? ["Passo #{no['id']}: mensagem ao cliente só como rascunho"] : []
  end
end
```

- [ ] **Step 3: Commit + CI**

```bash
git add app/services/ramon/fluxos/grafo.rb spec/services/ramon/fluxos/grafo_spec.rb
git commit -m "feat(fluxos): grafo do fluxo — navegação e validação de publicação"
```

Empurrar a branch (Eduardo via `!` se o push for barrado) e conferir no CI: `spec/models/fluxo_spec.rb` e `spec/services/ramon/fluxos/grafo_spec.rb` verdes + Rubocop verde. Vermelho → corrigir antes da Task 3.

---

### Task 3: Contexto, horário e condições

**Files:**
- Create: `app/services/ramon/fluxos/horario.rb`, `app/services/ramon/fluxos/condicao.rb`, `app/services/ramon/fluxos/contexto.rb`
- Test: `spec/services/ramon/fluxos/horario_spec.rb`, `spec/services/ramon/fluxos/condicao_spec.rb`, `spec/services/ramon/fluxos/contexto_spec.rb`

**Interfaces:**
- Consumes: `FluxoExecucao#lead/#conversa/#contexto/#ensaio` (Task 1).
- Produces: `Ramon::Fluxos::Horario.comercial?(time) -> bool`, `.proximo(time) -> Time`; `Ramon::Fluxos::Condicao.avaliar(config, dados) -> bool`, `.escolher(config, dados) -> String (chave|'outro')`; `Ramon::Fluxos::Contexto.new(execucao)` com `#execucao`, `#lead`, `#conversa`, `#ensaio?`, `#dados -> Hash<String,_>`, `#interpolar(texto) -> String`.

- [ ] **Step 1: Specs**

`spec/services/ramon/fluxos/horario_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe Ramon::Fluxos::Horario do
  def sp(texto) = Time.find_zone!('America/Sao_Paulo').parse(texto)

  it 'seg–sex 8h–18h em SP' do
    expect(described_class.comercial?(sp('2026-10-05 08:00'))).to be(true)  # segunda
    expect(described_class.comercial?(sp('2026-10-05 18:00'))).to be(false)
    expect(described_class.comercial?(sp('2026-10-10 10:00'))).to be(false) # sábado
  end

  it 'próximo horário comercial' do
    expect(described_class.proximo(sp('2026-10-05 07:10'))).to eq(sp('2026-10-05 08:00'))
    expect(described_class.proximo(sp('2026-10-05 19:00'))).to eq(sp('2026-10-06 08:00'))
    expect(described_class.proximo(sp('2026-10-09 18:30'))).to eq(sp('2026-10-12 08:00')) # sexta → segunda
    expect(described_class.proximo(sp('2026-10-05 10:00'))).to eq(sp('2026-10-05 10:00'))
  end
end
```

`spec/services/ramon/fluxos/condicao_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe Ramon::Fluxos::Condicao do
  let(:dados) { { 'tese' => 'Auxílio-acidente', 'valor' => 5000.0, 'etiquetas' => %w[urgente vip], 'origem' => nil } }

  def se(condicoes, juncao = 'e') = described_class.avaliar({ 'condicoes' => condicoes, 'juncao' => juncao }, dados)

  it 'compara sem acento e sem caixa' do
    expect(se([{ 'campo' => 'tese', 'operador' => 'igual', 'valor' => 'auxilio-acidente' }])).to be(true)
    expect(se([{ 'campo' => 'tese', 'operador' => 'contem', 'valor' => 'ACIDENTE' }])).to be(true)
    expect(se([{ 'campo' => 'tese', 'operador' => 'diferente', 'valor' => 'BPC' }])).to be(true)
  end

  it 'lista, número, existe/vazio e E/OU' do
    expect(se([{ 'campo' => 'etiquetas', 'operador' => 'igual', 'valor' => 'vip' }])).to be(true)
    expect(se([{ 'campo' => 'valor', 'operador' => 'maior', 'valor' => '1000' }])).to be(true)
    expect(se([{ 'campo' => 'origem', 'operador' => 'vazio' }])).to be(true)
    falsa = { 'campo' => 'origem', 'operador' => 'existe' }
    verdadeira = { 'campo' => 'tese', 'operador' => 'existe' }
    expect(se([falsa, verdadeira], 'e')).to be(false)
    expect(se([falsa, verdadeira], 'ou')).to be(true)
  end

  it 'escolha devolve a chave do caso ou outro' do
    config = { 'campo' => 'tese', 'casos' => [
      { 'chave' => 'c1', 'rotulo' => 'BPC', 'valores' => ['BPC'] },
      { 'chave' => 'c2', 'rotulo' => 'Acidente', 'valores' => ['Auxílio-acidente', 'Auxílio-doença'] }
    ] }
    expect(described_class.escolher(config, dados)).to eq('c2')
    expect(described_class.escolher(config, { 'tese' => 'Aposentadoria' })).to eq('outro')
  end
end
```

`spec/services/ramon/fluxos/contexto_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe Ramon::Fluxos::Contexto do
  let(:account) { create(:account) }
  let(:contato) { create(:contact, account: account, name: 'Maria da Silva', phone_number: '+5548999990000') }
  let(:conversa) { create(:conversation, account: account, contact: contato) }
  let(:lead) { create(:lead, account: account, contact: contato, conversation: conversa) }
  let(:fluxo) { fluxo_publicado(account, grafo_linear({ 'tipo' => 'manual' })) }

  def execucao(alvo, vars = {})
    fluxo.execucoes.create!(account: account, alvo: alvo, contexto: { 'vars' => vars, 'gatilho' => { 'texto' => 'oi' } })
  end

  it 'monta os dados do lead e da conversa ligada' do
    dados = described_class.new(execucao(lead)).dados
    expect(dados).to include('nome' => 'Maria', 'nome_completo' => 'Maria da Silva', 'etapa' => lead.lead_stage.name,
                             'caixa_id' => conversa.inbox_id, 'texto' => 'oi')
  end

  it 'acha o lead a partir da conversa' do
    lead
    expect(described_class.new(execucao(conversa)).lead).to eq(lead)
  end

  it 'interpola variáveis e deixa desconhecida literal' do
    ctx = described_class.new(execucao(lead, { 'resposta_ia' => 'ok' }))
    expect(ctx.interpolar('Olá {nome}, {resposta_ia} {inventada}')).to eq('Olá Maria, ok {inventada}')
  end
end
```

- [ ] **Step 2: Implementação**

`app/services/ramon/fluxos/horario.rb`:

```ruby
# Horário comercial do escritório para fluxos (condição e "esperar até o horário comercial").
# ponytail: seg–sex 8h–18h fixo; ler do working_hours da caixa se a banca pedir horário por caixa.
module Ramon::Fluxos::Horario
  ZONA = 'America/Sao_Paulo'.freeze
  INICIO = 8
  FIM = 18

  module_function

  def comercial?(momento)
    local = momento.in_time_zone(ZONA)
    (1..5).cover?(local.wday) && local.hour >= INICIO && local.hour < FIM
  end

  def proximo(momento)
    return momento if comercial?(momento)

    local = momento.in_time_zone(ZONA)
    dia = local.hour < INICIO ? local.to_date : local.to_date + 1
    dia += 1 until (1..5).cover?(dia.wday)
    Time.find_zone!(ZONA).local(dia.year, dia.month, dia.day, INICIO)
  end
end
```

`app/services/ramon/fluxos/condicao.rb`:

```ruby
# Passos de decisão do fluxo: `se` (lista de condições com E/OU) e `escolha`
# (uma saída por valor + "outro"). Compara sem acento e sem caixa.
module Ramon::Fluxos::Condicao
  module_function

  def avaliar(config, dados)
    resultados = Array(config['condicoes']).map { |c| teste(c, dados) }
    config['juncao'] == 'ou' ? resultados.any? : resultados.all?
  end

  def escolher(config, dados)
    atual = valores(dados[config['campo']])
    caso = Array(config['casos']).find { |c| Array(c['valores']).any? { |v| atual.include?(normal(v)) } }
    caso ? caso['chave'] : 'outro'
  end

  def teste(condicao, dados) # rubocop:disable Metrics/CyclomaticComplexity
    atual = dados[condicao['campo']]
    esperado = condicao['valor']
    case condicao['operador']
    when 'igual' then valores(atual).include?(normal(esperado))
    when 'diferente' then valores(atual).exclude?(normal(esperado))
    when 'contem' then valores(atual).any? { |v| v.include?(normal(esperado)) }
    when 'nao_contem' then valores(atual).none? { |v| v.include?(normal(esperado)) }
    when 'maior' then atual.present? && atual.to_f > esperado.to_f
    when 'menor' then atual.present? && atual.to_f < esperado.to_f
    when 'existe' then atual.present?
    when 'vazio' then atual.blank?
    when 'em_horario_comercial' then Ramon::Fluxos::Horario.comercial?(Time.current)
    else false
    end
  end

  def valores(atual) = Array(atual).map { |v| normal(v) }

  def normal(valor) = I18n.transliterate(valor.to_s).downcase.strip
end
```

`app/services/ramon/fluxos/contexto.rb`:

```ruby
# O que um passo enxerga: o alvo (lead/conversa) recarregado a cada passo + variáveis
# da execução. `dados` alimenta condições e o `{chave}` dos textos.
class Ramon::Fluxos::Contexto
  attr_reader :execucao

  def initialize(execucao)
    @execucao = execucao
  end

  def lead = @lead ||= execucao.lead

  def conversa = @conversa ||= execucao.conversa

  def ensaio? = execucao.ensaio

  def dados
    @dados ||= dados_lead.merge(dados_conversa).merge(
      'texto' => execucao.contexto.dig('gatilho', 'texto')
    ).merge(execucao.contexto['vars'] || {})
  end

  def interpolar(texto)
    texto.to_s.gsub(/\{(\w+)\}/) { dados.key?(Regexp.last_match(1)) ? dados[Regexp.last_match(1)].to_s : Regexp.last_match(0) }
  end

  private

  def contato = lead&.contact || conversa&.contact

  def dados_lead
    responsavel = lead&.closer || lead&.sdr
    nome = contato&.name.presence || lead&.name
    {
      'nome' => nome.to_s.split.first, 'nome_completo' => nome, 'telefone' => contato&.phone_number,
      'etapa' => lead&.lead_stage&.name, 'etapa_id' => lead&.lead_stage_id,
      'tese' => lead&.thesis&.name, 'tese_id' => lead&.thesis_id,
      'origem' => lead&.source, 'canal' => lead&.channel, 'valor' => lead&.value&.to_f,
      'prioridade' => lead&.lead_priority&.name,
      'responsavel' => responsavel&.name, 'responsavel_id' => responsavel&.id
    }
  end

  def dados_conversa
    {
      'caixa' => conversa&.inbox&.name, 'caixa_id' => conversa&.inbox_id,
      'status' => conversa&.status, 'etiquetas' => conversa ? conversa.label_list.to_a : []
    }
  end
end
```

- [ ] **Step 3: Commit**

```bash
git add app/services/ramon/fluxos/horario.rb app/services/ramon/fluxos/condicao.rb app/services/ramon/fluxos/contexto.rb spec/services/ramon/fluxos/horario_spec.rb spec/services/ramon/fluxos/condicao_spec.rb spec/services/ramon/fluxos/contexto_spec.rb
git commit -m "feat(fluxos): contexto do passo, condições (se/escolha) e horário comercial"
```

---

### Task 4: Passos

**Files:**
- Create: `app/services/ramon/fluxos/passo_impossivel.rb`, `app/services/ramon/fluxos/passos/logica.rb`, `…/passos/conversa.rb`, `…/passos/lead.rb`, `…/passos/aviso.rb`, `app/services/ramon/fluxos/acao_chatwoot_service.rb`
- Modify: `app/models/notification.rb:51-52` (tipos), `:105-111` (títulos), `:122` (branch `start_with?`)
- Modify: `config/locales/en.yml:256`, `config/locales/pt_BR.yml:235`, `app/javascript/dashboard/i18n/locale/en/generalSettings.json:176`, `app/javascript/dashboard/i18n/locale/pt_BR/generalSettings.json:176`
- Test: `spec/services/ramon/fluxos/passos_spec.rb`

**Interfaces:**
- Consumes: `Ramon::Fluxos::Contexto` (Task 3), `Ramon::Fluxos::Condicao`, `Ramon::Fluxos::Horario`.
- Produces: todo passo é `Modulo.tipo(config, ctx) -> Hash` com chaves `:saida` (String|nil), `:resumo` (String), opcionais `:vars` (Hash), `:esperar_ate` (Time), `:parar` (true). Em ensaio, passos com efeito **não executam** e devolvem `resumo` começando por `"faria: "`. Erro que não adianta repetir → `raise Ramon::Fluxos::PassoImpossivel`. `Ramon::Fluxos::AcaoChatwootService.new(execucao, conversation, acoes).perform`. Notification types `ramon_fluxo_aviso` (15) e `ramon_fluxo_falhou` (16).

- [ ] **Step 1: Spec**

```ruby
require 'rails_helper'

RSpec.describe 'Ramon::Fluxos::Passos' do
  let(:account) { create(:account) }
  let(:conversa) { create(:conversation, account: account) }
  let(:lead) { create(:lead, account: account, conversation: conversa, contact: conversa.contact) }
  let(:fluxo) { fluxo_publicado(account, grafo_linear({ 'tipo' => 'manual' })) }

  def ctx(alvo: lead, ensaio: false)
    Ramon::Fluxos::Contexto.new(fluxo.execucoes.create!(account: account, alvo: alvo, ensaio: ensaio))
  end

  it 'rascunho vira nota privada com o prefixo, nunca mensagem pública' do
    r = Ramon::Fluxos::Passos::Conversa.rascunho_texto({ 'texto' => 'Oi {nome}' }, ctx)
    msg = conversa.messages.last
    expect(msg.private).to be(true)
    expect(msg.content).to start_with(Ramon::RascunhoCarimbo::PREFIXO)
    expect(r[:saida]).to eq('s')
  end

  it 'rascunho de lead sem conversa vira nota do lead' do
    sozinho = create(:lead, account: account)
    Ramon::Fluxos::Passos::Conversa.rascunho_texto({ 'texto' => 'Oi' }, ctx(alvo: sozinho))
    expect(sozinho.lead_notes.last.body).to start_with(Ramon::RascunhoCarimbo::PREFIXO)
  end

  it 'ensaio não grava nada' do
    expect do
      r = Ramon::Fluxos::Passos::Conversa.rascunho_texto({ 'texto' => 'Oi' }, ctx(ensaio: true))
      expect(r[:resumo]).to start_with('faria: ')
    end.not_to(change { conversa.messages.count })
  end

  it 'ação do Chatwoot põe etiqueta e ignora envio ao cliente' do
    acoes = [{ 'action_name' => 'add_label', 'action_params' => ['urgente'] },
             { 'action_name' => 'send_message', 'action_params' => ['oi'] }]
    expect do
      Ramon::Fluxos::Passos::Conversa.acao_chatwoot({ 'acoes' => acoes }, ctx)
    end.not_to(change { conversa.messages.where(message_type: :outgoing, private: false).count })
    expect(conversa.reload.label_list).to include('urgente')
  end

  it 'mover etapa atualiza a etapa inicial da execução' do
    nova = create(:lead_stage, account: account, position: 5)
    c = ctx
    Ramon::Fluxos::Passos::Lead.mover_etapa({ 'etapa_id' => nova.id }, c)
    expect(lead.reload.lead_stage).to eq(nova)
    expect(c.execucao.contexto['etapa_inicial_id']).to eq(nova.id)
  end

  it 'passo de lead sem lead é impossível (não repete)' do
    sem_lead = create(:conversation, account: account)
    expect do
      Ramon::Fluxos::Passos::Lead.mover_etapa({ 'etapa_id' => lead.lead_stage_id }, ctx(alvo: sem_lead))
    end.to raise_error(Ramon::Fluxos::PassoImpossivel)
  end

  it 'tarefa na Esteira com prazo relativo' do
    Ramon::Fluxos::Passos::Lead.criar_tarefa({ 'titulo' => 'Conferir docs de {nome}', 'prazo_dias' => 2 }, ctx)
    tarefa = lead.lead_tasks.last
    expect(tarefa.title).to start_with('Conferir docs de')
    expect(tarefa.due_at.in_time_zone('America/Sao_Paulo').to_date).to eq(Time.find_zone!('America/Sao_Paulo').today + 2)
  end

  it 'esperar devolve o momento de retomar' do
    freeze_time do
      r = Ramon::Fluxos::Passos::Logica.esperar({ 'quantidade' => 2, 'unidade' => 'dias' }, ctx)
      expect(r[:esperar_ate]).to eq(2.days.from_now)
    end
  end

  it 'escolha sai pela chave do caso' do
    lead.update!(source: 'indicacao')
    config = { 'campo' => 'origem', 'casos' => [{ 'chave' => 'c1', 'rotulo' => 'Indicação', 'valores' => ['indicacao'] },
                                                { 'chave' => 'c2', 'rotulo' => 'Anúncio', 'valores' => ['anuncio'] }] }
    expect(Ramon::Fluxos::Passos::Logica.escolha(config, ctx)[:saida]).to eq('c1')
  end

  it 'sino avisa o responsável' do
    agente = create(:user, account: account)
    lead.update!(closer: agente)
    expect do
      Ramon::Fluxos::Passos::Aviso.avisar_sino({ 'texto' => 'Ver {nome}' }, ctx)
    end.to change { agente.notifications.where(notification_type: 'ramon_fluxo_aviso').count }.by(1)
  end
end
```

- [ ] **Step 2: Erro sem nova tentativa**

`app/services/ramon/fluxos/passo_impossivel.rb`:

```ruby
# Erro que não adianta repetir (ex.: passo de lead numa conversa sem lead):
# o executor marca `falhou` na hora, sem as 3 tentativas.
class Ramon::Fluxos::PassoImpossivel < StandardError; end
```

- [ ] **Step 3: Passos de lógica**

`app/services/ramon/fluxos/passos/logica.rb`:

```ruby
# Passos sem efeito fora do fluxo: decidir (se/escolha), esperar, parar.
module Ramon::Fluxos::Passos::Logica
  UNIDADES = { 'minutos' => :minutes, 'horas' => :hours, 'dias' => :days }.freeze

  module_function

  def se(config, ctx)
    ok = Ramon::Fluxos::Condicao.avaliar(config, ctx.dados)
    { saida: ok ? 'sim' : 'nao', resumo: ok ? 'sim' : 'não' }
  end

  def escolha(config, ctx)
    chave = Ramon::Fluxos::Condicao.escolher(config, ctx.dados)
    rotulo = Array(config['casos']).find { |c| c['chave'] == chave }&.dig('rotulo') || 'outro'
    { saida: chave, resumo: "#{config['campo']} → #{rotulo}" }
  end

  def esperar(config, _ctx)
    ate = if config['ate'] == 'horario_comercial'
            Ramon::Fluxos::Horario.proximo(Time.current)
          else
            Time.current + config['quantidade'].to_i.public_send(UNIDADES.fetch(config['unidade']))
          end
    { saida: 's', resumo: "espera até #{ate.in_time_zone(Fluxo::ZONA).strftime('%d/%m %H:%M')}", esperar_ate: ate }
  end

  def parar(_config, _ctx) = { saida: nil, resumo: 'parou', parar: true }
end
```

- [ ] **Step 4: Passos de conversa + ação do Chatwoot**

`app/services/ramon/fluxos/acao_chatwoot_service.rb`:

```ruby
# Ações nativas das regras do Chatwoot (etiqueta, atribuir, status, prioridade, e-mail…)
# executadas pelo mesmo código delas. A regra é só um molde em memória; a autoria dos
# eventos gerados vira a execução do fluxo (uma regra sem id não serializa no job).
class Ramon::Fluxos::AcaoChatwootService < AutomationRules::ActionService
  def initialize(execucao, conversation, acoes)
    permitidas = acoes.reject { |a| Ramon::Fluxos::Grafo::PROIBIDAS_CHATWOOT.include?(a['action_name']) }
    molde = AutomationRule.new(account: conversation.account, name: execucao.fluxo.nome,
                               event_name: 'conversation_updated', conditions: [], actions: permitidas)
    super(molde, conversation.account, conversation)
    Current.executed_by = execucao
  end
end
```

`app/services/ramon/fluxos/passos/conversa.rb`:

```ruby
# Passos que escrevem na conversa. Mensagem ao cliente SEMPRE como rascunho (nota privada
# com o prefixo do carimbo) — quem envia é uma pessoa.
module Ramon::Fluxos::Passos::Conversa
  module_function

  def rascunho_texto(config, ctx)
    texto = ctx.interpolar(config['texto'])
    return { saida: 's', resumo: "faria: rascunho \"#{texto.truncate(120)}\"" } if ctx.ensaio?

    escrever(ctx, "#{Ramon::RascunhoCarimbo::PREFIXO}\n#{texto}")
    { saida: 's', resumo: "rascunho criado: #{texto.truncate(120)}" }
  end

  def nota_privada(config, ctx)
    texto = ctx.interpolar(config['texto'])
    return { saida: 's', resumo: "faria: nota \"#{texto.truncate(120)}\"" } if ctx.ensaio?

    escrever(ctx, texto)
    { saida: 's', resumo: "nota: #{texto.truncate(120)}" }
  end

  def acao_chatwoot(config, ctx)
    acoes = Array(config['acoes'])
    descricao = acoes.pluck('action_name').join(', ')
    return { saida: 's', resumo: "faria: #{descricao}" } if ctx.ensaio?
    raise Ramon::Fluxos::PassoImpossivel, 'ação do Chatwoot precisa de uma conversa' if ctx.conversa.blank?

    Ramon::Fluxos::AcaoChatwootService.new(ctx.execucao, ctx.conversa, acoes).perform
    { saida: 's', resumo: descricao }
  end

  def escrever(ctx, texto)
    if ctx.conversa
      Messages::MessageBuilder.new(nil, ctx.conversa, { content: texto, private: true,
                                                        content_attributes: { ramon_fluxo_execucao_id: ctx.execucao.id } }).perform
    elsif ctx.lead
      ctx.lead.lead_notes.create!(account: ctx.lead.account, body: texto.truncate(1000))
    else
      raise Ramon::Fluxos::PassoImpossivel, 'sem conversa nem lead para escrever'
    end
  end
end
```

- [ ] **Step 5: Passos de lead**

`app/services/ramon/fluxos/passos/lead.rb`:

```ruby
# Passos que mexem no lead (funil e Esteira).
module Ramon::Fluxos::Passos::Lead
  module_function

  def mover_etapa(config, ctx)
    lead = exigir_lead(ctx)
    etapa = lead.account.lead_stages.find(config['etapa_id'])
    return { saida: 's', resumo: "faria: mover para #{etapa.name}" } if ctx.ensaio?

    lead.update!(lead_stage: etapa)
    # a mudança feita pelo próprio fluxo não pode cancelá-lo na próxima espera
    ctx.execucao.contexto = ctx.execucao.contexto.merge('etapa_inicial_id' => etapa.id)
    { saida: 's', resumo: "moveu para #{etapa.name}" }
  end

  def criar_tarefa(config, ctx)
    lead = exigir_lead(ctx)
    titulo = ctx.interpolar(config['titulo']).truncate(255)
    prazo = (Time.find_zone!(Fluxo::ZONA).now + config.fetch('prazo_dias', 1).to_i.days).end_of_day
    return { saida: 's', resumo: "faria: tarefa \"#{titulo}\"" } if ctx.ensaio?

    responsavel = config['responsavel_id'].present? ? lead.account.users.find(config['responsavel_id']) : (lead.closer || lead.sdr)
    kind = LeadTask::KINDS.include?(config['tipo']) ? config['tipo'] : 'other'
    lead.lead_tasks.create!(account: lead.account, kind: kind, title: titulo, due_at: prazo, user: responsavel)
    { saida: 's', resumo: "tarefa \"#{titulo}\" · #{responsavel&.name || 'sem responsável'}" }
  end

  def exigir_lead(ctx)
    ctx.lead || raise(Ramon::Fluxos::PassoImpossivel, 'este passo precisa de um lead')
  end
end
```

- [ ] **Step 6: Passos de aviso + tipos de notificação**

`app/services/ramon/fluxos/passos/aviso.rb`:

```ruby
# Avisos internos: sino do hub (lead) e push no celular (ntfy).
module Ramon::Fluxos::Passos::Aviso
  module_function

  def avisar_sino(config, ctx)
    lead = Ramon::Fluxos::Passos::Lead.exigir_lead(ctx)
    texto = ctx.interpolar(config['texto'])
    ids = Array(config['user_ids']).presence || [(lead.closer || lead.sdr)&.id].compact
    return { saida: 's', resumo: "faria: sino \"#{texto.truncate(80)}\"" } if ctx.ensaio?

    Ramon::LeadNotificationBuilder.new(lead: lead, notification_type: 'ramon_fluxo_aviso',
                                       meta: { 'label' => texto.truncate(200) }, user_ids: ids.presence).perform
    { saida: 's', resumo: "sino: #{texto.truncate(80)}" }
  end

  def avisar_push(config, ctx)
    titulo = ctx.interpolar(config['titulo'].presence || ctx.execucao.fluxo.nome)
    texto = ctx.interpolar(config['texto'])
    return { saida: 's', resumo: "faria: push \"#{texto.truncate(80)}\"" } if ctx.ensaio?

    Ramon::NtfyPushJob.perform_later(title: titulo, body: texto)
    { saida: 's', resumo: "push: #{texto.truncate(80)}" }
  end
end
```

`app/models/notification.rb` — no hash `NOTIFICATION_TYPES`, depois de `ramon_contract_status: 14`:

```ruby
    ramon_contract_status: 14,
    ramon_fluxo_aviso: 15,
    ramon_fluxo_falhou: 16
```

No `notification_title_map`, depois de `'ramon_contract_status' => …`:

```ruby
      'ramon_contract_status' => 'notifications.notification_title.ramon_contract_status',
      'ramon_fluxo_aviso' => 'notifications.notification_title.ramon_fluxo_aviso',
      'ramon_fluxo_falhou' => 'notifications.notification_title.ramon_fluxo_falhou'
```

E a linha do `elsif notification_type.start_with?(…)`:

```ruby
    elsif notification_type.start_with?('ramon_meeting_', 'ramon_sla_', 'ramon_contract_', 'ramon_fluxo_')
```

`config/locales/en.yml` (abaixo de `ramon_contract_status`):

```yaml
      ramon_fluxo_aviso: 'Automation: %{label} (%{name})'
      ramon_fluxo_falhou: 'Automation "%{label}" failed for %{name}'
```

`config/locales/pt_BR.yml` (abaixo de `ramon_contract_status`):

```yaml
      ramon_fluxo_aviso: 'Automação: %{label} (%{name})'
      ramon_fluxo_falhou: 'Automação "%{label}" falhou para %{name}'
```

`en/generalSettings.json` e `pt_BR/generalSettings.json` (abaixo de `"ramon_contract_status"`, com vírgula na linha anterior):

```json
      "ramon_fluxo_aviso": "Automation notice",
      "ramon_fluxo_falhou": "Automation failed"
```

```json
      "ramon_fluxo_aviso": "Aviso de automação",
      "ramon_fluxo_falhou": "Automação falhou"
```

- [ ] **Step 7: Commit + CI**

```bash
git add app/services/ramon/fluxos/passo_impossivel.rb app/services/ramon/fluxos/passos app/services/ramon/fluxos/acao_chatwoot_service.rb app/models/notification.rb config/locales/en.yml config/locales/pt_BR.yml app/javascript/dashboard/i18n/locale/en/generalSettings.json app/javascript/dashboard/i18n/locale/pt_BR/generalSettings.json spec/services/ramon/fluxos/passos_spec.rb
git commit -m "feat(fluxos): passos do motor (lógica, conversa, lead, avisos)"
```

Empurrar e conferir CI (Tasks 3–4 verdes) antes da Task 5.

---

### Task 5: Executor

**Files:**
- Create: `app/services/ramon/fluxos/executor.rb`
- Test: `spec/services/ramon/fluxos/executor_spec.rb`

**Interfaces:**
- Consumes: `FluxoExecucao#grafo/#lead/#conversa`, `Grafo#no/#proximo/#gatilho`, os passos (Task 4), `Ramon::EventoInline.registrar(conversation, texto, tipo:)`, `Ramon::LeadNotificationBuilder`, `Ramon::NtfyPushJob`.
- Produces: `Ramon::Fluxos::Executor.new(execucao).avancar!` (idempotente, seguro para chamada dupla); `Executor::PASSOS` (tipo → módulo com método homônimo).

- [ ] **Step 1: Spec**

```ruby
require 'rails_helper'

RSpec.describe Ramon::Fluxos::Executor do
  let(:account) { create(:account) }
  let(:conversa) { create(:conversation, account: account) }
  let(:lead) { create(:lead, account: account, conversation: conversa, contact: conversa.contact) }

  def iniciar(grafo, alvo: lead, **attrs)
    fluxo = fluxo_publicado(account, grafo)
    g = fluxo.versao_publicada.grafo
    fluxo.execucoes.create!({ account: account, versao: fluxo.versao_publicada, alvo: alvo,
                              no_atual: Ramon::Fluxos::Grafo.new(g).proximo('g', 's'),
                              contexto: { 'etapa_inicial_id' => lead.lead_stage_id } }.merge(attrs))
  end

  def avancar(execucao) = described_class.new(execucao).avancar!.then { execucao.reload }

  it 'anda até o fim, grava trilha e balão na conversa' do
    e = iniciar(grafo_linear({ 'tipo' => 'manual' }, ['nota_privada', { 'texto' => 'a' }],
                             ['criar_tarefa', { 'titulo' => 'T' }]))
    expect { avancar(e) }.to have_enqueued_job(Conversations::ActivityMessageJob)
    expect(e.status).to eq('concluida')
    expect(e.trilha.pluck('no')).to eq(%w[p1 p2])
  end

  it 'para na espera e retoma só quando vence (relógio duplicado não anda 2x)' do
    e = iniciar(grafo_linear({ 'tipo' => 'manual' }, ['esperar', { 'quantidade' => 2, 'unidade' => 'dias' }],
                             ['nota_privada', { 'texto' => 'depois' }]))
    avancar(e)
    expect(e.status).to eq('esperando')
    expect(e.no_atual).to eq('p2')

    avancar(e) # chamado antes da hora: não anda
    expect(e.status).to eq('esperando')

    travel 2.days + 1.minute do
      avancar(e)
      expect(e.status).to eq('concluida')
      avancar(e) # segundo job do relógio: nada muda
      expect(e.trilha.count { |t| t['no'] == 'p2' }).to eq(1)
    end
  end

  it 'cancela se o lead saiu da etapa durante a espera' do
    e = iniciar(grafo_linear({ 'tipo' => 'lead_criado' }, ['esperar', { 'quantidade' => 1, 'unidade' => 'horas' }],
                             ['nota_privada', { 'texto' => 'x' }]))
    avancar(e)
    lead.update!(lead_stage: create(:lead_stage, account: account, position: 9))
    travel(2.hours) { expect(avancar(e).status).to eq('cancelada') }
  end

  it 'versão congelada: publicar de novo não muda execução em andamento' do
    e = iniciar(grafo_linear({ 'tipo' => 'manual' }, ['esperar', { 'quantidade' => 1, 'unidade' => 'horas' }],
                             ['nota_privada', { 'texto' => 'v1' }]))
    avancar(e)
    e.fluxo.update!(rascunho: grafo_linear({ 'tipo' => 'manual' }, ['esperar', { 'quantidade' => 1, 'unidade' => 'horas' }],
                                           ['nota_privada', { 'texto' => 'v2' }]))
    e.fluxo.publicar!(nil)
    travel(2.hours) { avancar(e) }
    expect(conversa.messages.where(private: true).last.content).to eq('v1')
  end

  it 'erro: tenta em 1, 5, 15 min e depois falha avisando' do
    e = iniciar(grafo_linear({ 'tipo' => 'manual' }, ['nota_privada', { 'texto' => 'x' }]))
    allow(Ramon::Fluxos::Passos::Conversa).to receive(:nota_privada).and_raise(StandardError, 'fora do ar')
    [1, 5, 15].each do |min|
      avancar(e)
      expect(e.status).to eq('esperando')
      expect(e.retomar_em).to be_within(5.seconds).of(min.minutes.from_now)
      e.update!(retomar_em: 1.second.ago)
    end
    expect { avancar(e) }.to have_enqueued_job(Ramon::NtfyPushJob)
    expect(e.status).to eq('falhou')
    expect(e.erro).to include('fora do ar')
  end

  it 'passo impossível falha na hora' do
    sem_lead = create(:conversation, account: account)
    e = iniciar(grafo_linear({ 'tipo' => 'manual' }, ['mover_etapa', { 'etapa_id' => lead.lead_stage_id }]), alvo: sem_lead)
    expect(avancar(e).status).to eq('falhou')
    expect(e.tentativas).to eq(0)
  end

  it 'alvo apagado durante a espera → cancelada' do
    e = iniciar(grafo_linear({ 'tipo' => 'manual' }, ['esperar', { 'quantidade' => 1, 'unidade' => 'horas' }],
                             ['nota_privada', { 'texto' => 'x' }]))
    avancar(e)
    FluxoExecucao.where(id: e.id).update_all(alvo_id: 0) # rubocop:disable Rails/SkipsModelValidations
    travel(2.hours) { expect(avancar(e).status).to eq('cancelada') }
  end

  it 'escolha segue a saída do caso' do
    d = grafo_linear({ 'tipo' => 'manual' })
    d['nos'] += [no_fluxo('x', 'escolha', { 'campo' => 'origem', 'casos' => [
      { 'chave' => 'c1', 'rotulo' => 'Indicação', 'valores' => ['indicacao'] },
      { 'chave' => 'c2', 'rotulo' => 'Anúncio', 'valores' => ['anuncio'] }
    ] }), no_fluxo('a', 'nota_privada', { 'texto' => 'A' }), no_fluxo('b', 'nota_privada', { 'texto' => 'B' })]
    d['setas'] += [{ 'de' => 'g', 'saida' => 's', 'para' => 'x' }, { 'de' => 'x', 'saida' => 'c1', 'para' => 'a' },
                   { 'de' => 'x', 'saida' => 'outro', 'para' => 'b' }]
    lead.update!(source: 'indicacao')
    e = iniciar(d)
    expect(avancar(e).trilha.pluck('no')).to eq(%w[x a])
  end

  it 'ensaio pula espera e não executa ações' do
    e = iniciar(grafo_linear({ 'tipo' => 'manual' }, ['esperar', { 'quantidade' => 3, 'unidade' => 'dias' }],
                             ['nota_privada', { 'texto' => 'x' }]),
                ensaio: true, contexto: { 'pular_esperas' => true })
    expect { avancar(e) }.not_to(change { conversa.messages.count })
    expect(e.status).to eq('concluida')
    expect(e.trilha.last['resumo']).to start_with('faria: ')
  end
end
```

- [ ] **Step 2: Implementação**

```ruby
# Anda uma execução de fluxo passo a passo (spec §6). Seguro para chamada dupla:
# trava a linha, só anda se estiver rodando/esperando E a espera venceu.
# Esperar só anota retomar_em — quem retoma é o Ramon::FluxoRelogioJob.
class Ramon::Fluxos::Executor # rubocop:disable Metrics/ClassLength
  LIMITE_PASSOS = 50
  ESPERAS_ERRO = [1, 5, 15].freeze # minutos até a próxima tentativa
  VISIVEIS = %w[mover_etapa criar_tarefa acao_chatwoot avisar_sino avisar_push].freeze
  # tipo do passo → módulo que tem o método de mesmo nome (chamado por nome: dá pra stubar no spec)
  PASSOS = {
    'se' => Ramon::Fluxos::Passos::Logica, 'escolha' => Ramon::Fluxos::Passos::Logica,
    'esperar' => Ramon::Fluxos::Passos::Logica, 'parar' => Ramon::Fluxos::Passos::Logica,
    'rascunho_texto' => Ramon::Fluxos::Passos::Conversa, 'nota_privada' => Ramon::Fluxos::Passos::Conversa,
    'acao_chatwoot' => Ramon::Fluxos::Passos::Conversa,
    'mover_etapa' => Ramon::Fluxos::Passos::Lead, 'criar_tarefa' => Ramon::Fluxos::Passos::Lead,
    'avisar_sino' => Ramon::Fluxos::Passos::Aviso, 'avisar_push' => Ramon::Fluxos::Passos::Aviso
  }.freeze

  def initialize(execucao)
    @execucao = execucao
  end

  def avancar!
    falhou = false
    @execucao.with_lock do
      next unless pode_andar?
      next if cancelar_se_preciso

      @execucao.assign_attributes(status: 'rodando', retomar_em: nil)
      andar
      @execucao.save!
      falhou = @execucao.status == 'falhou' && !@execucao.ensaio
    end
    avisar_falha if falhou
    @execucao
  end

  private

  def pode_andar?
    return true if @execucao.status == 'rodando'

    @execucao.status == 'esperando' && @execucao.retomar_em.present? && @execucao.retomar_em <= Time.current
  end

  def cancelar_se_preciso
    motivo = if @execucao.alvo.nil? then 'o lead/conversa foi apagado'
             elsif saiu_da_etapa? then 'o lead saiu da etapa'
             end
    return false unless motivo

    @execucao.update!(status: 'cancelada', retomar_em: nil,
                      trilha: @execucao.trilha + [linha('cancelado', 'cancelado', "cancelado: #{motivo}")])
    true
  end

  def saiu_da_etapa?
    inicial = @execucao.contexto['etapa_inicial_id']
    return false if @execucao.status != 'esperando' || inicial.blank?
    return false if @execucao.grafo.gatilho&.dig('config', 'cancelar_se_sair_da_etapa') == false

    lead = @execucao.lead
    lead.present? && lead.lead_stage_id != inicial
  end

  def andar
    LIMITE_PASSOS.times do
      no = @execucao.grafo.no(@execucao.no_atual)
      return @execucao.status = 'concluida' if no.nil?

      resultado = executar(no)
      return if resultado.nil? # erro: já ficou esperando nova tentativa ou falhou

      registrar(no, resultado)
      return @execucao.status = 'concluida' if resultado[:parar]

      @execucao.no_atual = @execucao.grafo.proximo(no['id'], resultado[:saida])
      return esperar(resultado[:esperar_ate]) if resultado[:esperar_ate] && !@execucao.contexto['pular_esperas']
    end
    @execucao.assign_attributes(status: 'falhou', erro: "passou de #{LIMITE_PASSOS} passos")
  end

  def executar(no)
    Current.executed_by = @execucao
    resultado = PASSOS.fetch(no['tipo']).public_send(no['tipo'], no['config'] || {}, Ramon::Fluxos::Contexto.new(@execucao))
    @execucao.tentativas = 0
    @execucao.contexto = @execucao.contexto.merge('vars' => (@execucao.contexto['vars'] || {}).merge(resultado[:vars] || {}))
    resultado
  rescue StandardError => e
    tratar_erro(no, e)
    nil
  ensure
    Current.executed_by = nil
  end

  def tratar_erro(no, erro)
    espera = ESPERAS_ERRO[@execucao.tentativas] unless @execucao.ensaio || erro.is_a?(Ramon::Fluxos::PassoImpossivel)
    if espera
      @execucao.assign_attributes(tentativas: @execucao.tentativas + 1, status: 'esperando', retomar_em: espera.minutes.from_now)
    else
      @execucao.assign_attributes(status: 'falhou', erro: "#{no['id']}: #{erro.message}".truncate(500))
      @execucao.trilha = @execucao.trilha + [linha(no['id'], no['tipo'], "erro: #{erro.message}".truncate(300), erro: true)]
    end
  end

  def esperar(ate)
    @execucao.assign_attributes(status: 'esperando', retomar_em: ate)
  end

  def registrar(no, resultado)
    @execucao.trilha = @execucao.trilha + [linha(no['id'], no['tipo'], resultado[:resumo], saida: resultado[:saida])]
    return if @execucao.ensaio || VISIVEIS.exclude?(no['tipo'])

    Ramon::EventoInline.registrar(@execucao.conversa, "⚙ Fluxo #{@execucao.fluxo.nome}: #{resultado[:resumo]}", tipo: 'fluxo')
  end

  def linha(no, tipo, resumo, saida: nil, erro: false)
    { 'no' => no, 'tipo' => tipo, 'em' => Time.current.iso8601, 'saida' => saida, 'resumo' => resumo, 'erro' => erro }
  end

  def avisar_falha
    fluxo = @execucao.fluxo
    lead = @execucao.lead
    if lead
      admins = fluxo.account.account_users.administrator.pluck(:user_id)
      Ramon::LeadNotificationBuilder.new(lead: lead, notification_type: 'ramon_fluxo_falhou',
                                         meta: { 'label' => fluxo.nome }, user_ids: admins).perform
    end
    Ramon::NtfyPushJob.perform_later(title: "Fluxo falhou: #{fluxo.nome}", body: @execucao.erro.to_s.truncate(200))
  end
end
```

Nota: o `ensure` zera `Current.executed_by`; o `AutomationRules::ActionService#perform` também chama `Current.reset` — por isso o executor seta `executed_by` a cada passo, nunca uma vez só.

- [ ] **Step 3: Commit**

```bash
git add app/services/ramon/fluxos/executor.rb spec/services/ramon/fluxos/executor_spec.rb
git commit -m "feat(fluxos): executor — trilha, espera, tentativas, cancelamento e ensaio"
```

---

### Task 6: Disparo, job de avanço e ensaio

**Files:**
- Create: `app/services/ramon/fluxos/disparo.rb`, `app/jobs/ramon/fluxo_avancar_job.rb`
- Test: `spec/services/ramon/fluxos/disparo_spec.rb`

**Interfaces:**
- Consumes: `Fluxo.executaveis`, `Fluxo#limite_atingido?`, `Grafo#gatilho/#proximo`, `Executor#avancar!`.
- Produces:
  - `Ramon::Fluxos::Disparo.call(gatilho_tipo, alvo, dados = {}, origem: nil) -> Array<FluxoExecucao>` (eventos; `origem` = `FluxoExecucao` autora do evento ou nil)
  - `Ramon::Fluxos::Disparo.manual(fluxo, alvo) -> FluxoExecucao|nil`
  - `Ramon::Fluxos::Disparo.ensaiar(fluxo, alvo, usar: 'rascunho'|'publicada') -> FluxoExecucao` (síncrono, já avançada)
  - `Ramon::FluxoAvancarJob.perform_later(execucao_id)`
  - `Disparo::PROFUNDIDADE_MAX = 3`

- [ ] **Step 1: Spec**

```ruby
require 'rails_helper'

RSpec.describe Ramon::Fluxos::Disparo do
  let(:account) { create(:account) }
  let(:conversa) { create(:conversation, account: account) }
  let(:lead) { create(:lead, account: account, conversation: conversa, contact: conversa.contact) }
  let(:nota) { ['nota_privada', { 'texto' => 'oi' }] }

  it 'cria execução e enfileira o avanço' do
    fluxo = fluxo_publicado(account, grafo_linear({ 'tipo' => 'lead_criado' }, nota))
    expect { described_class.call('lead_criado', lead) }.to have_enqueued_job(Ramon::FluxoAvancarJob)
    e = fluxo.execucoes.last
    expect(e).to have_attributes(status: 'rodando', no_atual: 'p1', profundidade: 0)
    expect(e.trilha.first['tipo']).to eq('gatilho')
    expect(e.contexto['etapa_inicial_id']).to eq(lead.lead_stage_id)
  end

  it 'rajada no mesmo alvo vira uma execução só' do
    fluxo = fluxo_publicado(account, grafo_linear({ 'tipo' => 'mensagem_recebida' }, nota))
    5.times { described_class.call('mensagem_recebida', conversa, { 'caixa_id' => conversa.inbox_id }) }
    expect(fluxo.execucoes.count).to eq(1)
  end

  it 'respeita filtro de caixa e de etapa' do
    fluxo_publicado(account, grafo_linear({ 'tipo' => 'conversa_criada', 'caixa_ids' => [conversa.inbox_id + 1] }, nota))
    expect(described_class.call('conversa_criada', conversa, { 'caixa_id' => conversa.inbox_id })).to eq([])

    fluxo_publicado(account, grafo_linear({ 'tipo' => 'lead_mudou_etapa', 'para_etapa_ids' => [999] }, nota))
    expect(described_class.call('lead_mudou_etapa', lead, { 'para_etapa_id' => lead.lead_stage_id })).to eq([])
  end

  it 'respeita o limite do dia e ignora desligado' do
    fluxo = fluxo_publicado(account, grafo_linear({ 'tipo' => 'lead_criado' }, nota), limite_dia: 1)
    described_class.call('lead_criado', lead)
    described_class.call('lead_criado', create(:lead, account: account))
    expect(fluxo.execucoes.count).to eq(1)

    fluxo.update!(ativo: false)
    expect(described_class.call('lead_criado', create(:lead, account: account))).to eq([])
  end

  it 'cadeia: não redispara a si mesmo e para na profundidade 3' do
    a = fluxo_publicado(account, grafo_linear({ 'tipo' => 'lead_mudou_etapa' }, nota))
    origem = a.execucoes.create!(account: account, alvo: lead, profundidade: 0, status: 'concluida')
    expect(described_class.call('lead_mudou_etapa', lead, {}, origem: origem)).to eq([])

    b = fluxo_publicado(account, grafo_linear({ 'tipo' => 'lead_mudou_etapa' }, nota))
    funda = a.execucoes.create!(account: account, alvo: lead, profundidade: 3, status: 'concluida')
    expect(described_class.call('lead_mudou_etapa', lead, {}, origem: funda)).to eq([])
    rasa = a.execucoes.create!(account: account, alvo: lead, profundidade: 1, status: 'concluida')
    expect(described_class.call('lead_mudou_etapa', lead, {}, origem: rasa).map(&:fluxo)).to eq([b])
    expect(b.execucoes.last.profundidade).to eq(2)
  end

  it 'modo sombra cria execução de ensaio' do
    fluxo = fluxo_publicado(account, grafo_linear({ 'tipo' => 'lead_criado' }, nota), modo: 'sombra')
    described_class.call('lead_criado', lead)
    expect(fluxo.execucoes.last.ensaio).to be(true)
  end

  it 'ensaio do rascunho roda na hora e não grava nada' do
    fluxo = fluxo_publicado(account, grafo_linear({ 'tipo' => 'manual' }, nota))
    fluxo.update!(rascunho: grafo_linear({ 'tipo' => 'manual' }, ['esperar', { 'quantidade' => 1, 'unidade' => 'dias' }], nota))
    e = nil
    expect { e = described_class.ensaiar(fluxo, lead, usar: 'rascunho') }.not_to(change { conversa.messages.count })
    expect(e).to have_attributes(status: 'concluida', ensaio: true, versao_id: nil)
    expect(e.trilha.pluck('no')).to eq(%w[g p1 p2])
  end

  it 'manual só para fluxo com gatilho manual' do
    manual = fluxo_publicado(account, grafo_linear({ 'tipo' => 'manual' }, nota))
    outro = fluxo_publicado(account, grafo_linear({ 'tipo' => 'lead_criado' }, nota))
    expect(described_class.manual(manual, lead)).to be_a(FluxoExecucao)
    expect(described_class.manual(outro, lead)).to be_nil
  end
end
```

- [ ] **Step 2: Implementação**

`app/services/ramon/fluxos/disparo.rb`:

```ruby
# Transforma um evento (ou um clique) em execuções de fluxo (spec §6): acha os fluxos
# ativos com aquele gatilho, aplica o filtro, o limite do dia e a profundidade de cadeia,
# e cria a execução — o índice único parcial barra 2 execuções vivas no mesmo alvo.
class Ramon::Fluxos::Disparo
  PROFUNDIDADE_MAX = 3

  def self.call(gatilho_tipo, alvo, dados = {}, origem: nil)
    account = alvo.account
    account.fluxos.executaveis.where(gatilho_tipo: gatilho_tipo).includes(:versao_publicada).filter_map do |fluxo|
      new(fluxo, alvo, dados, origem).iniciar if passa?(fluxo, dados, origem)
    end
  end

  def self.manual(fluxo, alvo)
    return unless fluxo.gatilho_tipo == 'manual' && fluxo.versao_publicada && !fluxo.limite_atingido?

    new(fluxo, alvo, {}, nil).iniciar
  end

  def self.ensaiar(fluxo, alvo, usar: 'rascunho')
    new(fluxo, alvo, {}, nil, ensaio: usar).iniciar
  end

  def self.passa?(fluxo, dados, origem)
    if origem
      return false if origem.fluxo_id == fluxo.id || origem.profundidade + 1 > PROFUNDIDADE_MAX
    end
    return false if fluxo.modo == 'normal' && fluxo.limite_atingido?

    filtro_ok?(Ramon::Fluxos::Grafo.new(fluxo.versao_publicada.grafo).gatilho['config'] || {}, dados)
  end

  def self.filtro_ok?(config, dados)
    { 'caixa_ids' => 'caixa_id', 'de_etapa_ids' => 'de_etapa_id', 'para_etapa_ids' => 'para_etapa_id' }.all? do |filtro, campo|
      lista = Array(config[filtro]).map(&:to_i)
      lista.empty? || lista.include?(dados[campo].to_i)
    end
  end

  def initialize(fluxo, alvo, dados, origem, ensaio: nil)
    @fluxo = fluxo
    @alvo = alvo
    @dados = dados
    @origem = origem
    @ensaio = ensaio
  end

  def iniciar
    execucao = @fluxo.execucoes.create!(atributos)
    return Ramon::Fluxos::Executor.new(execucao).avancar! if @ensaio

    Ramon::FluxoAvancarJob.perform_later(execucao.id)
    execucao
  rescue ActiveRecord::RecordNotUnique
    nil # já existe execução viva desse fluxo nesse alvo
  end

  private

  def atributos
    g = grafo.gatilho
    {
      account: @fluxo.account, versao: (@ensaio == 'rascunho' ? nil : @fluxo.versao_publicada), alvo: @alvo,
      ensaio: @ensaio.present? || @fluxo.modo == 'sombra', profundidade: @origem ? @origem.profundidade + 1 : 0,
      no_atual: grafo.proximo(g['id'], 's'), contexto: contexto,
      trilha: [{ 'no' => g['id'], 'tipo' => 'gatilho', 'em' => Time.current.iso8601, 'saida' => 's',
                 'resumo' => g.dig('config', 'tipo'), 'erro' => false }]
    }
  end

  def grafo
    @grafo ||= Ramon::Fluxos::Grafo.new(@ensaio == 'rascunho' ? @fluxo.rascunho : @fluxo.versao_publicada.grafo)
  end

  def contexto
    lead = @alvo.is_a?(Lead) ? @alvo : @fluxo.account.leads.where(conversation_id: @alvo.id).reorder(id: :desc).first
    base = { 'gatilho' => @dados, 'vars' => {}, 'etapa_inicial_id' => lead&.lead_stage_id }
    base['grafo'] = @fluxo.rascunho if @ensaio == 'rascunho'
    base['pular_esperas'] = true if @ensaio
    base.compact
  end
end
```

`app/jobs/ramon/fluxo_avancar_job.rb`:

```ruby
# Anda uma execução de fluxo (criada pelo Disparo ou retomada pelo relógio).
class Ramon::FluxoAvancarJob < ApplicationJob
  queue_as :default

  def perform(execucao_id)
    execucao = FluxoExecucao.find_by(id: execucao_id)
    Ramon::Fluxos::Executor.new(execucao).avancar! if execucao
  end
end
```

- [ ] **Step 3: Commit + CI**

```bash
git add app/services/ramon/fluxos/disparo.rb app/jobs/ramon/fluxo_avancar_job.rb spec/services/ramon/fluxos/disparo_spec.rb
git commit -m "feat(fluxos): disparo com filtro, limite, cadeia, sombra, manual e ensaio"
```

Empurrar e conferir CI (Tasks 5–6) antes da Task 7.

---

### Task 7: Ouvinte de eventos

**Files:**
- Create: `app/listeners/ramon_fluxo_listener.rb`
- Modify: `app/dispatchers/async_dispatcher.rb:24` (registrar), `app/models/lead.rb:220-224` (`dispatch_update_event`)
- Test: `spec/listeners/ramon_fluxo_listener_spec.rb`

**Interfaces:**
- Consumes: `Ramon::Fluxos::Disparo.call(tipo, alvo, dados, origem:)`.
- Produces: evento `lead.updated` agora carrega `changed_attributes: { 'lead_stage_id' => [de, para] }` (só quando mudou) e `performed_by: Current.executed_by`.

- [ ] **Step 1: Spec**

```ruby
require 'rails_helper'

RSpec.describe RamonFluxoListener do
  let(:listener) { described_class.instance }
  let(:account) { create(:account) }
  let(:conversa) { create(:conversation, account: account) }
  let(:lead) { create(:lead, account: account, conversation: conversa) }

  def evento(nome, dados) = Events::Base.new(nome, Time.zone.now, dados)

  it 'mensagem recebida dispara com o texto; nota privada não' do
    msg = create(:message, conversation: conversa, account: account, inbox: conversa.inbox, message_type: :incoming, content: 'oi')
    expect(Ramon::Fluxos::Disparo).to receive(:call)
      .with('mensagem_recebida', conversa, hash_including('texto' => 'oi', 'caixa_id' => conversa.inbox_id), origem: nil)
    listener.message_created(evento('message.created', message: msg))

    nota = create(:message, conversation: conversa, account: account, inbox: conversa.inbox, message_type: :outgoing, private: true)
    expect(Ramon::Fluxos::Disparo).not_to receive(:call)
    listener.message_created(evento('message.created', message: nota))
  end

  it 'etapa mudou dispara etapa + ganho, com a execução autora como origem' do
    ganho = create(:lead_stage, account: account, is_won: true, position: 9)
    de = lead.lead_stage_id
    lead.update!(lead_stage: ganho)
    autora = fluxo_publicado(account, grafo_linear({ 'tipo' => 'manual' })).execucoes.create!(account: account, alvo: lead)
    dados = { 'de_etapa_id' => de, 'para_etapa_id' => ganho.id }
    expect(Ramon::Fluxos::Disparo).to receive(:call).with('lead_mudou_etapa', lead, dados, origem: autora)
    expect(Ramon::Fluxos::Disparo).to receive(:call).with('lead_ganho', lead, dados, origem: autora)
    listener.lead_updated(evento('lead.updated', lead: lead, changed_attributes: { 'lead_stage_id' => [de, ganho.id] },
                                                 performed_by: autora))
  end

  it 'lead atualizado sem troca de etapa não dispara' do
    expect(Ramon::Fluxos::Disparo).not_to receive(:call)
    listener.lead_updated(evento('lead.updated', lead: lead, changed_attributes: {}))
  end

  it 'o modelo Lead manda a troca de etapa no evento' do
    nova = create(:lead_stage, account: account, position: 3)
    lead
    allow(Rails.configuration.dispatcher).to receive(:dispatch)
    lead.update!(lead_stage: nova)
    expect(Rails.configuration.dispatcher).to have_received(:dispatch)
      .with(Events::Types::LEAD_UPDATED, anything, hash_including(changed_attributes: { 'lead_stage_id' => [anything, nova.id] }))
  end
end
```

- [ ] **Step 2: Ouvinte**

`app/listeners/ramon_fluxo_listener.rb`:

```ruby
# Automações em fluxo: traduz eventos do hub em gatilhos de fluxo (spec §4.1).
# `performed_by` = execução de fluxo que causou o evento (cadeia/profundidade).
class RamonFluxoListener < BaseListener
  def conversation_created(event) = disparar('conversa_criada', event.data[:conversation], event)

  def conversation_resolved(event) = disparar('conversa_resolvida', event.data[:conversation], event)

  def conversation_opened(event) = disparar('conversa_reaberta', event.data[:conversation], event)

  def assignee_changed(event) = disparar('conversa_atribuida', event.data[:conversation], event)

  def message_created(event)
    message = event.data[:message]
    return unless message.incoming? && !message.private?

    disparar('mensagem_recebida', message.conversation, event, 'texto' => message.content.to_s.truncate(500))
  end

  def lead_created(event) = disparar('lead_criado', event.data[:lead], event)

  def lead_updated(event)
    de, para = (event.data[:changed_attributes] || {})['lead_stage_id']
    return if para.nil?

    lead = event.data[:lead]
    dados = { 'de_etapa_id' => de, 'para_etapa_id' => para }
    disparar('lead_mudou_etapa', lead, event, dados)
    disparar('lead_ganho', lead, event, dados) if lead.lead_stage&.is_won
    disparar('lead_perdido', lead, event, dados) if lead.lead_stage&.is_lost
  end

  private

  def disparar(tipo, alvo, event, dados = {})
    return if alvo.nil?

    base = alvo.is_a?(Conversation) ? { 'caixa_id' => alvo.inbox_id } : {}
    autor = event.data[:performed_by]
    Ramon::Fluxos::Disparo.call(tipo, alvo, base.merge(dados), origem: autor.is_a?(FluxoExecucao) ? autor : nil)
  end
end
```

`app/dispatchers/async_dispatcher.rb` — na lista:

```ruby
      RamonLeadListener.instance,
      RamonAgenteListener.instance,
      RamonFluxoListener.instance
```

`app/models/lead.rb` — `dispatch_update_event`:

```ruby
  def dispatch_update_event
    return if Current.suppress_import_events

    # changed_attributes/performed_by: gatilhos de fluxo (etapa mudou; cadeia entre fluxos)
    Rails.configuration.dispatcher.dispatch(Events::Types::LEAD_UPDATED, Time.zone.now, lead: self,
                                                                                    changed_attributes: saved_changes.slice('lead_stage_id'),
                                                                                    performed_by: Current.executed_by)
  end
```

- [ ] **Step 3: Commit**

```bash
git add app/listeners/ramon_fluxo_listener.rb app/dispatchers/async_dispatcher.rb app/models/lead.rb spec/listeners/ramon_fluxo_listener_spec.rb
git commit -m "feat(fluxos): ouvinte de eventos de conversa e lead"
```

---

### Task 8: Relógio

**Files:**
- Create: `app/jobs/ramon/fluxo_relogio_job.rb`
- Modify: `config/schedule.yml` (bloco novo após `ramon_night_copilot_job`)
- Test: `spec/jobs/ramon/fluxo_relogio_job_spec.rb`

**Interfaces:**
- Consumes: `Ramon::FluxoAvancarJob`.
- Produces: cron `ramon_fluxo_relogio_job` a cada minuto.

- [ ] **Step 1: Spec**

```ruby
require 'rails_helper'

RSpec.describe Ramon::FluxoRelogioJob do
  let(:account) { create(:account) }
  let(:fluxo) { fluxo_publicado(account, grafo_linear({ 'tipo' => 'manual' })) }
  let(:lead) { create(:lead, account: account) }

  it 'retoma só as esperas vencidas' do
    vencida = fluxo.execucoes.create!(account: account, alvo: lead, status: 'esperando', retomar_em: 1.minute.ago)
    fluxo.execucoes.create!(account: account, alvo: create(:lead, account: account), status: 'esperando', retomar_em: 1.hour.from_now)
    expect { described_class.perform_now }.to have_enqueued_job(Ramon::FluxoAvancarJob).with(vencida.id).exactly(:once)
  end
end
```

- [ ] **Step 2: Implementação**

`app/jobs/ramon/fluxo_relogio_job.rb`:

```ruby
# Relógio dos fluxos (a cada minuto): retoma execuções cuja espera venceu.
# Nada fica preso em perform_in longo — deploy/reinício não perde quem esperava.
# ponytail: 500 por minuto; paginar se a fila de esperas passar disso.
class Ramon::FluxoRelogioJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    FluxoExecucao.where(status: 'esperando', retomar_em: ..Time.current).order(:retomar_em).limit(500).pluck(:id)
                 .each { |id| Ramon::FluxoAvancarJob.perform_later(id) }
  end
end
```

`config/schedule.yml`:

```yaml
# a cada minuto: retoma execuções de fluxo cuja espera venceu (Automações em fluxo)
ramon_fluxo_relogio_job:
  cron: '*/1 * * * *'
  class: 'Ramon::FluxoRelogioJob'
  queue: scheduled_jobs
```

- [ ] **Step 3: Commit + CI**

```bash
git add app/jobs/ramon/fluxo_relogio_job.rb config/schedule.yml spec/jobs/ramon/fluxo_relogio_job_spec.rb
git commit -m "feat(fluxos): relógio que retoma esperas vencidas"
```

Empurrar e conferir CI (Tasks 7–8).

---

### Task 9: API (só admin)

**Files:**
- Create: `app/policies/ramon_fluxo_policy.rb`, `app/controllers/api/v1/accounts/ramon_fluxos_controller.rb`, `app/controllers/api/v1/accounts/ramon_fluxo_execucoes_controller.rb`
- Modify: `config/routes.rb:334` (perto de `ramon_watchdog`), `app/models/fluxo.rb` (`resumo_json`), `app/models/fluxo_execucao.rb` (`resumo_json`)
- Test: `spec/controllers/api/v1/accounts/ramon_fluxos_controller_spec.rb`

**Interfaces:**
- Consumes: `Fluxo#publicar!`, `Disparo.ensaiar/.manual`.
- Produces (contrato da B2):
  - `GET /api/v1/accounts/:id/ramon_fluxos` → `{ payload: [Fluxo#resumo_json], resumo: { ligados, total, hoje, esperando, falharam_24h } }`
  - `GET …/ramon_fluxos/:id` → `resumo_json + { rascunho, versoes: [{numero, created_at}] }`
  - `POST …/ramon_fluxos` `{ nome, descricao?, rascunho? }` · `PATCH …/:id` `{ nome?, descricao?, ativo?, limite_dia?, modo?, rascunho? }` · `DELETE …/:id`
  - `POST …/:id/publicar` → 200 `{ versao }` | 422 `{ erros: [..] }`
  - `POST …/:id/ensaio` `{ lead_id | conversation_id (display_id), usar }` → `FluxoExecucao#resumo_json`
  - `POST …/:id/rodar` `{ lead_id | conversation_id }` → execução | 422
  - `GET …/:id/execucoes?status=` (100 mais novas) · `GET …/:id/execucoes/:execucao_id`
  - Fluxo do sistema (`origem: 'sistema'`): `update/destroy/publicar/rodar` → 403.

- [ ] **Step 1: Spec**

```ruby
require 'rails_helper'

RSpec.describe 'Ramon Fluxos API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agente) { create(:user, account: account, role: :agent) }
  let(:url) { "/api/v1/accounts/#{account.id}/ramon_fluxos" }
  let(:grafo) { grafo_linear({ 'tipo' => 'manual' }, ['nota_privada', { 'texto' => 'oi' }]) }

  it 'agente não acessa' do
    get url, headers: agente.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it 'cria, edita o rascunho, publica e lista com contadores' do
    post url, params: { nome: 'Pós-contrato', rascunho: grafo }, headers: admin.create_new_auth_token, as: :json
    id = response.parsed_body['id']
    patch "#{url}/#{id}", params: { ativo: true, limite_dia: 20 }, headers: admin.create_new_auth_token, as: :json
    post "#{url}/#{id}/publicar", headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body).to include('versao' => 1)

    get url, headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['payload'].first).to include('nome' => 'Pós-contrato', 'gatilho_tipo' => 'manual', 'versao' => 1,
                                                             'ativo' => true, 'hoje' => 0)
    expect(response.parsed_body['resumo']).to include('ligados' => 1, 'total' => 1)
  end

  it 'publicar inválido devolve os erros' do
    post url, params: { nome: 'X', rascunho: { nos: [], setas: [] } }, headers: admin.create_new_auth_token, as: :json
    post "#{url}/#{response.parsed_body['id']}/publicar", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['erros']).to include('O fluxo precisa de exatamente 1 gatilho')
  end

  it 'ensaio com um lead devolve a trilha' do
    fluxo = fluxo_publicado(account, grafo)
    lead = create(:lead, account: account)
    post "#{url}/#{fluxo.id}/ensaio", params: { lead_id: lead.id, usar: 'publicada' }, headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body).to include('status' => 'concluida', 'ensaio' => true)
    expect(response.parsed_body['trilha'].pluck('no')).to eq(%w[g p1])
  end

  it 'fluxo do sistema é só leitura' do
    fluxo = fluxo_publicado(account, grafo, origem: 'sistema')
    patch "#{url}/#{fluxo.id}", params: { nome: 'Y' }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
  end

  it 'lista execuções do fluxo' do
    fluxo = fluxo_publicado(account, grafo)
    Ramon::Fluxos::Disparo.manual(fluxo, create(:lead, account: account))
    get "#{url}/#{fluxo.id}/execucoes", headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['payload'].size).to eq(1)
  end
end
```

- [ ] **Step 2: Policy**

`app/policies/ramon_fluxo_policy.rb`:

```ruby
# Automações em fluxo: só administradores montam, publicam, ensaiam e veem execuções.
class RamonFluxoPolicy < ApplicationPolicy
  def gerenciar?
    @account_user.administrator?
  end
end
```

- [ ] **Step 3: JSON dos modelos**

Em `app/models/fluxo.rb`, antes do `end` final:

```ruby
  # ponytail: contadores por fluxo (N consultas); agregar numa query se passar de ~50 fluxos.
  def resumo_json
    vivas = execucoes.where(ensaio: false)
    {
      id: id, nome: nome, descricao: descricao, gatilho_tipo: gatilho_tipo, ativo: ativo, limite_dia: limite_dia,
      origem: origem, sistema_chave: sistema_chave, modo: modo, versao: versao_publicada&.numero,
      hoje: execucoes_hoje.count, esperando: vivas.where(status: 'esperando').count,
      falharam_24h: vivas.where(status: 'falhou', updated_at: 24.hours.ago..).count,
      ultima_em: vivas.maximum(:created_at), editado_em: updated_at
    }
  end
```

Em `app/models/fluxo_execucao.rb`, antes do `end` final:

```ruby
  def resumo_json
    {
      id: id, fluxo_id: fluxo_id, versao: versao&.numero, alvo_type: alvo_type, alvo_id: alvo_id,
      alvo_nome: alvo.try(:name) || alvo&.contact&.name, conversation_display_id: conversa&.display_id,
      lead_id: lead&.id, status: status, ensaio: ensaio, no_atual: no_atual, retomar_em: retomar_em,
      trilha: trilha, erro: erro, created_at: created_at, updated_at: updated_at
    }
  end
```

- [ ] **Step 4: Controllers**

`app/controllers/api/v1/accounts/ramon_fluxos_controller.rb`:

```ruby
# Automações em fluxo (spec §7): CRUD do rascunho, publicar, ensaiar e rodar na mão.
class Api::V1::Accounts::RamonFluxosController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :fluxo, except: [:index, :create]
  before_action :bloquear_sistema, only: [:update, :destroy, :publicar, :rodar]

  def index
    fluxos = Current.account.fluxos.includes(:versao_publicada).order(:origem, :nome)
    payload = fluxos.map(&:resumo_json)
    render json: { payload: payload, resumo: resumo(payload) }
  end

  def show
    render json: @fluxo.resumo_json.merge(rascunho: @fluxo.rascunho,
                                          versoes: @fluxo.versoes.order(numero: :desc).map { |v| { numero: v.numero, created_at: v.created_at } })
  end

  def create
    fluxo = Current.account.fluxos.create!(fluxo_params.merge(created_by: Current.user))
    render json: fluxo.resumo_json
  end

  def update
    @fluxo.update!(fluxo_params)
    render json: @fluxo.resumo_json
  end

  def destroy
    @fluxo.destroy!
    head :ok
  end

  def publicar
    render json: { versao: @fluxo.publicar!(Current.user).numero }
  rescue Ramon::Fluxos::Grafo::Invalido
    render json: { erros: Ramon::Fluxos::Grafo.new(@fluxo.rascunho).erros }, status: :unprocessable_entity
  end

  def ensaio
    render json: Ramon::Fluxos::Disparo.ensaiar(@fluxo, alvo, usar: params[:usar].presence_in(%w[rascunho publicada]) || 'rascunho').resumo_json
  end

  def rodar
    execucao = Ramon::Fluxos::Disparo.manual(@fluxo, alvo)
    return render json: { erro: 'FLUXO_NAO_RODOU' }, status: :unprocessable_entity if execucao.nil?

    render json: execucao.resumo_json
  end

  private

  def check_authorization
    authorize(:ramon_fluxo, :gerenciar?)
  end

  def fluxo
    @fluxo = Current.account.fluxos.find(params[:id])
  end

  def bloquear_sistema
    head :forbidden if @fluxo.origem == 'sistema'
  end

  def alvo
    return Current.account.leads.find(params[:lead_id]) if params[:lead_id].present?

    Current.account.conversations.find_by!(display_id: params[:conversation_id])
  end

  def fluxo_params
    permitidos = params.permit(:nome, :descricao, :ativo, :limite_dia, :modo).to_h
    permitidos[:rascunho] = params[:rascunho].permit!.to_h if params[:rascunho].present?
    permitidos
  end

  def resumo(payload)
    {
      ligados: payload.count { |f| f[:ativo] }, total: payload.size, hoje: payload.sum { |f| f[:hoje] },
      esperando: payload.sum { |f| f[:esperando] }, falharam_24h: payload.sum { |f| f[:falharam_24h] }
    }
  end
end
```

`app/controllers/api/v1/accounts/ramon_fluxo_execucoes_controller.rb`:

```ruby
# Execuções de um fluxo (lista e uma com a trilha) — base da tela "caminho aceso".
class Api::V1::Accounts::RamonFluxoExecucoesController < Api::V1::Accounts::BaseController
  LIMITE = 100

  before_action { authorize(:ramon_fluxo, :gerenciar?) }

  def index
    execucoes = fluxo.execucoes.includes(:versao, :alvo).order(created_at: :desc).limit(LIMITE)
    execucoes = execucoes.where(status: params[:status]) if params[:status].present?
    render json: { payload: execucoes.map(&:resumo_json) }
  end

  def show
    render json: fluxo.execucoes.find(params[:id]).resumo_json
  end

  private

  def fluxo = @fluxo ||= Current.account.fluxos.find(params[:ramon_fluxo_id])
end
```

- [ ] **Step 5: Rotas**

`config/routes.rb`, logo abaixo de `resource :ramon_watchdog, …`:

```ruby
          resources :ramon_fluxos, only: [:index, :show, :create, :update, :destroy], controller: 'ramon_fluxos' do
            member do
              post :publicar
              post :ensaio
              post :rodar
            end
            resources :execucoes, only: [:index, :show], controller: 'ramon_fluxo_execucoes'
          end
```

- [ ] **Step 6: Commit + CI**

```bash
git add app/policies/ramon_fluxo_policy.rb app/controllers/api/v1/accounts/ramon_fluxos_controller.rb app/controllers/api/v1/accounts/ramon_fluxo_execucoes_controller.rb config/routes.rb app/models/fluxo.rb app/models/fluxo_execucao.rb spec/controllers/api/v1/accounts/ramon_fluxos_controller_spec.rb
git commit -m "feat(fluxos): API de fluxos e execuções (só admin)"
```

Empurrar e conferir CI 100% verde (todos os shards + Rubocop).

---

### Task 10: Ajuste da spec, PR, deploy e prova real

**Files:**
- Modify: `docs/superpowers/specs/2026-10-05-automacoes-em-fluxo-design.md` (§5: `ensaio` boolean + `versao_id` nulo no ensaio do rascunho; §4.3: rascunho de fluxo não entra no carimbo `bi_ia` — este só mede notas do Assistente; §10: `registrar_atividade`, `trocar_responsavel` e `preencher_campo` entram na B2b)
- Create: `RAdvogados\comercial\docs\2026-10-XX-smoke-fluxos-b1.md` (data do deploy)

- [ ] **Step 1: Ajustar a spec** (as 3 refinações acima, 1 linha cada) e commitar:

```bash
git add docs/superpowers/specs/2026-10-05-automacoes-em-fluxo-design.md
git commit -m "docs(fluxos): spec — ensaio como coluna e rascunho fora do bi_ia"
```

- [ ] **Step 2: PR** — `gh pr create --base ramon` com título `feat(fluxos): motor de automações em fluxo (B1)`; corpo: parágrafo de produto ("o hub ganha um motor de fluxos; nada ligado até o smoke; a tela vem na B2"), `How to test` = roteiro do smoke. CI verde → merge squash no regime combinado (pacote).

- [ ] **Step 3: Deploy (Eduardo roda via `!`)** — imagem nova publicada → `docker compose pull && up -d` → **migração à mão**: `docker compose exec -T web bundle exec rails db:migrate:status | tail -3` (deve listar `20261005000002` como `down`; a `20261005000001` do portal já `up` se o #195 foi deployado antes) → `docker compose exec -T web bundle exec rails db:migrate` → conferir `\d ramon_fluxo_execucoes` mostra o índice `index_ramon_fluxo_execucoes_unica_ativa` → login 200 → `docker inspect` com o SHA.

- [ ] **Step 4: Prova real na VPS** (`rails runner`, lead temporário, apagado no fim):

```ruby
a = Account.find(2)
lead = a.leads.create!(name: 'TESTE FLUXO (apagar)', lead_stage: a.lead_stages.order(:position).first)
g = { 'nos' => [
  { 'id' => 'g', 'tipo' => 'gatilho', 'config' => { 'tipo' => 'manual' } },
  { 'id' => 'p1', 'tipo' => 'nota_privada', 'config' => { 'texto' => 'fluxo de teste para {nome}' } },
  { 'id' => 'p2', 'tipo' => 'esperar', 'config' => { 'quantidade' => 1, 'unidade' => 'minutos' } },
  { 'id' => 'p3', 'tipo' => 'criar_tarefa', 'config' => { 'titulo' => 'Tarefa do fluxo de teste' } }
], 'setas' => [{ 'de' => 'g', 'saida' => 's', 'para' => 'p1' }, { 'de' => 'p1', 'saida' => 's', 'para' => 'p2' },
               { 'de' => 'p2', 'saida' => 's', 'para' => 'p3' }] }
f = a.fluxos.create!(nome: 'TESTE B1', rascunho: g, ativo: true) # desligado o manual não roda
f.publicar!(nil)
puts Ramon::Fluxos::Disparo.ensaiar(f, lead, usar: 'publicada').trilha.map { |t| t['resumo'] }.inspect
e = Ramon::Fluxos::Disparo.manual(f.reload, lead)
sleep 5
puts e.reload.status # esperando
sleep 80             # relógio retoma
puts e.reload.status, lead.lead_tasks.last&.title, lead.lead_notes.last&.body # concluida / tarefa / nota
LeadActivity.where(lead_id: lead.id).delete_all
lead.lead_tasks.delete_all
lead.lead_notes.delete_all
f.destroy!
lead.destroy!
```

Esperado: ensaio com 3 resumos começando por `faria:` (exceto a espera); execução real passa por `esperando` → `concluida` com tarefa criada. Se ficar `esperando` depois de 80 s → conferir se o cron `ramon_fluxo_relogio_job` subiu (`Sidekiq::Cron::Job.find('ramon_fluxo_relogio_job')`).

- [ ] **Step 5: Smoke doc pro Eduardo** — `comercial\docs\2026-10-XX-smoke-fluxos-b1.md`: o que entrou, prova da VPS colada, e **seção em bloco** (sem tela ainda — B2): "nada mudou no uso; nenhum fluxo ligado". Atualizar a memória `automacoes-em-fluxo` (B1 no ar, SHA, próxima = B2).
