# F0 — Honorário pela tabela do POP JUR-02 · Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** o honorário que o hub calcula, mostra e fala ao lead passa a seguir a tabela do POP JUR-02 (percentual + "3", mínimo, e "fora da tabela" = não citar valor), em vez do "30% + 3 em todas as teses".

**Architecture:** três colunas novas em `theses` (mínimo qtd/base, na tabela) + `Ramon::SalarioMinimo`. `Ramon::Honorario` continua o único lugar da regra e ganha `descricao(tese)`, que vira o texto único usado pelo simulador, pelas tools do agente e pelo dossiê. A migração já grava os valores do JUR-02 nas 5 teses de produção. Textos ao cliente (diretriz, guardrail, skills, FAQs) mudam no seed e só são **ativados** (`rake ramon:inteligencia:seed[2]`) depois do aprovado do Eduardo.

**Tech Stack:** Rails 7.1 (Chatwoot 4.15 fork), RSpec, Vue 3 `<script setup>` + Vitest, Tailwind.

**Spec:** `docs/superpowers/specs/2026-10-13-roteiro-da-tese-design.md` §3.11 e §6 (F0).

## Global Constraints

- Fonte da verdade do honorário = **POP JUR-02** (`C:\Users\dudsl\RAdvogados\conhecimento\procedimentos\manual\pops.js`, linha `code: "JUR-02"`), **linha online/tráfego** de cada matéria.
- "O '3' da tabela é sempre 3 salários de benefício ou 3 salários mínimos, o que for maior." Implementação: `n × max(benefício mensal informado, salário mínimo vigente)`.
- "Aplicar o mínimo: … Vale o maior" → `valor = max(fórmula, mínimo)`.
- Salário mínimo 2026 = **R$ 1.621,00** (Decreto 12.797/2025).
- Tese fora da tabela → a IA **não cita valor** e passa para humano; texto: `Ramon::Honorario::FORA_DA_TABELA`.
- Tese criada pela tela nasce **sem honorário e fora da tabela** (POP: "Matéria que não está na tabela: alinhar com o Dr. Ramon").
- Texto que fala com cliente só é ativado com o aprovado do Eduardo (CLAUDE.md do ramon-hub). O código pode subir antes.
- Sem Ruby local (Smart App Control): Ruby é validado por **CI**; lint Ruby antes do push com `rubocop-vps` (Git Bash, ~10 s). JS roda local: `pnpm vitest run <arquivo>`.
- i18n: chaves em `en/ramon.json` **e** `pt_BR/ramon.json` (padrão do fork — a tela é em PT).
- Commits: Conventional Commits; rodapé de atribuição da sessão.

**Simplificação deliberada vs. spec §3.11:** sem coluna `honorario_formula`. "Só percentual" = `honorario_n_mensalidades` vazio; a fórmula "% **ou** 3" do JUR-02 só existe nas linhas balcão/orgânico, que nunca passam pela IA. Acrescentar quando o hub atender balcão.

## Review Focus

1. Tese criada pela tela depois do deploy → nasce fora da tabela; a IA não cita valor (Task 2, request spec).
2. Benefício mensal **abaixo** do salário mínimo (auxílio-acidente costuma ser 50% do SB) → o "3" usa o salário mínimo (Task 1).
3. Atrasados pequenos → vale o **mínimo**, não a fórmula (Task 1).
4. Simulador do painel numa tese fora da tabela → devolve `valor: nil` + motivo, a tela mostra o aviso e não quebra (Task 2 e 3).
5. Admin apaga o mínimo na tela (manda `''`) → salva `nil`, não `0` nem erro 422 (Task 2).

---

### Task 1: Dados e regra do honorário

**Files:**
- Create: `db/migrate/20261013100001_add_jur02_to_theses.rb`
- Modify: `db/schema.rb` (bloco `create_table "theses"` + versão no topo)
- Create: `app/services/ramon/salario_minimo.rb`
- Modify: `app/services/ramon/honorario.rb`
- Modify: `app/models/thesis.rb`
- Create: `spec/services/ramon/honorario_spec.rb`
- Modify: `spec/models/thesis_spec.rb`

**Interfaces:**
- Produces:
  - colunas `theses.honorario_minimo_qtd :integer`, `theses.honorario_minimo_base :string` (`'sm'|'sb'`), `theses.honorario_na_tabela :boolean, default: false, null: false`
  - `Ramon::SalarioMinimo.vigente(data = Date.current) -> BigDecimal`
  - `Ramon::Honorario.calcular(tese, atrasados:, mensal:) -> Hash` com `:valor` (String "%.2f" ou nil), `:motivo` (quando nil), `:percentual` (Float), `:n_mensalidades` (Integer), `:tese` (String), `:descricao` (String)
  - `Ramon::Honorario.descricao(tese) -> String | nil` (nil = sem tese ou sem honorário configurado)
  - constantes `Ramon::Honorario::SEM_CONFIG`, `Ramon::Honorario::FORA_DA_TABELA`

- [ ] **Step 1: Escrever o spec da regra (falha)**

`spec/services/ramon/honorario_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe Ramon::Honorario do
  let(:account) { create(:account) }

  def tese(**attrs)
    create(:thesis, account: account, name: "Tese #{SecureRandom.hex(3)}", honorario_na_tabela: true, **attrs)
  end

  describe '.calcular' do
    it 'soma o percentual dos atrasados e 3 benefícios' do
      t = tese(honorario_percentual: 30, honorario_n_mensalidades: 3)
      res = described_class.calcular(t, atrasados: 10_000, mensal: 2000)
      expect(res[:valor]).to eq('9000.00') # 3000 + 3 × 2000
    end

    it 'usa o salário mínimo no "3" quando o benefício é menor que ele' do
      t = tese(honorario_percentual: 30, honorario_n_mensalidades: 3)
      res = described_class.calcular(t, atrasados: 10_000, mensal: 800)
      expect(res[:valor]).to eq('7863.00') # 3000 + 3 × 1621
    end

    it 'vale o mínimo quando ele é maior que a fórmula' do
      t = tese(honorario_percentual: 30, honorario_minimo_qtd: 1, honorario_minimo_base: 'sb')
      res = described_class.calcular(t, atrasados: 1000, mensal: 2000)
      expect(res[:valor]).to eq('2000.00') # 300 < 1 × 2000
    end

    it 'mínimo em salários mínimos' do
      t = tese(honorario_percentual: 30, honorario_n_mensalidades: 3, honorario_minimo_qtd: 3, honorario_minimo_base: 'sm')
      res = described_class.calcular(t, atrasados: 0, mensal: 500)
      expect(res[:valor]).to eq('4863.00') # 3 × 1621 (fórmula = mínimo)
    end

    it 'tese fora da tabela não calcula e explica o motivo' do
      t = create(:thesis, account: account, honorario_percentual: 30, honorario_n_mensalidades: 3)
      res = described_class.calcular(t, atrasados: 10_000, mensal: 2000)
      expect(res).to eq(valor: nil, motivo: described_class::FORA_DA_TABELA)
    end

    it 'tese na tabela sem percentual nem mensalidades é sem configuração' do
      res = described_class.calcular(tese, atrasados: 1, mensal: 1)
      expect(res).to eq(valor: nil, motivo: described_class::SEM_CONFIG)
    end

    it 'sem tese é sem configuração' do
      expect(described_class.calcular(nil, atrasados: 1, mensal: 1)[:motivo]).to eq(described_class::SEM_CONFIG)
    end
  end

  describe '.descricao' do
    it 'auxílio-acidente (online)' do
      t = tese(honorario_percentual: 30, honorario_n_mensalidades: 3, honorario_minimo_qtd: 3, honorario_minimo_base: 'sm')
      expect(described_class.descricao(t)).to eq('30% dos atrasados + 3 benefícios, mínimo 3 salários mínimos')
    end

    it 'só percentual com mínimo de 1 benefício' do
      t = tese(honorario_percentual: 30, honorario_minimo_qtd: 1, honorario_minimo_base: 'sb')
      expect(described_class.descricao(t)).to eq('30% dos atrasados, mínimo 1 benefício')
    end

    it 'percentual fracionado com vírgula, sem mensalidades zeradas' do
      t = tese(honorario_percentual: 12.5, honorario_n_mensalidades: 0)
      expect(described_class.descricao(t)).to eq('12,5% dos atrasados')
    end

    it 'fora da tabela' do
      expect(described_class.descricao(create(:thesis, account: account))).to eq(described_class::FORA_DA_TABELA)
    end

    it 'sem configuração devolve nil' do
      expect(described_class.descricao(tese)).to be_nil
    end
  end

  describe Ramon::SalarioMinimo do
    it 'vale R$ 1.621 em 2026' do
      expect(described_class.vigente(Date.new(2026, 10, 13))).to eq(BigDecimal('1621'))
    end
  end
end
```

Acrescentar no fim de `spec/models/thesis_spec.rb` (antes do último `end`):

```ruby
  it 'nasce fora da tabela de honorários' do
    expect(account.theses.create!(name: 'Tese Nova JUR-02').honorario_na_tabela).to be false
  end

  it 'aceita só sm ou sb como base do mínimo' do
    expect(account.theses.build(name: 'Base Ruim', honorario_minimo_base: 'xx')).not_to be_valid
    expect(account.theses.build(name: 'Base SM', honorario_minimo_base: 'sm')).to be_valid
  end

  it 'rejeita mínimo negativo' do
    expect(account.theses.build(name: 'Min Neg', honorario_minimo_qtd: -1)).not_to be_valid
  end
```

- [ ] **Step 2: Migração (colunas + valores do JUR-02 nas 5 teses)**

`db/migrate/20261013100001_add_jur02_to_theses.rb`:

```ruby
# Honorário pela tabela do POP JUR-02 (decisão Eduardo 13/10/2026), linha online/tráfego.
# Tese não listada (BPC, acréscimo de 25%, maternidade, criadas na tela) fica fora da tabela:
# a IA não cita valor e o Dr. Ramon define.
class AddJur02ToTheses < ActiveRecord::Migration[7.1]
  JUR02 = {
    'Auxílio-acidente (B36)' => { pct: 30, n: 3, min: 3, base: 'sm' },
    'Auxílio por incapacidade temporária (auxílio-doença / B31)' => { pct: 30, n: nil, min: 1, base: 'sb' },
    'Aposentadoria por incapacidade permanente (invalidez / B32)' => { pct: 30, n: nil, min: 3, base: 'sb' }
  }.freeze

  def up
    add_column :theses, :honorario_minimo_qtd, :integer
    add_column :theses, :honorario_minimo_base, :string
    add_column :theses, :honorario_na_tabela, :boolean, default: false, null: false

    JUR02.each do |nome, v|
      execute <<~SQL.squish
        UPDATE theses SET honorario_percentual = #{v[:pct]},
          honorario_n_mensalidades = #{v[:n] || 'NULL'},
          honorario_minimo_qtd = #{v[:min]}, honorario_minimo_base = '#{v[:base]}',
          honorario_na_tabela = TRUE
        WHERE name = #{connection.quote(nome)}
      SQL
    end
  end

  def down
    remove_column :theses, :honorario_minimo_qtd
    remove_column :theses, :honorario_minimo_base
    remove_column :theses, :honorario_na_tabela
  end
end
```

Em `db/schema.rb`: trocar a versão do topo para `2026_10_13_100001` (só se for maior que a atual) e, no bloco `create_table "theses"`, logo depois de `t.integer "honorario_n_mensalidades"`:

```ruby
    t.integer "honorario_minimo_qtd"
    t.string "honorario_minimo_base"
    t.boolean "honorario_na_tabela", default: false, null: false
```

- [ ] **Step 3: Model**

`app/models/thesis.rb` — apagar o comentário e a constante `HONORARIO_PADRAO` (o controller deixa de usar na Task 2) e acrescentar as validações:

```ruby
class Thesis < ApplicationRecord
  belongs_to :account
  has_many :thesis_items, -> { order(:position) }, dependent: :destroy, inverse_of: :thesis
  has_many :leads, dependent: :nullify

  validates :name, presence: true, uniqueness: { scope: :account_id }
  validates :honorario_percentual,
            numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 },
            allow_nil: true
  validates :honorario_n_mensalidades, :honorario_minimo_qtd,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 },
            allow_nil: true
  validates :honorario_minimo_base, inclusion: { in: %w[sm sb] }, allow_nil: true
  default_scope { order(:position) }
end
```

- [ ] **Step 4: Salário mínimo**

`app/services/ramon/salario_minimo.rb`:

```ruby
# Salário mínimo nacional por ano — único lugar do valor (honorário, calculadoras do roteiro).
# ponytail: tabela no código; atualizar todo janeiro (checklist de jan/2027 junto com as LPs).
# Ano sem valor cadastrado usa o último conhecido.
module Ramon::SalarioMinimo
  VALORES = { 2026 => BigDecimal('1621.00') }.freeze # Decreto 12.797/2025

  module_function

  def vigente(data = Date.current)
    ano = VALORES.keys.select { |a| a <= data.year }.max || VALORES.keys.min
    VALORES[ano]
  end
end
```

- [ ] **Step 5: Regra do honorário**

`app/services/ramon/honorario.rb` (substitui o arquivo):

```ruby
# Honorário da tese pela tabela do POP JUR-02 (linha online): percentual dos atrasados
# + N benefícios, com mínimo. Único lugar da regra — simulador (LeadSimulacoesController),
# tools simular_honorario/playbook_da_tese e dossiê. calcular devolve o mesmo Hash do endpoint.
class Ramon::Honorario
  SEM_CONFIG = 'tese do lead sem honorário configurado (% e nº de mensalidades)'.freeze
  FORA_DA_TABELA = 'tese fora da tabela de honorários do escritório (POP JUR-02) — não cite valor; ' \
                   'o advogado explica o honorário na conversa'.freeze

  def self.calcular(tese, atrasados:, mensal:)
    return { valor: nil, motivo: FORA_DA_TABELA } if tese && !tese.honorario_na_tabela
    return { valor: nil, motivo: SEM_CONFIG } unless configurada?(tese)

    mensal = BigDecimal(mensal.to_s)
    sm = Ramon::SalarioMinimo.vigente
    percentual = tese.honorario_percentual || 0
    n = tese.honorario_n_mensalidades || 0
    # JUR-02: o "3" é sempre 3 benefícios ou 3 salários mínimos, o que for maior.
    formula = (BigDecimal(atrasados.to_s) * percentual / 100) + ([mensal, sm].max * n)
    valor = [formula, minimo(tese, mensal, sm)].max
    { valor: format('%.2f', valor), percentual: percentual.to_f, n_mensalidades: n, tese: tese.name,
      descricao: descricao(tese) }
  end

  def self.descricao(tese)
    return nil if tese.nil?
    return FORA_DA_TABELA unless tese.honorario_na_tabela
    return nil unless configurada?(tese)

    texto = "#{numero(tese.honorario_percentual || 0)}% dos atrasados"
    n = tese.honorario_n_mensalidades.to_i
    texto += " + #{n} #{n == 1 ? 'benefício' : 'benefícios'}" if n.positive?
    q = tese.honorario_minimo_qtd.to_i
    texto += ", mínimo #{q} #{unidade(tese.honorario_minimo_base, q)}" if q.positive?
    texto
  end

  def self.configurada?(tese)
    tese && (tese.honorario_percentual.present? || tese.honorario_n_mensalidades.present?)
  end

  def self.minimo(tese, mensal, sm)
    q = tese.honorario_minimo_qtd.to_i
    q * (tese.honorario_minimo_base == 'sm' ? sm : mensal)
  end

  def self.numero(pct)
    (pct % 1).zero? ? pct.to_i.to_s : pct.to_f.to_s.tr('.', ',')
  end

  def self.unidade(base, qtd)
    return (qtd == 1 ? 'salário mínimo' : 'salários mínimos') if base == 'sm'

    qtd == 1 ? 'benefício' : 'benefícios'
  end
  private_class_method :configurada?, :minimo, :numero, :unidade
end
```

- [ ] **Step 6: Lint + commit**

```bash
rubocop-vps app/services/ramon/honorario.rb app/services/ramon/salario_minimo.rb app/models/thesis.rb \
  db/migrate/20261013100001_add_jur02_to_theses.rb spec/services/ramon/honorario_spec.rb spec/models/thesis_spec.rb
git add db/migrate/20261013100001_add_jur02_to_theses.rb db/schema.rb app/services/ramon/salario_minimo.rb \
  app/services/ramon/honorario.rb app/models/thesis.rb spec/services/ramon/honorario_spec.rb spec/models/thesis_spec.rb
git commit -m "feat(honorario): regra pela tabela do POP JUR-02 (mínimo, salário mínimo, fora da tabela)"
```

(Os specs Ruby rodam no CI — Task 5. Se `rubocop-vps -a` corrigir algo, re-adicionar.)

---

### Task 2: Consumidores no backend (tools, dossiê, simulador, API, seed de contas novas)

**Files:**
- Modify: `enterprise/lib/captain/tools/simular_honorario_tool.rb` (`description`, `texto`)
- Modify: `enterprise/lib/captain/tools/playbook_da_tese_tool.rb` (`cabecalho`, apagar `honorario`)
- Modify: `app/services/ramon/dossie_service.rb` (`honorario_text`)
- Modify: `app/controllers/api/v1/accounts/theses_controller.rb` (`create`, `permitted_params`)
- Modify: `app/views/api/v1/accounts/theses/show.json.jbuilder`
- Modify: `app/services/leads/seed_default_config_service.rb` (`seed_theses`)
- Modify: `db/seeds/ramon/theses_seed.yml` (5 teses)
- Modify specs: `spec/enterprise/lib/captain/tools/simular_honorario_tool_spec.rb`, `spec/enterprise/lib/captain/tools/playbook_da_tese_tool_spec.rb`, `spec/services/ramon/dossie_service_spec.rb`, `spec/controllers/api/v1/accounts/lead_simulacoes_controller_spec.rb`, `spec/requests/api/v1/accounts/theses_controller_spec.rb`

**Interfaces:**
- Consumes: `Ramon::Honorario.calcular`, `.descricao`, `::FORA_DA_TABELA` (Task 1)
- Produces: JSON da tese (`show`) com `honorario_minimo_qtd`, `honorario_minimo_base`, `honorario_na_tabela`; payload do simulador com `honorario.descricao` (usado na Task 3)

- [ ] **Step 1: Ajustar os specs existentes (vão falhar até o Step 2)**

`simular_honorario_tool_spec.rb` — trocar o `let(:thesis)` e os dois primeiros exemplos; acrescentar o de fora da tabela:

```ruby
  let(:thesis) do
    create(:thesis, account: account, name: 'Auxílio', honorario_percentual: 30, honorario_n_mensalidades: 3,
                    honorario_na_tabela: true)
  end

  describe '#perform' do
    it 'estima o honorario pela formula da tese e avisa que e estimativa' do
      lead = create(:lead, account: account, thesis: thesis)

      texto = tool.perform(tool_context, lead_id: lead.id.to_s, mensal: '2000', atrasados: '10000')

      expect(texto).to include('Honorario estimado (tese Auxílio): R$ 9000.00', '30% dos atrasados + 3 benefícios',
                               'R$ 10000.00', 'R$ 2000.00', 'estimativa')
    end

    it 'aceita numero com virgula' do
      lead = create(:lead, account: account, thesis: thesis)

      expect(tool.perform(tool_context, lead_id: lead.id.to_s, mensal: '2000,50', atrasados: '0')).to include('R$ 6001.50')
    end

    it 'tese fora da tabela: nao cita valor' do
      lead = create(:lead, account: account, thesis: create(:thesis, account: account, honorario_percentual: 30))

      texto = tool.perform(tool_context, lead_id: lead.id.to_s, mensal: 1, atrasados: 1)

      expect(texto).to include('Nao da para simular', 'fora da tabela')
    end
```

(Os exemplos "sem honorario configurado", "sem tese" e "sem caso" ficam. No "sem honorario configurado", trocar a tese para `create(:thesis, account: account, honorario_na_tabela: true)`.)

`playbook_da_tese_tool_spec.rb` — no `let(:thesis)` acrescentar `honorario_na_tabela: true`; na expectativa trocar `'Honorario: 30.0% dos atrasados + 3 mensalidades'` por `'Honorario: 30% dos atrasados + 3 benefícios'`; no exemplo `'diz honorario nao configurado'` trocar a tese para `create(:thesis, account: account, name: 'BPC', honorario_na_tabela: true)`; acrescentar:

```ruby
    it 'tese fora da tabela manda nao citar valor' do
      create(:thesis, account: account, name: 'Maternidade')

      expect(tool.perform(tool_context, tese: 'Maternidade')).to include('Honorario: tese fora da tabela', 'não cite valor')
    end
```

`dossie_service_spec.rb` — nas duas teses acrescentar `honorario_na_tabela: true`; trocar `'30% dos atrasados + 3 mensalidades'` por `'30% dos atrasados + 3 benefícios'`.

`lead_simulacoes_controller_spec.rb` — `let(:thesis)` com `honorario_na_tabela: true` (a conta 30% × 17000 + 3 × 1700 = 10200 não muda: 1700 > 1621). Acrescentar no `describe` do simulador, perto de "flags when the lead thesis has no honorario config":

```ruby
    it 'tese fora da tabela devolve o motivo sem valor' do
      lead.update!(thesis: create(:thesis, account: account, name: 'Fora', honorario_percentual: 30))
      with_modified_env MOTOR_CALCULOS_URL: motor_url do
        simulate
      end
      expect(response.parsed_body['honorario']).to eq('valor' => nil, 'motivo' => Ramon::Honorario::FORA_DA_TABELA)
    end
```

e no exemplo "applies the honorario formula" acrescentar `'descricao' => '30% dos atrasados + 3 benefícios'` ao `include`.

`theses_controller_spec.rb` — trocar o exemplo `'nasce com o honorário padrão do escritório (30% + 3)'` por:

```ruby
    it 'nasce sem honorário e fora da tabela (JUR-02: alinhar com o Dr. Ramon)', :aggregate_failures do
      post "/api/v1/accounts/#{account.id}/theses",
           params: { name: 'Tese Padrão' }, headers: admin.create_new_auth_token
      body = response.parsed_body
      expect(body['honorario_percentual']).to be_nil
      expect(body['honorario_n_mensalidades']).to be_nil
      expect(body['honorario_na_tabela']).to be false
    end
```

e acrescentar no `describe` de update (ou criar `describe 'PATCH update'` se não houver — usar o mesmo padrão de headers do arquivo):

```ruby
    it 'grava mínimo e tabela; mínimo vazio vira nil', :aggregate_failures do
      thesis = account.theses.create!(name: 'Tese Min', position: 60)
      patch "/api/v1/accounts/#{account.id}/theses/#{thesis.id}",
            params: { honorario_minimo_qtd: '3', honorario_minimo_base: 'sm', honorario_na_tabela: true },
            headers: admin.create_new_auth_token
      expect(response.parsed_body).to include('honorario_minimo_qtd' => 3, 'honorario_minimo_base' => 'sm',
                                              'honorario_na_tabela' => true)
      patch "/api/v1/accounts/#{account.id}/theses/#{thesis.id}",
            params: { honorario_minimo_qtd: '' }, headers: admin.create_new_auth_token
      expect(response).to have_http_status(:success)
      expect(thesis.reload.honorario_minimo_qtd).to be_nil
    end
```

O exemplo `'expõe os campos de honorário no show'` ganha `expect(body).to include('honorario_na_tabela' => false, 'honorario_minimo_qtd' => nil)`.

- [ ] **Step 2: Código**

`simular_honorario_tool.rb`:

```ruby
  description 'Estima o honorario da banca para o caso: aplica a formula da tese do lead ' \
              '(tabela do escritorio — percentual dos atrasados, beneficios e minimo) aos valores informados. ' \
              'E estimativa, nao proposta. Tese fora da tabela: nao cite valor.'
```

```ruby
  def texto(res, atrasados, mensal)
    "Honorario estimado (tese #{res[:tese]}): R$ #{res[:valor]}. " \
      "Formula: #{res[:descricao]} — sobre R$ #{format('%.2f', atrasados)} de atrasados e " \
      "R$ #{format('%.2f', mensal)} de beneficio mensal. " \
      'Aviso: estimativa a partir dos valores informados — o valor final depende do calculo do motor e do contrato.'
  end
```

`playbook_da_tese_tool.rb` — em `cabecalho`, trocar `linhas << "Honorario: #{honorario(thesis)}"` por:

```ruby
    linhas << "Honorario: #{::Ramon::Honorario.descricao(thesis) || 'nao configurado'}"
```

e apagar o método `honorario(thesis)`.

`dossie_service.rb` — trocar o comentário e o método `honorario_text` por:

```ruby
  # Texto único do honorário da tese (POP JUR-02) — o mesmo que o agente lê.
  def honorario_text
    Ramon::Honorario.descricao(@thesis)
  end
```

`theses_controller.rb`:

```ruby
  def create
    @thesis = Current.account.theses.new(permitted_params)
```

```ruby
  def permitted_params
    params.permit(:name, :description, :area, :active, :honorario_percentual, :honorario_n_mensalidades,
                  :honorario_minimo_qtd, :honorario_minimo_base, :honorario_na_tabela)
  end
```

(O `''` do mínimo vira `nil` sozinho: coluna integer com string vazia é cast para nil. Base vazia: a tela da Task 3 manda `null`, então `''` nunca chega na `inclusion`.)

`show.json.jbuilder` — depois de `honorario_n_mensalidades`:

```ruby
json.honorario_minimo_qtd @thesis.honorario_minimo_qtd
json.honorario_minimo_base @thesis.honorario_minimo_base
json.honorario_na_tabela @thesis.honorario_na_tabela
```

`seed_default_config_service.rb` — no bloco `find_or_create_by!` de `seed_theses`, depois de `t.honorario_n_mensalidades = …`:

```ruby
        t.honorario_minimo_qtd = thesis_attrs['honorario_minimo_qtd']
        t.honorario_minimo_base = thesis_attrs['honorario_minimo_base']
        t.honorario_na_tabela = thesis_attrs['honorario_na_tabela'] || false
```

`theses_seed.yml` — nas 5 teses, trocar o par `honorario_percentual/honorario_n_mensalidades` pelos valores do JUR-02 (iguais à migração):

```yaml
  # auxílio-doença (B31)
    honorario_percentual: 30
    honorario_n_mensalidades:
    honorario_minimo_qtd: 1
    honorario_minimo_base: sb
    honorario_na_tabela: true
  # invalidez (B32)
    honorario_percentual: 30
    honorario_n_mensalidades:
    honorario_minimo_qtd: 3
    honorario_minimo_base: sb
    honorario_na_tabela: true
  # Auxílio-acidente (B36)
    honorario_percentual: 30
    honorario_n_mensalidades: 3
    honorario_minimo_qtd: 3
    honorario_minimo_base: sm
    honorario_na_tabela: true
  # BPC/LOAS por deficiência e Acréscimo de 25% — fora da tabela do JUR-02
    honorario_percentual:
    honorario_n_mensalidades:
    honorario_na_tabela: false
```

(Os comentários acima só indicam qual tese; no YAML cada bloco fica dentro da sua tese, nas linhas 10–11, 78–79, 142–143, 409–410, 473–474.)

- [ ] **Step 3: Lint + commit**

```bash
rubocop-vps
git add enterprise/lib/captain/tools/simular_honorario_tool.rb enterprise/lib/captain/tools/playbook_da_tese_tool.rb \
  app/services/ramon/dossie_service.rb app/controllers/api/v1/accounts/theses_controller.rb \
  app/views/api/v1/accounts/theses/show.json.jbuilder app/services/leads/seed_default_config_service.rb \
  db/seeds/ramon/theses_seed.yml spec/enterprise/lib/captain/tools/simular_honorario_tool_spec.rb \
  spec/enterprise/lib/captain/tools/playbook_da_tese_tool_spec.rb spec/services/ramon/dossie_service_spec.rb \
  spec/controllers/api/v1/accounts/lead_simulacoes_controller_spec.rb spec/requests/api/v1/accounts/theses_controller_spec.rb
git commit -m "feat(honorario): tools, dossiê, simulador e API usam a regra do JUR-02"
```

⚠️ Specs em `spec/enterprise` **não rodam no CI FOSS** (rm -rf enterprise). A prova das duas tools é o `rails runner` da Task 5.

---

### Task 3: Tela (Playbooks + simulador)

**Files:**
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/pages/Playbooks.vue`
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/components/conversation/LeadSimulador.vue:1044-1052`
- Modify: `app/javascript/dashboard/i18n/locale/en/ramon.json`, `app/javascript/dashboard/i18n/locale/pt_BR/ramon.json`
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/pages/specs/Playbooks.spec.js`
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/components/conversation/specs/LeadSimulador.spec.js`

**Interfaces:**
- Consumes: JSON da tese com `honorario_minimo_qtd`, `honorario_minimo_base`, `honorario_na_tabela`; `honorario.descricao` no payload do simulador (Task 2)

- [ ] **Step 1: Specs JS (falham)**

`Playbooks.spec.js` — seguindo o padrão do arquivo para montar a tela com uma tese selecionada (ver o teste que usa `playbooks-honorario-percentual-input`), acrescentar:

```js
  it('salva mínimo, base e "na tabela" da tese', async () => {
    const { wrapper, store } = mountPlaybooks();
    await wrapper.findAll('[data-testid="playbooks-item"]')[0].trigger('click');
    await wrapper
      .find('[data-testid="playbooks-honorario-na-tabela"]')
      .setValue(true);
    await wrapper
      .find('[data-testid="playbooks-honorario-minimo-qtd-input"]')
      .setValue('3');
    await wrapper
      .find('[data-testid="playbooks-honorario-minimo-base"]')
      .setValue('sm');
    expect(store.dispatch).toHaveBeenLastCalledWith(
      'theses/update',
      expect.objectContaining({
        id: 1,
        honorario_minimo_qtd: '3',
        honorario_minimo_base: 'sm',
        honorario_na_tabela: true,
      })
    );
  });
```

(Se a seleção da tese no arquivo usar outro testid que não `playbooks-item`, usar o do teste `'tese com leads: oferece desativar…'`, que já seleciona uma tese antes de salvar.)

`LeadSimulador.spec.js` — no objeto `honorario` do mock (linha ~39) acrescentar `descricao: '30% dos atrasados + 3 benefícios'` e, no teste que confere `sim-honorario`, acrescentar:

```js
    expect(wrapper.find('[data-testid="sim-honorario"]').text()).toContain(
      '30% dos atrasados + 3 benefícios'
    );
```

Run: `pnpm vitest run app/javascript/dashboard/routes/dashboard/ramon/pages/specs/Playbooks.spec.js app/javascript/dashboard/routes/dashboard/ramon/components/conversation/specs/LeadSimulador.spec.js`
Expected: FAIL (testids/descrição ausentes)

- [ ] **Step 2: Playbooks.vue**

No `reactive` do `detail` (linha ~43) acrescentar `honorarioMinimoQtd: ''`, `honorarioMinimoBase: ''`, `honorarioNaTabela: false`; no carregamento (linha ~54):

```js
  detail.honorarioMinimoQtd = thesis.honorario_minimo_qtd ?? '';
  detail.honorarioMinimoBase = thesis.honorario_minimo_base ?? '';
  detail.honorarioNaTabela = !!thesis.honorario_na_tabela;
```

em `saveDetail` (linha ~141), depois de `honorario_n_mensalidades`:

```js
      honorario_minimo_qtd: detail.honorarioMinimoQtd,
      honorario_minimo_base: detail.honorarioMinimoBase || null,
      honorario_na_tabela: detail.honorarioNaTabela,
```

No template, manter a grade de 3 colunas existente (Área / percentual / mensalidades) e acrescentar **logo abaixo** dela, antes do `<p data-testid="playbooks-honorario-padrao">`:

```vue
              <div class="grid gap-3 md:grid-cols-3">
                <label :class="ROTULO">
                  {{ $t('RAMON.PLAYBOOKS.HONORARIO_MINIMO') }}
                  <input
                    v-model="detail.honorarioMinimoQtd"
                    type="number"
                    min="0"
                    step="1"
                    data-testid="playbooks-honorario-minimo-qtd-input"
                    class="font-mono"
                    :class="CAMPO"
                    @blur="saveDetail"
                  />
                </label>
                <label :class="ROTULO">
                  {{ $t('RAMON.PLAYBOOKS.HONORARIO_MINIMO_BASE') }}
                  <select
                    v-model="detail.honorarioMinimoBase"
                    data-testid="playbooks-honorario-minimo-base"
                    :class="CAMPO"
                    @change="saveDetail"
                  >
                    <option value="">—</option>
                    <option value="sm">{{ $t('RAMON.PLAYBOOKS.BASE_SM') }}</option>
                    <option value="sb">{{ $t('RAMON.PLAYBOOKS.BASE_SB') }}</option>
                  </select>
                </label>
                <label :class="ROTULO" class="flex items-center gap-2 self-end">
                  <input
                    v-model="detail.honorarioNaTabela"
                    type="checkbox"
                    data-testid="playbooks-honorario-na-tabela"
                    @change="saveDetail"
                  />
                  {{ $t('RAMON.PLAYBOOKS.HONORARIO_NA_TABELA') }}
                </label>
              </div>
```

- [ ] **Step 3: LeadSimulador.vue**

Trocar o bloco `$t('RAMON.SIMULADOR.HONORARIO_FORMULA', {...})` (linhas ~1044–1052) por:

```vue
          <span class="text-xs text-n-slate-10">
            ({{ honorario.descricao }} · {{ honorario.tese }})
          </span>
```

- [ ] **Step 4: i18n**

Em `en/ramon.json` e `pt_BR/ramon.json`:
- **apagar** `RAMON.SIMULADOR.HONORARIO_FORMULA` (sem uso);
- trocar `RAMON.PLAYBOOKS.HONORARIO_PADRAO`:
  - en: `"Fee table: POP JUR-02 (online row). Off the table: the AI never quotes a fee and hands off to a person."`
  - pt_BR: `"Tabela do POP JUR-02 (linha online). Fora da tabela: a IA não cita valor e passa para humano."`
- acrescentar em `RAMON.PLAYBOOKS`:

| chave | en | pt_BR |
|---|---|---|
| `HONORARIO_MINIMO` | `Fee: minimum (qty)` | `Honorário: mínimo (qtd)` |
| `HONORARIO_MINIMO_BASE` | `Minimum in` | `Mínimo em` |
| `BASE_SM` | `minimum wages` | `salários mínimos` |
| `BASE_SB` | `benefits` | `benefícios` |
| `HONORARIO_NA_TABELA` | `On the fee table (AI may quote it)` | `Na tabela de honorários (a IA pode citar)` |

- [ ] **Step 5: Rodar specs JS + eslint**

Run: `pnpm vitest run app/javascript/dashboard/routes/dashboard/ramon/pages/specs/Playbooks.spec.js app/javascript/dashboard/routes/dashboard/ramon/components/conversation/specs/LeadSimulador.spec.js`
Expected: PASS

Run: `pnpm eslint app/javascript/dashboard/routes/dashboard/ramon/pages/Playbooks.vue app/javascript/dashboard/routes/dashboard/ramon/components/conversation/LeadSimulador.vue`
Expected: sem erros

- [ ] **Step 6: Commit**

```bash
git add app/javascript/dashboard/routes/dashboard/ramon/pages/Playbooks.vue \
  app/javascript/dashboard/routes/dashboard/ramon/components/conversation/LeadSimulador.vue \
  app/javascript/dashboard/i18n/locale/en/ramon.json app/javascript/dashboard/i18n/locale/pt_BR/ramon.json \
  app/javascript/dashboard/routes/dashboard/ramon/pages/specs/Playbooks.spec.js \
  app/javascript/dashboard/routes/dashboard/ramon/components/conversation/specs/LeadSimulador.spec.js
git commit -m "feat(playbooks): mínimo e 'na tabela' do honorário na tela; simulador mostra a fórmula da tese"
```

---

### Task 4: Textos ao cliente (rascunho → aprovado do Eduardo)

**Files:**
- Modify: `db/seeds/ramon/inteligencia/assistentes.yml` (linhas 21, 29, 76, 95–96)
- Modify: `db/seeds/ramon/inteligencia/faq/{auxilio-acidente,auxilio-doenca,aposentadoria-invalidez,bpc-loas,acrescimo-25}.md` (pergunta "Quanto custa?")
- Create: `C:\Users\dudsl\RAdvogados\comercial\docs\2026-10-13-honorario-jur02-textos.md` (fora do repo: antes × depois para o Eduardo aprovar)

**Interfaces:** nenhuma (texto). Ativação = `rake 'ramon:inteligencia:seed[2]'` na VPS — **só depois do aprovado**.

- [ ] **Step 1: Trocar os textos no seed**

`assistentes.yml`:
- linha 21 (diretriz) →
  `- "Honorário, quando perguntarem: use o que a FAQ ou o playbook da tese informar — o honorário muda por tese. Se a tese estiver fora da tabela, não cite valor: diga que o advogado explica o honorário na conversa e passe para humano. Nunca ofereça desconto nem parcelamento: a resposta à objeção de preço é o risco zero, não o preço."`
- linha 29 (guardrail) →
  `- "Não cite valor ou fórmula de honorário diferente do que a FAQ ou o playbook da tese informam; tese fora da tabela: nenhum valor."`
- linha 76 (skill Dúvidas): `→ só paga se receber, 30% dos atrasados + 3 parcelas, sem entrada;` →
  `→ o honorário da tese (FAQ/playbook) e que só paga se receber; tese fora da tabela → o advogado explica;`
- linhas 95–96 (skill Estimar): `(30% dos atrasados + 3 parcelas), lembrando que só paga se receber.` →
  `(pela fórmula da tese que o simulador devolve), lembrando que só paga se receber. Se o simulador disser que a tese está fora da tabela, não fale de valor de honorário: o advogado explica.`

FAQs — a resposta da pergunta de custo (a linha logo abaixo de `## Quanto custa? …`) em cada arquivo:

| arquivo | resposta nova |
|---|---|
| `auxilio-acidente.md` | `Você só paga se receber. Nosso combinado é 30% do valor atrasado que vier, mais o equivalente a 3 benefícios — nunca menos que 3 salários mínimos no total —, sem entrada, sem mensalidade, sem custo escondido.` + o resto da linha atual que vem depois de "custo escondido." (manter) |
| `auxilio-doenca.md` | `Você só paga se receber. Nosso combinado é 30% do valor atrasado que vier, com mínimo de 1 benefício — sem entrada, sem mensalidade, sem custo escondido.` |
| `aposentadoria-invalidez.md` | `Você só paga se receber. Nosso combinado é 30% do valor atrasado que vier, com mínimo de 3 benefícios — sem entrada, sem mensalidade, sem custo escondido.` (manter o resto da linha, se houver) |
| `bpc-loas.md` | `O honorário desse tipo de caso o advogado explica na conversa, olhando a sua situação. Quer que eu já peça para ele falar com você?` |
| `acrescimo-25.md` | `O honorário desse tipo de caso o advogado explica na conversa, olhando a sua situação. Quer que eu já peça para ele falar com você?` |

⚠️ A FAQ é chaveada pela **pergunta** (`upsert_faq` por `question`): não mudar o título `## …`, só a resposta. FAQ editada na tela (`edited: true`) não é sobrescrita pelo seed — a Task 5 confere.

- [ ] **Step 2: Documento de aprovação**

Criar `comercial\docs\2026-10-13-honorario-jur02-textos.md` com uma tabela **antes × depois** de cada texto acima (copiar o "antes" do arquivo atual), a nota "rascunho — só entra no ar com o seu aprovado" e duas perguntas:
1. Auxílio-acidente: o "3" do JUR-02 foi implementado como **3 × o maior entre o benefício mensal e o salário mínimo**. É isso, ou é 3 × o salário de benefício (base do cálculo, que é o dobro do auxílio-acidente)?
2. BPC e acréscimo: a frase "o advogado explica" serve, ou prefere outra?

- [ ] **Step 3: Commit (só o repo)**

```bash
git add db/seeds/ramon/inteligencia/assistentes.yml db/seeds/ramon/inteligencia/faq/
git commit -m "feat(inteligencia): diretriz, guardrail, skills e FAQs de honorário pelo POP JUR-02"
```

---

### Task 5: PR, CI, merge, deploy, provas e smoke

**Files:**
- Create: `C:\Users\dudsl\RAdvogados\comercial\docs\2026-10-13-smoke-f0-honorario.md`

- [ ] **Step 1: Push e PR** (push = Eduardo via `!` se o classificador barrar)

```bash
git push -u origin docs/roteiro-da-tese
gh pr create --base ramon --title "feat(honorario): honorário pela tabela do POP JUR-02 (F0 do roteiro da tese)" --body-file <corpo>
```

Corpo: parágrafo de produto; "Como testar" (Playbooks: mínimo/na tabela; simulador numa tese fora da tabela); o aviso de que os textos ao cliente só são ativados com o seed após aprovado; rodapé de atribuição.

- [ ] **Step 2: CI 100% verde** — se o CI pegar lint/spec, corrigir, `rubocop-vps`, novo commit (não amend). 429/503 baixando actions = re-rodar o job.

- [ ] **Step 3: Merge (squash) e deploy** — regime de merge/deploy autônomo com CI verde (CLAUDE.md do ramon-hub). Deploy como os anteriores: `docker pull` da imagem `sha-<7>` + tag + `compose run --rm --no-deps chatwoot-web bundle exec rails db:migrate` + `up -d chatwoot-web chatwoot-worker`. Conferir a label da imagem e o login 200 em https://chat.ramonantonio.adv.br.

- [ ] **Step 4: Provas em produção (só leitura)** via `rails runner`:

```ruby
a = Account.find(2)
a.theses.map { |t| [t.name, t.honorario_na_tabela, Ramon::Honorario.descricao(t)] }
# esperado: aux-acidente/doença/invalidez na tabela com a descrição do JUR-02; BPC e acréscimo fora
t = a.theses.find_by(name: 'Auxílio-acidente (B36)')
Ramon::Honorario.calcular(t, atrasados: 10_000, mensal: 800)[:valor] # => "7863.00"
asst = Captain::Assistant.find_by(account: a, name: 'Atendimento')
Captain::Tools::PlaybookDaTeseTool.new(asst).perform(Struct.new(:state).new({}), tese: 'BPC')
# => contém "Honorario: tese fora da tabela"
Captain::Assistant.find_by(account: a, name: 'Atendimento').responses.where(edited: true).where("answer ILIKE '%30%'").pluck(:question)
# FAQs editadas na tela com "30%" — listar no smoke (o seed não as sobrescreve)
```

- [ ] **Step 5: Smoke doc** `comercial\docs\2026-10-13-smoke-f0-honorario.md` (bloco inteiro por seção, nunca passo a passo em formulário): (A) Playbooks — abrir cada tese e conferir mínimo/na tabela; criar tese de teste e ver que nasce fora da tabela; apagar. (B) Simulador no painel de um lead de auxílio-acidente e de um de BPC. (C) **Só depois do aprovado dos textos:** rodar `rake 'ramon:inteligencia:seed[2]'` e perguntar "quanto custa?" no Testar para auxílio-acidente, auxílio-doença e BPC.

- [ ] **Step 6: Registrar** na memória `roteiro-da-tese.md` (PR, squash, VPS, migração aplicada, seed pendente do aprovado).
