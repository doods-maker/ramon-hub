# Config de Honorário por Tese — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cada tese ganha `honorario_percentual` e `honorario_n_mensalidades` (estrutura única: `honorário = % × atrasados + N × mensalidade`), editáveis na tela Playbooks, com seed do auxílio-acidente (30% / 3).

**Architecture:** Duas colunas novas na tabela `theses` (nullable = "não configurado"), expostas no CRUD existente (`ThesesController` + jbuilder + tela Playbooks). Seed em duas frentes: contas novas via `theses_seed.yml` + `SeedDefaultConfigService`; contas existentes (produção) via backfill na própria migração.

**Tech Stack:** Rails 7.1 (fork Chatwoot v4.15.1), Vue 3 `<script setup>`, Tailwind, RSpec.

**Spec de origem:** `docs/superpowers/specs/2026-07-07-sala-de-fechamento-design.md` (seção "PRONTO PRA CODAR").

## Global Constraints

- Sem ambiente local: **PR + CI validam**. Commits/push com `--no-verify` (husky não roda em worktree Windows).
- `db/schema.rb` DEVE conter as colunas novas (CI usa `db:schema:load`). Nesta feature (add_column simples) o schema é editado **manualmente** na Task 1 — não usar scratch DB.
- Rubocop: 150 chars/linha; `ENV.fetch`; RSpec máx 7 expectations por exemplo.
- `create(:account)` já seeda funil + 5 teses do playbook — specs nunca criam tese com nome seedado; contagens partem de 5.
- i18n frontend: `en/ramon.json` E `pt_BR/ramon.json` (o par é mantido no fork).
- Valores nulos = "honorário não configurado" (válido; o Eduardo cadastra pela UI).
- Semente obrigatória: tese `Auxílio-acidente (B36)` → percentual 30, mensalidades 3.

---

### Task 1: Migração + validações do model

**Files:**
- Create: `db/migrate/20260707000001_add_honorario_to_theses.rb`
- Modify: `db/schema.rb` (tabela `theses`, ~linhas 1422-1432, e `version:` na linha 13)
- Modify: `app/models/thesis.rb`
- Test: `spec/models/thesis_spec.rb`

**Interfaces:**
- Produces: colunas `theses.honorario_percentual` (decimal 5,2, nullable) e `theses.honorario_n_mensalidades` (integer, nullable); validações `numericality` allow_nil no model. Tasks 2-4 dependem desses nomes exatos.

- [ ] **Step 1: Escrever os testes que falham (validações)**

Adicionar ao fim do bloco `RSpec.describe Thesis` em `spec/models/thesis_spec.rb`:

```ruby
  it 'aceita honorário não configurado (nil)' do
    thesis = account.theses.build(name: 'Tese Sem Honorário', honorario_percentual: nil, honorario_n_mensalidades: nil)
    expect(thesis).to be_valid
  end

  it 'rejeita percentual de honorário fora de 0..100' do
    thesis = account.theses.build(name: 'Tese Percentual Ruim', honorario_percentual: 101)
    expect(thesis).not_to be_valid
  end

  it 'rejeita número de mensalidades negativo ou fracionário' do
    negativa = account.theses.build(name: 'Tese N Negativo', honorario_n_mensalidades: -1)
    fracionada = account.theses.build(name: 'Tese N Fracionário', honorario_n_mensalidades: 1.5)
    expect(negativa).not_to be_valid
    expect(fracionada).not_to be_valid
  end
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `bundle exec rspec spec/models/thesis_spec.rb`
Expected: FAIL — `unknown attribute 'honorario_percentual'` (coluna não existe). *Sem ambiente local: pular a execução e seguir; o CI é quem valida (regra do repo).*

- [ ] **Step 3: Criar a migração**

`db/migrate/20260707000001_add_honorario_to_theses.rb`:

```ruby
class AddHonorarioToTheses < ActiveRecord::Migration[7.1]
  def up
    add_column :theses, :honorario_percentual, :decimal, precision: 5, scale: 2
    add_column :theses, :honorario_n_mensalidades, :integer

    # Semente da casa p/ contas existentes: auxílio-acidente = 30% + 3 mensalidades.
    # Contas novas recebem via theses_seed.yml (Task 3).
    execute <<~SQL.squish
      UPDATE theses SET honorario_percentual = 30, honorario_n_mensalidades = 3
      WHERE name = 'Auxílio-acidente (B36)' AND honorario_percentual IS NULL
    SQL
  end

  def down
    remove_column :theses, :honorario_percentual
    remove_column :theses, :honorario_n_mensalidades
  end
end
```

- [ ] **Step 4: Atualizar db/schema.rb manualmente**

Na linha ~13, trocar `version: 2026_07_06_160001` por `version: 2026_07_07_000001`.

Na definição de `create_table "theses"` (~linha 1422), adicionar ao FIM da lista de colunas (depois de `t.datetime "updated_at"`, antes dos índices):

```ruby
    t.decimal "honorario_percentual", precision: 5, scale: 2
    t.integer "honorario_n_mensalidades"
```

(Colunas de `add_column` entram no fim da tabela física — é onde o dump as colocaria.)

- [ ] **Step 5: Adicionar validações no model**

`app/models/thesis.rb` — adicionar após a validação de `name`:

```ruby
  validates :honorario_percentual, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }, allow_nil: true
  validates :honorario_n_mensalidades, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
```

- [ ] **Step 6: Commit**

```bash
git add db/migrate/20260707000001_add_honorario_to_theses.rb db/schema.rb app/models/thesis.rb spec/models/thesis_spec.rb
git commit --no-verify -m "feat(theses): colunas de honorario por tese (percentual + n mensalidades)"
```

---

### Task 2: API — permitir e expor os campos

**Files:**
- Modify: `app/controllers/api/v1/accounts/theses_controller.rb:50` (permitted_params)
- Modify: `app/views/api/v1/accounts/theses/show.json.jbuilder`
- Test: `spec/requests/api/v1/accounts/theses_controller_spec.rb`

**Interfaces:**
- Consumes: colunas da Task 1.
- Produces: `PATCH /api/v1/accounts/:id/theses/:id` aceita `honorario_percentual`/`honorario_n_mensalidades`; `GET show` responde com as duas chaves (decimal serializa como string no JSON — ex.: `"30.0"`). A Task 4 consome esse contrato.

- [ ] **Step 1: Escrever os testes que falham**

Adicionar em `spec/requests/api/v1/accounts/theses_controller_spec.rb`, dentro do `describe 'PATCH update'` (novo exemplo) e do `describe 'GET show'` (novo exemplo):

```ruby
    it 'atualiza o honorário da tese (admin)' do
      thesis = account.theses.create!(name: 'Tese Honorário', position: 50)
      patch "/api/v1/accounts/#{account.id}/theses/#{thesis.id}",
            params: { honorario_percentual: 30, honorario_n_mensalidades: 3 },
            headers: admin.create_new_auth_token
      expect(response).to have_http_status(:success)
      expect(thesis.reload.honorario_percentual).to eq(30)
      expect(thesis.reload.honorario_n_mensalidades).to eq(3)
    end
```

```ruby
    it 'expõe os campos de honorário no show' do
      thesis = account.theses.create!(name: 'Tese Show Honorário', position: 51,
                                      honorario_percentual: 30, honorario_n_mensalidades: 3)
      get "/api/v1/accounts/#{account.id}/theses/#{thesis.id}", headers: agent.create_new_auth_token
      body = response.parsed_body
      expect(body['honorario_percentual'].to_f).to eq(30.0)
      expect(body['honorario_n_mensalidades']).to eq(3)
    end
```

- [ ] **Step 2: Permitir os params**

`app/controllers/api/v1/accounts/theses_controller.rb`, método `permitted_params`:

```ruby
  def permitted_params
    params.permit(:name, :description, :area, :active, :honorario_percentual, :honorario_n_mensalidades)
  end
```

- [ ] **Step 3: Expor no jbuilder**

`app/views/api/v1/accounts/theses/show.json.jbuilder` — adicionar após `json.position @thesis.position`:

```ruby
json.honorario_percentual @thesis.honorario_percentual
json.honorario_n_mensalidades @thesis.honorario_n_mensalidades
```

- [ ] **Step 4: Commit**

```bash
git add app/controllers/api/v1/accounts/theses_controller.rb app/views/api/v1/accounts/theses/show.json.jbuilder spec/requests/api/v1/accounts/theses_controller_spec.rb
git commit --no-verify -m "feat(theses): API aceita e expoe honorario por tese"
```

---

### Task 3: Seed do auxílio-acidente (contas novas)

**Files:**
- Modify: `db/seeds/ramon/theses_seed.yml` (bloco `Auxílio-acidente (B36)`, ~linha 134)
- Modify: `app/services/leads/seed_default_config_service.rb:126-140` (método `seed_theses`)
- Test: `spec/services/leads/seed_default_config_service_spec.rb`

**Interfaces:**
- Consumes: colunas da Task 1.
- Produces: conta nova nasce com a tese `Auxílio-acidente (B36)` já configurada (30 / 3); demais teses ficam nil.

- [ ] **Step 1: Escrever o teste que falha**

Adicionar em `spec/services/leads/seed_default_config_service_spec.rb` (dentro do describe principal — seguir o `let`/setup já existente no arquivo):

```ruby
  it 'seeda o honorário padrão do auxílio-acidente (30% + 3 mensalidades)' do
    tese = account.theses.find_by!(name: 'Auxílio-acidente (B36)')
    expect(tese.honorario_percentual).to eq(30)
    expect(tese.honorario_n_mensalidades).to eq(3)
  end
```

(Se o arquivo instanciar o service explicitamente em vez de depender do seed do `create(:account)`, seguir o padrão local — o importante é o assert nos dois campos.)

- [ ] **Step 2: Adicionar os campos no YAML**

`db/seeds/ramon/theses_seed.yml`, no bloco da tese `Auxílio-acidente (B36)` (após `position: 3`):

```yaml
    honorario_percentual: 30
    honorario_n_mensalidades: 3
```

- [ ] **Step 3: Consumir no service**

`app/services/leads/seed_default_config_service.rb`, método `seed_theses`, dentro do bloco `find_or_create_by!`:

```ruby
      thesis = @account.theses.find_or_create_by!(name: thesis_attrs['name']) do |t|
        t.description = thesis_attrs['description']
        t.area = thesis_attrs['area']
        t.position = thesis_attrs['position']
        t.honorario_percentual = thesis_attrs['honorario_percentual']
        t.honorario_n_mensalidades = thesis_attrs['honorario_n_mensalidades']
      end
```

- [ ] **Step 4: Commit**

```bash
git add db/seeds/ramon/theses_seed.yml app/services/leads/seed_default_config_service.rb spec/services/leads/seed_default_config_service_spec.rb
git commit --no-verify -m "feat(theses): seed do honorario padrao do auxilio-acidente (30%/3)"
```

---

### Task 4: UI Playbooks + i18n

**Files:**
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/pages/Playbooks.vue` (detail reactive ~linha 28, watch ~linha 30, saveDetail ~linha 76, template ~linha 264-270)
- Modify: `app/javascript/dashboard/i18n/locale/en/ramon.json` (bloco `RAMON.PLAYBOOKS`, ~linha 301)
- Modify: `app/javascript/dashboard/i18n/locale/pt_BR/ramon.json` (bloco `RAMON.PLAYBOOKS`, ~linha 287)

**Interfaces:**
- Consumes: contrato da Task 2 (`show` traz `honorario_percentual` como string decimal ou null; `update` aceita os dois campos; string vazia vira nil no Rails).

- [ ] **Step 1: Estender o estado do detail**

Em `Playbooks.vue`:

Linha 28 — trocar:

```js
const detail = reactive({ name: '', description: '', area: '', active: true });
```

por:

```js
const detail = reactive({
  name: '',
  description: '',
  area: '',
  active: true,
  honorarioPercentual: '',
  honorarioNMensalidades: '',
});
```

No `watch` (linhas 30-40), adicionar antes do fechamento do callback:

```js
    detail.honorarioPercentual = thesis.honorario_percentual ?? '';
    detail.honorarioNMensalidades = thesis.honorario_n_mensalidades ?? '';
```

No `saveDetail` (linhas 76-84), incluir os campos no payload:

```js
const saveDetail = () => {
  if (!selectedThesis.value) return;
  store.dispatch('theses/update', {
    id: selectedThesis.value.id,
    name: detail.name,
    description: detail.description,
    area: detail.area,
    honorario_percentual: detail.honorarioPercentual,
    honorario_n_mensalidades: detail.honorarioNMensalidades,
  });
};
```

- [ ] **Step 2: Inputs no template**

Após o input de `area` (linha 270) e antes do `<label>` do active, adicionar:

```html
          <div class="flex gap-3">
            <input
              v-model="detail.honorarioPercentual"
              type="number"
              min="0"
              max="100"
              step="0.5"
              data-testid="playbooks-honorario-percentual-input"
              class="flex-1 px-3 py-2 text-sm rounded-lg bg-n-alpha-2 text-n-slate-12"
              :placeholder="$t('RAMON.PLAYBOOKS.HONORARIO_PERCENT')"
              @blur="saveDetail"
            />
            <input
              v-model="detail.honorarioNMensalidades"
              type="number"
              min="0"
              step="1"
              data-testid="playbooks-honorario-mensalidades-input"
              class="flex-1 px-3 py-2 text-sm rounded-lg bg-n-alpha-2 text-n-slate-12"
              :placeholder="$t('RAMON.PLAYBOOKS.HONORARIO_INSTALLMENTS')"
              @blur="saveDetail"
            />
          </div>
```

- [ ] **Step 3: i18n**

`en/ramon.json`, bloco `RAMON.PLAYBOOKS` (após `"AREA": "Area",`):

```json
      "HONORARIO_PERCENT": "Fee: % of past-due amount",
      "HONORARIO_INSTALLMENTS": "Fee: nº of monthly benefits",
```

`pt_BR/ramon.json`, bloco `RAMON.PLAYBOOKS` (mesma posição relativa):

```json
      "HONORARIO_PERCENT": "Honorário: % dos atrasados",
      "HONORARIO_INSTALLMENTS": "Honorário: nº de mensalidades",
```

- [ ] **Step 4: Lint local do que é possível**

Run: `npx prettier --check app/javascript/dashboard/routes/dashboard/ramon/pages/Playbooks.vue app/javascript/dashboard/i18n/locale/en/ramon.json app/javascript/dashboard/i18n/locale/pt_BR/ramon.json`
Expected: sem diffs (se houver, `npx prettier --write` nos mesmos arquivos). Ignorar erros `Delete ␍` de CRLF em arquivos NÃO tocados.

- [ ] **Step 5: Commit**

```bash
git add app/javascript/dashboard/routes/dashboard/ramon/pages/Playbooks.vue app/javascript/dashboard/i18n/locale/en/ramon.json app/javascript/dashboard/i18n/locale/pt_BR/ramon.json
git commit --no-verify -m "feat(playbooks): campos de honorario por tese na tela Playbooks"
```

---

## Verificação final (whole-branch)

- Push da branch, abrir PR com título Conventional Commits: `feat: config de honorario por tese (percentual + mensalidades)`.
- CI: verificar via `gh pr view <N> --json statusCheckRollup` — contar N/N completed + zero não-success (NUNCA lista truncada).
- Deploy (gate Eduardo): migração tem BACKFILL → `rails db:migrate` ANTES da imagem nova.
