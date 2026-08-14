# Onda 3 — "Estratégia Visível" Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fechar o funil estratégico: valor estimado automático por tese (simulação exata > piso de mensalidades), previsão visível, cabeça das colunas do kanban com contagem + valor + ponderado + conversão, probability editável, e o fim do drift do BI com views SQL versionadas (`bi_*`) que os cards do Metabase passam a consultar.

**Architecture:** O valor estimado é calculado em `before_save` no próprio Lead (zero commits extras, zero loops de callback) e só escreve quando o valor está vazio ou foi escrito pelo próprio automático (flag `custom_attributes.valor_estimado.origem`); lead ganho nunca é tocado. A cabeça da coluna já soma valor e calcula ponderado — falta des-esconder o ponderado e levar a conversão (que o Cockpit já calcula) até o Kanban. Views via gem `scenic` (entram no `schema.rb`, o CI `db:schema:load` as cria, specs cobrem a semântica).

**Tech Stack:** Rails 7 (fork Chatwoot v4.15.1), Vue 3 `<script setup>`, gem nova: `scenic`. Sem tabela nova; 1 migration de views.

**Spec:** `docs/superpowers/specs/2026-08-13-funil-estrategico-design.md` (decisões 11–13) + CONTEXT.md (Valor Estimado, Previsão).

**Decisões do Eduardo (14/08, via AskUserQuestion — vinculantes):**
- Honorário **30% + 3 mensalidades replicado pra TODAS as teses** (ele confirmou vendo o aviso de que era exclusivo do auxílio-acidente; decision-log será proposto).
- Estimativa pré-simulação = **piso das mensalidades** (`honorario_n_mensalidades × benefit_monthly_value`), sem chutar atrasados; depois da simulação vale o honorário exato dela.

## Global Constraints

- UI pt-BR; strings novas em `pt_BR/ramon.json` E `en/ramon.json` (paridade estrutural). Sem string literal em template; Tailwind only; `<script setup>`.
- **Broadcast**: escalar novo no jbuilder slim TEM espelho em `lead.rb#push_event_data`; `value` é decimal — sempre `&.to_f` no broadcast (BigDecimal mata Sidekiq strict_args).
- **RSpec: SÓ estender arquivos existentes**; exceção: no máximo 1 arquivo novo nesta onda (`spec/db/bi_views_spec.rb`). Vitest novo é livre. `with_modified_env`; contexts em inglês.
- **Auto NUNCA sobrescreve humano**: valor com `origem == 'manual'` (ou sem flag e preenchido) é intocável; lead com `won_at` presente é intocável (valor de contrato).
- PATCH de `custom_attributes` faz deep_merge server-side — mandar só a chave alterada; chave nunca é removida.
- Rubocop 150 col; compact class/module; eventos Vue camelCase.
- **CI monta o banco com `db:schema:load`** (`run_foss_spec.yml:111`) — a migration de views só funciona no CI se o `schema.rb` ganhar os blocos `create_view` do scenic (ver Task 5).
- Worktree `ramon-hub-wt-onda3` com `pnpm install` REAL (lição da Onda 2 — junction quebra vitest). Front: `npx pnpm exec vitest run <spec>` / `npx pnpm exec eslint <files>` (forma scoped). SEM Ruby local — Ruby valida no CI.
- Branch única, 1 commit por task, 1 PR; merge só com CI verde.

---

### Task 1: Valor estimado automático (backend)

Concern `LeadValorEstimado` com `before_save`; regra: honorário exato da última simulação > piso `n_mensalidades × benefit_monthly_value`; flag de origem em `custom_attributes.valor_estimado`; edição manual de `value` via API marca origem manual.

**Files:**
- Create: `app/models/concerns/lead_valor_estimado.rb`
- Modify: `app/models/lead.rb` (include do concern, junto do `LeadDocs`/`LeadCadence`)
- Modify: `app/controllers/api/v1/accounts/leads_controller.rb` (~:168-176 `merged_params`: PATCH com `:value` marca origem manual)
- Test: `spec/models/lead_spec.rb` + `spec/controllers/api/v1/accounts/leads_controller_spec.rb` (estender)

**Interfaces:**
- Consumes: `thesis.honorario_percentual`/`honorario_n_mensalidades` (`thesis.rb:7-12`); `custom_attributes['ultima_simulacao']['honorario_valor']` (gravado por `LeadSimulador.vue:236-240` — conferir o tipo real: número vs string); `benefit_monthly_value` (decimal).
- Produces: `custom_attributes['valor_estimado'] = { 'origem' => 'auto'|'manual', 'base' => 'simulacao'|'mensalidades', 'em' => iso8601 }` (chaves string). `value` preenchido automaticamente quando elegível. Tasks 2 e 4 consomem `value` + a flag.

- [ ] **Step 1: Testes primeiro (estender `spec/models/lead_spec.rb`)**

```ruby
describe 'valor estimado automático' do
  let(:thesis) { create(:thesis, account: account, honorario_percentual: 30, honorario_n_mensalidades: 3) }

  it 'preenche pelo piso das mensalidades quando o benefício mensal é conhecido' do
    lead = create(:lead, account: account, thesis: thesis, benefit_monthly_value: 2000)
    expect(lead.value).to eq(6000)
    expect(lead.custom_attributes.dig('valor_estimado', 'origem')).to eq('auto')
    expect(lead.custom_attributes.dig('valor_estimado', 'base')).to eq('mensalidades')
  end

  it 'prefere o honorário exato da simulação quando existe' do
    lead = create(:lead, account: account, thesis: thesis, benefit_monthly_value: 2000,
                  custom_attributes: { 'ultima_simulacao' => { 'honorario_valor' => 9500.0 } })
    expect(lead.value).to eq(9500)
    expect(lead.custom_attributes.dig('valor_estimado', 'base')).to eq('simulacao')
  end

  it 'nao toca valor manual nem lead ganho' do
    lead = create(:lead, account: account, thesis: thesis, value: 1234,
                  custom_attributes: { 'valor_estimado' => { 'origem' => 'manual' } })
    lead.update!(benefit_monthly_value: 2000)
    expect(lead.reload.value).to eq(1234)
  end

  it 'valor preenchido sem flag (legado) e tratado como manual' do
    lead = create(:lead, account: account, thesis: thesis, value: 500)
    lead.update!(benefit_monthly_value: 2000)
    expect(lead.reload.value).to eq(500)
  end

  it 'sem honorario configurado na tese, nao estima' do
    tese_sem = create(:thesis, account: account)
    lead = create(:lead, account: account, thesis: tese_sem, benefit_monthly_value: 2000)
    expect(lead.value).to be_nil
  end
end
```

(Conferir: lead ganho — adicionar exemplo com etapa `is_won` + `value` já setado → recálculo não roda. Reusar os `let` de etapa ganha que o arquivo já tem.)

- [ ] **Step 2: Implementar o concern**

```ruby
# Valor Estimado (CONTEXT.md): honorário previsto pela regra da Tese, automático
# desde a qualificação; ajuste manual SEMPRE vence; no ganho o valor é contrato
# e o automático nunca mais toca. Roda em before_save: mesmo UPDATE, sem loop.
module LeadValorEstimado
  extend ActiveSupport::Concern

  included do
    before_save :recalcular_valor_estimado
  end

  private

  def recalcular_valor_estimado
    return if won_at.present? || valor_manual?

    estimado, base = estimativa
    return if estimado.blank? || estimado.zero?
    return if value.present? && value.to_d == estimado.to_d

    self.value = estimado
    self.custom_attributes = custom_attributes.to_h.merge(
      'valor_estimado' => { 'origem' => 'auto', 'base' => base, 'em' => Time.zone.now.iso8601 }
    )
  end

  def valor_manual?
    origem = custom_attributes&.dig('valor_estimado', 'origem')
    return origem == 'manual' if origem.present?

    value.present? # legado: valor preenchido antes da flag existir = mão humana
  end

  def estimativa
    simulado = custom_attributes&.dig('ultima_simulacao', 'honorario_valor')
    return [BigDecimal(simulado.to_s), 'simulacao'] if simulado.present? && simulado.to_f.positive?

    n = thesis&.honorario_n_mensalidades
    return [nil, nil] if n.blank? || n.zero? || benefit_monthly_value.blank?

    [benefit_monthly_value * n, 'mensalidades']
  end
end
```

(Incluir no `lead.rb` junto dos outros concerns. `BigDecimal(simulado.to_s)` — nunca float direto na coluna decimal.)

- [ ] **Step 3: Marca manual no controller**

Em `leads_controller.rb#merged_params` (ou no `update` antes do `update!`): quando `permitted_params[:value]` está presente (Eduardo digitou/prompt de ganho), deep-merge `{ 'valor_estimado' => { 'origem' => 'manual', 'em' => Time.zone.now.iso8601 } }` no custom_attributes do payload. Estender `leads_controller_spec.rb`: PATCH com `value` grava a flag manual; PATCH sem `value` não cria a flag.

- [ ] **Step 4: Rubocop por leitura (150 col) — CI valida. Commit:**

```bash
git add -A && git commit -m "feat(ramon): valor estimado automatico por tese (simulacao > piso de mensalidades)"
```

---

### Task 2: Valor estimado no front (badge de origem + edição manual coerente)

**Files:**
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/components/lead/LeadFields.vue` (campo `field-value` ~:555-565 e `saveValue` ~:182-193)
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/components/lead/LeadPanelBody.vue` (chip de valor ~:314-320)
- Modify: `pt_BR/ramon.json` + `en/ramon.json`
- Test: `.../lead/specs/LeadFields.spec.js` (estender)

**Interfaces:**
- Consumes: `custom_attributes.valor_estimado` da Task 1 (`origem`/`base`).
- Produces: nada novo pro backend (o controller já marca manual quando `value` viaja no PATCH — Task 1 Step 3; o front NÃO precisa mandar a flag).

- [ ] **Step 1: Teste (estender LeadFields.spec.js)** — lead com `valor_estimado.origem === 'auto'` mostra `[data-testid="value-auto-badge"]`; com `origem 'manual'` ou sem flag, não mostra.

- [ ] **Step 2: Badge no LeadFields**, ao lado do label do campo valor:

```html
<span
  v-if="valorEstimadoAuto"
  data-testid="value-auto-badge"
  :title="$t('RAMON.DRAWER.VALUE_AUTO_TIP')"
  class="ms-1 inline-flex items-center gap-0.5 rounded bg-n-iris-9/10 px-1 text-[10px] text-n-iris-11"
>
  <span class="i-lucide-sparkles size-2.5" />{{ $t('RAMON.DRAWER.VALUE_AUTO') }}
</span>
```

```js
const valorEstimadoAuto = computed(
  () => props.lead?.custom_attributes?.valor_estimado?.origem === 'auto'
);
```

No `LeadPanelBody`, mesmo computed e o badge compacto dentro do chip de valor existente. i18n: `RAMON.DRAWER.VALUE_AUTO` = "estimado" / "estimated"; `VALUE_AUTO_TIP` = "Estimado automaticamente pela regra da tese ({base}) — editar o campo trava como manual" (usar `base` se simples; senão texto fixo sem parâmetro).

- [ ] **Step 3: `saveValue` intacto** — conferir apenas que o PATCH continua mandando `{ value }` (o backend marca manual sozinho). Se o spec existente de saveValue quebrar por causa do broadcast novo da flag, ajustar o mock.

- [ ] **Step 4: vitest + eslint scoped verdes. Commit:**

```bash
git add -A && git commit -m "feat(ramon): badge de valor estimado automatico no painel"
```

---

### Task 3: Honorário 30% + 3 em todas as teses (seed)

**Files:**
- Modify: `db/seeds/ramon/theses_seed.yml` (linhas ~:6, :72, :401, :463 — adicionar `honorario_percentual: 30` e `honorario_n_mensalidades: 3` nas 4 teses sem)
- Modify: `app/services/leads/seed_default_config_service.rb` (~:126-142 — conferir se o reconcile ATUALIZA tese existente com honorário nulo; se não, adicionar reconcile dos 2 campos quando nulos, no padrão do reconcile de cadência :87-91)
- Test: `spec/services/leads/seed_default_config_service_spec.rb` (estender — as 5 teses saem com 30/3)

**Interfaces:**
- Produces: todas as teses do seed com honorário; produção (conta 2) é atualizada NO DEPLOY via rails runner (trabalho do controller, não desta task): `Thesis.where(honorario_percentual: nil).update_all(honorario_percentual: 30, honorario_n_mensalidades: 3)`.

- [ ] **Step 1: Teste do seed (estender)** — após `perform`, `Thesis.where(honorario_percentual: nil)` vazio; tese pré-existente sem honorário ganha 30/3 no re-seed; tese com honorário CUSTOMIZADO (ex. 25/2 setado à mão) NÃO é sobrescrita.
- [ ] **Step 2: YAML + reconcile respeitando valor existente (só preenche quando ambos nulos).**
- [ ] **Step 3: Commit:** `feat(ramon): honorario 30/3 em todas as teses do seed (decisao Eduardo 14/08)`

---

### Task 4: Cabeça da coluna completa + probability editável

Ponderado visível, % conversão na coluna (dado que o Cockpit já calcula), input de probability no FunilConfig.

**Files:**
- Modify: `.../kanban/KanbanColumn.vue` (bloco :206-227; `stage-weighted` :220-226 deixa de ser sr-only; prop nova `conversionRate`)
- Modify: `.../kanban/KanbanBoard.vue` (:527-529 passa `:conversion-rate="rateFor(element.id)"`; computed `rateByStage` do store `ramonDashboard`)
- Modify: `.../pages/Funil.vue` (14 linhas — `onMounted` dispara o fetch do `ramonDashboard` se vazio, igual `CommandCenter.vue:32,343`)
- Modify: `.../pages/FunilConfig.vue` (seção cadência :251-280 — input `stage-probability`, molde exato do `stage-stalled-days` :266-273, clamp 0-100)
- Modify: `pt_BR/ramon.json` + `en/ramon.json` (`RAMON.KANBAN.COLUMN.*`, `RAMON.FUNIL_CONFIG.*`)
- Test: `.../kanban/specs/KanbanColumn.spec.js` + `.../pages/specs/FunilConfig.spec.js` (estender; fixtures ganham `probability`)

**Interfaces:**
- Consumes: `conversion` do `ramon_dashboard` (shape `{ stage_id, name, entered, advanced, rate }` — `cockpit_metrics.rb:94-106`); store `ramonDashboard` já existente com action de fetch; `stage.probability` via `leadConfig` (já chega).
- Produces: prop `conversionRate: { type: Number, default: null }` no KanbanColumn; header renderiza `N · R$ X · ~R$ Y` + `↳ Z%` quando `conversionRate != null`.

- [ ] **Step 1: Testes primeiro** — KanbanColumn.spec: fixture stage ganha `probability: 40`; asserts: `stage-weighted` VISÍVEL (sem sr-only) com `~R$` compacto; com prop `conversionRate: 35` renderiza `[data-testid="stage-conversion"]` contendo `35`; sem a prop, ausente; etapa `probability: 0` não mostra ponderado (comportamento atual preservado). FunilConfig.spec: molde dos 5 casos do `stage-stalled-days` (:47-88) replicado pro `stage-probability` (render, clamp/truncar, não salvar igual, salvar novo valor via `leadConfig/updateStage`).
- [ ] **Step 2: KanbanColumn** — remover `sr-only` do `stage-weighted` e integrá-lo ao bloco de métricas (`· ~{{ brlCompact(weightedValue) }}`, classe `text-n-iris-11/80`); adicionar:

```html
<span
  v-if="conversionRate != null"
  data-testid="stage-conversion"
  :title="$t('RAMON.KANBAN.COLUMN.CONVERSION_TIP')"
  class="text-[10px] text-n-slate-10"
>↳ {{ conversionRate }}%</span>
```

- [ ] **Step 3: KanbanBoard + Funil.vue** — computed `rateByStage` sobre `ramonDashboard/getData`.conversion (mapa `stage_id → rate`, só quando `entered > 0` — guarda igual `FunnelConversion.vue:29-32`); `Funil.vue` dispara o fetch no mount (não bloqueia render; coluna funciona sem o dado).
- [ ] **Step 4: FunilConfig input probability** — label i18n `RAMON.FUNIL_CONFIG.PROBABILITY` ("Probabilidade (%)"), hint "usada na previsão ponderada"; PATCH via `leadConfig/updateStage` (backend já permite `:probability`, `lead_stages_controller.rb:79`).
- [ ] **Step 5: i18n paridade; vitest + eslint scoped. Commit:**

```bash
git add -A && git commit -m "feat(ramon): cabeca da coluna com ponderado visivel + conversao; probability editavel"
```

---

### Task 5: Views BI versionadas (scenic)

**Files:**
- Modify: `Gemfile` (gem `scenic`; lockfile é resolvido pelo controller em container — NÃO editar Gemfile.lock à mão; reportar DONE_WITH_CONCERNS)
- Create: `db/views/bi_leads_v01.sql`, `db/views/bi_stage_transitions_v01.sql`
- Create: `db/migrate/<timestamp>_create_bi_views.rb` (`create_view :bi_leads` + `create_view :bi_stage_transitions`)
- Modify: `db/schema.rb` (adicionar os blocos `create_view ..., sql_definition: <<-SQL` no FIM do schema + bump da versão pro timestamp da migration — sem Ruby local, o dump canônico sai depois na VPS; o CI valida este hand-add)
- Test: Create `spec/db/bi_views_spec.rb` (ÚNICO arquivo de spec novo da onda)

**Interfaces:**
- Produces: view `bi_leads` (1 linha por lead de funil — a REGRA DE NEGÓCIO encapsulada: exclui `source = 'calculo-advbox'` NULL-safe, `channel` com COALESCE `'outro'`, junta tese e etapa) e `bi_stage_transitions` (histórico `stage_changed`). Task 6 escreve os cards sobre elas.

- [ ] **Step 1: SQL das views**

`db/views/bi_leads_v01.sql`:

```sql
-- Regra canônica de "lead de funil" (espelho de Lead.funil — lead.rb:27-36).
-- Mudou a regra no modelo → mude AQUI na mesma PR (decisão 13 da spec 13/08).
SELECT
  l.id,
  l.account_id,
  l.contact_id,
  l.created_at,
  l.won_at,
  l.lost_at,
  l.lost_reason,
  l.value,
  l.benefit_monthly_value,
  l.source,
  COALESCE(l.channel, 'outro') AS channel,
  l.thesis_id,
  t.name  AS thesis_name,
  s.id    AS stage_id,
  s.name  AS stage_name,
  s.probability AS stage_probability,
  s.is_won,
  s.is_lost,
  (l.custom_attributes #>> '{utm,utm_campaign}') AS utm_campaign,
  (l.custom_attributes #>> '{valor_estimado,origem}') AS valor_origem
FROM leads l
LEFT JOIN theses t ON t.id = l.thesis_id
LEFT JOIN lead_stages s ON s.id = l.lead_stage_id
WHERE l.source IS DISTINCT FROM 'calculo-advbox'
```

`db/views/bi_stage_transitions_v01.sql`:

```sql
-- Transições de etapa dos leads de funil (fonte: lead_activities stage_changed;
-- etapa por NOME — renomear etapa mantém o nome antigo no histórico).
SELECT
  la.lead_id,
  b.account_id,
  la.from_value,
  la.to_value,
  la.created_at
FROM lead_activities la
JOIN bi_leads b ON b.id = la.lead_id
WHERE la.kind = 'stage_changed'
```

(Conferir os nomes reais das colunas de `lead_activities` — `kind`/`from_value`/`to_value` — contra o schema.)

- [ ] **Step 2: Migration**

```ruby
class CreateBiViews < ActiveRecord::Migration[7.1]
  def change
    create_view :bi_leads
    create_view :bi_stage_transitions
  end
end
```

- [ ] **Step 3: schema.rb hand-add** — no fim do bloco principal (antes do `end` final), os dois `create_view "bi_leads", sql_definition: <<-SQL ... SQL` com o MESMO SQL dos arquivos (formato que o scenic dumpa; `bi_stage_transitions` DEPOIS de `bi_leads` — dependência); bump `define(version: ...)` pro timestamp novo. Comentário de 1 linha avisando que o dump canônico será regenerado na VPS.
- [ ] **Step 4: Spec novo `spec/db/bi_views_spec.rb`** — usando modelos anônimos ou `ActiveRecord::Base.connection.exec_query`: (a) lead normal aparece em `bi_leads`; lead `source: 'calculo-advbox'` NÃO; (b) `channel` nulo sai como `'outro'`; (c) transição `stage_changed` aparece em `bi_stage_transitions` e atividade de lead de cálculo não; (d) `stage_probability` reflete a etapa.
- [ ] **Step 5: Commit:** `feat(ramon): views bi_leads + bi_stage_transitions versionadas (scenic)`

---

### Task 6: Cards do Metabase sobre as views (script + SQL, NÃO executa)

**Files:**
- Create: `docs/superpowers/specs/2026-08-14-metabase-cards-sobre-views.md` (o SQL NOVO dos 13 cards do "Análise Comercial" id=3 + dos 8 do Placar id=2, todos reescritos como SELECT sobre `bi_leads`/`bi_stage_transitions`; banner topo: "APLICAR SÓ NO DEPLOY DA ONDA 3 — via script")
- Create: `scripts/metabase_bi_rewrite.py` (lê `METABASE_URL` + `METABASE_ADMIN_KEY` do ambiente — credencial NUNCA no repo; casa cards por nome via API `/api/dashboard/{id}`, substitui `dataset_query.native.query`, imprime diff e pede confirmação por card com flag `--yes` pra pular)
- Test: nenhum (script operacional; validação é a execução assistida no deploy)

**Interfaces:**
- Consumes: SQL antigo dos 13 cards em `docs/superpowers/plans/2026-07-31-bi-relatorios-metabase.md:85-206` (fonte da reescrita); views da Task 5.
- Produces: doc + script prontos; a EXECUÇÃO é gate do deploy (credencial em `conhecimento\metabase-credenciais.txt`; classificador barra chamada com credencial → Eduardo dispara com `!` ou controller roda na VPS).

- [ ] **Step 1: Reescrever os 13 SQLs** — cada card vira SELECT sobre `bi_leads` (`WHERE account_id = 2` continua no card; o filtro de calculo-advbox SOME — a view já garante). Cards 5 e 6 (tempo em etapa, transições) usam `bi_stage_transitions`. Cards 11/12/13 (SLA, reuniões, follow-ups) mantêm as tabelas nativas (conversations/lead_tasks) MAS trocam o join de leads por `bi_leads`. Card 8 usa `channel` da view (sem COALESCE no card). Anotar no doc, card a card: o que mudou e o que a view absorveu.
- [ ] **Step 2: Placar (cards 40-47)** — sem o SQL no repo: o script BAIXA o SQL atual de cada card, remove o predicado `source IS DISTINCT FROM 'calculo-advbox'` e troca `FROM leads l`/`FROM leads` por `FROM bi_leads l`/`FROM bi_leads`; imprime o diff pra conferência antes de aplicar.
- [ ] **Step 3: Script python** — stdlib only (`urllib.request`, `json`, `difflib`); header `X-API-KEY`; dry-run por default (`--apply` pra gravar).
- [ ] **Step 4: Commit:** `docs(ramon): cards do Metabase reescritos sobre as views bi_* + script de aplicacao`

---

## Self-Review (feito na escrita)

- **Cobertura:** decisão 11 → Tasks 1+2+3 (estimativa, origem, honorários); decisão 12 → Task 4 (ponderado visível + conversão + probability editável; contagem/valor já existiam); decisão 13 → Tasks 5+6 (views + cards sobre elas; pendência "revisar queries Metabase pós-13/08" morre na reescrita). Previsão global já existe (forecast_total no Cockpit/chips) — nada a criar.
- **Tipos:** `valor_estimado` chaves string; `conversionRate` Number|null; `docs`-style escalares não mudam; `value` decimal no banco, `to_f` no broadcast (já existente, intocado).
- **Placeholder scan:** todos os steps têm código/instrução concreta; pontos de conferência local marcados com "(conferir ...)".

## Deploy (controller, fora das tasks)

1. Lockfile do scenic via container na VPS (mesmo fluxo da Onda 2).
2. Merge com CI verde → imagem → VPS: `rails db:migrate` À MÃO (entrypoint não migra) → conferir views no psql → regenerar `db/schema.rb` canônico via scratch DB (RAILS_ENV=production, lição 26/07) e commitar se divergir do hand-add.
3. Runner de produção: honorários 30/3 nas teses com campos nulos (conta 2).
4. Metabase: rodar `scripts/metabase_bi_rewrite.py` (gate credencial — Eduardo `!` ou execução na VPS), conferir os 21 cards.
5. Smoke doc da Onda 3 (guardado — testa junto das 3 ondas) + memória + propor decision-log (honorário 30/3 pra todas as teses, 14/08).
