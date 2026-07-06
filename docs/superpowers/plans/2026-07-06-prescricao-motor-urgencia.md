# Prescrição como Motor de Urgência — Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Campo `dcb_em` (data de cessação do benefício) + `benefit_monthly_value` no Lead, com cálculo de parcelas prescrevendo (quinquenal, Art. 103 §único, Lei 8.213/91) exibido no card do Kanban, injetado no prompt do Kit do Closer e ordenando a fila de retomada do Centro de Comando.

**Architecture:** Duas colunas novas em `leads` (sem backfill). A matemática da prescrição vive em `Lead#prescription` (backend, usada pelo Kit) e em `ramon/helpers/prescription.js` (frontend, usada por card/fila) — duplicação deliberada de ~10 linhas de aritmética de datas para evitar recomputar no servidor a cada render. Nenhuma tela nova: a "fila de retomada" é a `followUpQueue` existente do CommandCenter, que só ganha ordenação.

**Tech Stack:** Rails 7.1 (fork Chatwoot v4.15), Vue 3 `<script setup>`, Vuex, RSpec, Vitest.

## Global Constraints

- Regra do repo: só `en.json`/`en.yml` de i18n são editados manualmente.
- Eventos custom Vue SEMPRE camelCase (kebab não passa eslint).
- Action Vuex nunca destrutura `state` cru (no-shadow) — usar `state: moduleState` se precisar.
- Rubocop: `ENV.fetch`, não `ENV[]`. RSpec: máx 7 expectations por exemplo.
- `Lead` tem `default_scope order(:lead_stage_id, :position, :id)` — em spec, `.last` NÃO é o mais recente; `DISTINCT`+pluck exige `reorder(nil)`.
- `create(:account)` seeda o funil (Novo…Fechado/Perdido) — spec nunca cria etapa com nome seedado.
- Título do PR = Conventional Commits (check "Validate PR title"); ex.: `feat: prescricao como motor de urgencia`.
- `db/schema.rb` NUNCA editado à mão — regenerado via scratch DB na VPS (Task 5, orquestrador).
- Sem teste local completo: vitest local precisa `npx pnpm@10.2.0 install`; erros eslint `Delete ␍` em arquivos não tocados = CRLF, ignorar; CI é o juiz final.
- Verificação de CI: `gh pr view N --json statusCheckRollup` filtrando conclusion != SUCCESS — nunca lista truncada.

---

### Task 1: Backend — migração, `Lead#prescription`, serialização e params

**Files:**
- Create: `db/migrate/20260706000001_add_prescription_fields_to_leads.rb`
- Modify: `app/models/lead.rb` (helper + broadcast; `cadence_event_data` está ~linhas 71-81)
- Modify: `app/controllers/api/v1/accounts/leads_controller.rb` (`permitted_params`, ~linhas 118-121)
- Modify: `app/views/api/v1/accounts/leads/_lead.json.jbuilder` (junto de `won_at`/`lost_at`, ~linhas 15-17)
- Modify: `app/views/api/v1/accounts/ramon_dashboard/_lead.json.jbuilder`
- Test: `spec/models/lead_spec.rb` (adicionar bloco), `spec/controllers/api/v1/accounts/leads_controller_spec.rb` (ou request spec existente de leads — adicionar caso)

**Interfaces:**
- Produces: colunas `leads.dcb_em :date` e `leads.benefit_monthly_value :decimal(12,2)`, ambas null; `Lead#prescription` → `nil` se `dcb_em` blank, senão `{ months_since_dcb: Integer, lost_installments: Integer, lost_value: BigDecimal|nil }`; ambos os campos nos dois jbuilders e no payload de broadcast (`cadence_event_data`).

- [ ] **Step 1: Escrever a migração**

```ruby
class AddPrescriptionFieldsToLeads < ActiveRecord::Migration[7.1]
  def change
    add_column :leads, :dcb_em, :date
    add_column :leads, :benefit_monthly_value, :decimal, precision: 12, scale: 2
  end
end
```

- [ ] **Step 2: Escrever o spec do helper (falhando)**

Em `spec/models/lead_spec.rb`, dentro do describe existente de `Lead`:

```ruby
describe '#prescription' do
  let(:account) { create(:account) }
  let(:stage) { account.lead_stages.first }

  it 'returns nil without dcb_em' do
    lead = create(:lead, account: account, lead_stage: stage)
    expect(lead.prescription).to be_nil
  end

  it 'computes months and lost installments past the 60-month window' do
    lead = create(:lead, account: account, lead_stage: stage,
                  dcb_em: Date.new(2020, 1, 15), benefit_monthly_value: 800)
    travel_to Date.new(2026, 7, 6) do
      p = lead.prescription
      expect(p[:months_since_dcb]).to eq(77)
      expect(p[:lost_installments]).to eq(17)
      expect(p[:lost_value]).to eq(BigDecimal('13600'))
    end
  end

  it 'reports zero lost inside the window and nil value without monthly' do
    lead = create(:lead, account: account, lead_stage: stage, dcb_em: 2.years.ago.to_date)
    p = lead.prescription
    expect(p[:lost_installments]).to eq(0)
    expect(p[:lost_value]).to be_nil
  end
end
```

Nota: 15/01/2020 → 06/07/2026 = 78 meses de calendário, menos 1 porque o dia 6 < dia 15 → 77; 77−60 = 17 parcelas.

- [ ] **Step 3: Rodar e ver falhar** — `bundle exec rspec spec/models/lead_spec.rb` (na CI se não houver Ruby local; localmente esperar `undefined column`/`undefined method`).

- [ ] **Step 4: Implementar `Lead#prescription`**

Em `app/models/lead.rb`:

```ruby
PRESCRIPTION_WINDOW_MONTHS = 60

def prescription
  return nil if dcb_em.blank?

  today = Time.zone.today
  months = ((today.year - dcb_em.year) * 12) + (today.month - dcb_em.month)
  months -= 1 if today.day < dcb_em.day
  months = 0 if months.negative?
  lost = [months - PRESCRIPTION_WINDOW_MONTHS, 0].max
  {
    months_since_dcb: months,
    lost_installments: lost,
    lost_value: benefit_monthly_value.present? ? benefit_monthly_value * lost : nil
  }
end
```

- [ ] **Step 5: Serialização + params + broadcast**

1. `_lead.json.jbuilder` (accounts/leads), junto dos outros campos de data:
```ruby
json.dcb_em lead.dcb_em
json.benefit_monthly_value lead.benefit_monthly_value
```
2. Mesmo par no `ramon_dashboard/_lead.json.jbuilder`.
3. `permitted_params` do `leads_controller.rb`: adicionar `:dcb_em, :benefit_monthly_value` ao allowlist.
4. `lead.rb`, no hash de `cadence_event_data`: adicionar `dcb_em: dcb_em, benefit_monthly_value: benefit_monthly_value` (o card recebe update em tempo real).

- [ ] **Step 6: Spec de API (caso novo no spec de controller/request existente)**

```ruby
it 'updates dcb_em and benefit_monthly_value' do
  patch "/api/v1/accounts/#{account.id}/leads/#{lead.id}",
        params: { dcb_em: '2020-01-15', benefit_monthly_value: 800 },
        headers: agent.create_new_auth_token, as: :json
  expect(response).to have_http_status(:success)
  expect(lead.reload.dcb_em).to eq(Date.new(2020, 1, 15))
end
```

Adaptar ao formato do spec existente (se for controller spec, usar o estilo dos vizinhos).

- [ ] **Step 7: Commit** — `git add db/migrate app/models/lead.rb app/controllers/api/v1/accounts/leads_controller.rb app/views/api/v1/accounts spec && git commit -m "feat(ramon): campos dcb_em e benefit_monthly_value com calculo de prescricao"`

---

### Task 2: Kit do Closer — bloco de prescrição no prompt

**Files:**
- Modify: `app/services/leads/kit_service.rb` (`user_prompt`, ~linhas 44-54)
- Test: `spec/services/leads/kit_service_spec.rb` (adicionar exemplo)

**Interfaces:**
- Consumes: `Lead#prescription` da Task 1.
- Produces: linhas extras no user prompt quando `dcb_em` presente (nenhuma mudança no SYSTEM_PROMPT/schema de saída).

- [ ] **Step 1: Spec (falhando)** — no spec existente do KitService, exemplo novo:

```ruby
it 'includes prescription block when dcb_em is set' do
  lead.update!(dcb_em: Date.new(2020, 1, 15), benefit_monthly_value: 800)
  travel_to Date.new(2026, 7, 6) do
    prompt = service.send(:user_prompt)
    expect(prompt).to include('Prescricao (Art. 103')
    expect(prompt).to include('17 parcelas ja prescritas')
  end
end
```

Adaptar `lead`/`service` aos `let` existentes do spec.

- [ ] **Step 2: Implementar** — em `user_prompt`, depois da linha de viabilidade, adicionar ao array (antes do `Pseudonymizer.mask`, que já cobre o texto todo):

```ruby
if @lead.dcb_em.present? && (presc = @lead.prescription)
  monthly = @lead.benefit_monthly_value
  parts << "Prescricao (Art. 103 par. unico, Lei 8.213/91): DCB em #{I18n.l(@lead.dcb_em)}, " \
           "#{presc[:months_since_dcb]} meses atras. #{presc[:lost_installments]} parcelas ja prescritas" \
           "#{presc[:lost_value] ? " (~R$ #{presc[:lost_value].to_i})" : ''}." \
           "#{monthly.present? && presc[:lost_installments].positive? ? " A cada mes sem acao, mais R$ #{monthly.to_i} prescrevem." : ''}"
end
```

Ajustar `parts` ao nome real do array no método. Instrução ao LLM já existente no SYSTEM_PROMPT cobre o tom; a IA transforma o número em argumento leigo OAB-safe.

- [ ] **Step 3: Rodar spec, ver passar (CI se sem Ruby local).**

- [ ] **Step 4: Commit** — `git commit -m "feat(ramon): kit do closer recebe bloco de prescricao no prompt"`

---

### Task 3: Frontend — helper `prescription.js` + campos na gaveta

**Files:**
- Create: `app/javascript/dashboard/routes/dashboard/ramon/helpers/prescription.js`
- Create: `app/javascript/dashboard/routes/dashboard/ramon/helpers/specs/prescription.spec.js` (seguir pasta/padrão dos specs de `currency.js`; se os specs vivem noutro path, seguir o vizinho)
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/components/lead/LeadFields.vue` (padrão do campo `value`, linhas ~35/50/114-125)
- Modify: `app/javascript/dashboard/i18n/locale/en/ramon.json`

**Interfaces:**
- Consumes: `lead.dcb_em` (string ISO `YYYY-MM-DD`) e `lead.benefit_monthly_value` do serializer (Task 1); `formatBrl`/`parseBrlInput` de `../helpers/currency.js`; action `leads/update`.
- Produces: `prescriptionInfo(lead, now = new Date())` → `null` ou `{ monthsSinceDcb, lostInstallments, monthlyValue, lostValue, monthsToCliff }` — consumido pela Task 4.

- [ ] **Step 1: Spec do helper (falhando)**

```js
import { prescriptionInfo } from '../prescription';

describe('prescriptionInfo', () => {
  const now = new Date(2026, 6, 6); // 06/07/2026

  it('returns null without dcb_em', () => {
    expect(prescriptionInfo({}, now)).toBeNull();
  });

  it('computes lost installments past 60 months', () => {
    const info = prescriptionInfo(
      { dcb_em: '2020-01-15', benefit_monthly_value: '800.0' },
      now
    );
    expect(info.monthsSinceDcb).toBe(77);
    expect(info.lostInstallments).toBe(17);
    expect(info.lostValue).toBe(13600);
    expect(info.monthsToCliff).toBe(0);
  });

  it('reports months to cliff inside the window', () => {
    const info = prescriptionInfo({ dcb_em: '2022-01-06' }, now);
    expect(info.lostInstallments).toBe(0);
    expect(info.monthsToCliff).toBe(6);
    expect(info.lostValue).toBeNull();
  });
});
```

- [ ] **Step 2: Implementar o helper**

```js
export const PRESCRIPTION_WINDOW_MONTHS = 60;

export function prescriptionInfo(lead, now = new Date()) {
  if (!lead?.dcb_em) return null;
  const dcb = new Date(`${lead.dcb_em}T00:00:00`);
  let months =
    (now.getFullYear() - dcb.getFullYear()) * 12 +
    (now.getMonth() - dcb.getMonth());
  if (now.getDate() < dcb.getDate()) months -= 1;
  if (months < 0) months = 0;
  const lost = Math.max(months - PRESCRIPTION_WINDOW_MONTHS, 0);
  const monthly = Number(lead.benefit_monthly_value) || null;
  return {
    monthsSinceDcb: months,
    lostInstallments: lost,
    monthlyValue: monthly,
    lostValue: monthly ? monthly * lost : null,
    monthsToCliff: Math.max(PRESCRIPTION_WINDOW_MONTHS - months, 0),
  };
}
```

- [ ] **Step 3: Rodar** — `npx vitest run <path do spec>` (após `npx pnpm@10.2.0 install` se necessário). Esperado: PASS.

- [ ] **Step 4: Campos na gaveta (LeadFields.vue)**

Seguir exatamente o esqueleto do campo `value`: ref local, sync no `watch(props.lead)`, save no blur/change via `save({ ... })` → `leads/update`.

- `dcb_em`: `<input type="date" v-model="dcbEm" @change="saveDcbEm" ... />` (input nativo; classes iguais aos inputs vizinhos). `saveDcbEm()` → `save({ dcb_em: dcbEm.value || null })`.
- `benefit_monthly_value`: input texto com máscara BRL, espelhando o de `value` (`formatBrl` no watch, `parseBrlInput` no save). Atenção à lição do PR #29: não apagar valor salvo quando o input está intocado — copiar o guard do campo `value`.

Labels via i18n novo em `ramon.json`, dentro de `RAMON.DRAWER` (seguir o agrupamento existente):

```json
"DCB_LABEL": "DCB (cessação do benefício)",
"BENEFIT_MONTHLY_LABEL": "Benefício mensal estimado"
```

(As strings do produto são PT-BR dentro do en.json — padrão do fork; conferir os vizinhos e manter.)

- [ ] **Step 5: Commit** — `git commit -m "feat(ramon): campos de prescricao na gaveta do lead + helper prescriptionInfo"`

---

### Task 4: Frontend — badge no card + fila ordenada por dinheiro prescrevendo

**Files:**
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/components/kanban/LeadCard.vue` (bloco de chips, linhas ~125-147)
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/pages/CommandCenter.vue` (`followUpQueue`, linhas ~39-90)
- Modify: `app/javascript/dashboard/i18n/locale/en/ramon.json`

**Interfaces:**
- Consumes: `prescriptionInfo` da Task 3; campos no payload do card (Task 1: jbuilder + `cadence_event_data`) e no jbuilder do `ramon_dashboard` (Task 1).

- [ ] **Step 1: Badge no LeadCard**

Computed no `<script setup>`:

```js
import { prescriptionInfo } from '../../helpers/prescription';

const prescription = computed(() => prescriptionInfo(props.lead));
const prescriptionLabel = computed(() => {
  const p = prescription.value;
  if (!p) return null;
  if (p.lostInstallments > 0 && p.monthlyValue)
    return t('RAMON.KANBAN.CARD.PRESCRIPTION_BLEEDING', {
      value: brlCompact(p.monthlyValue),
    });
  if (p.lostInstallments > 0)
    return t('RAMON.KANBAN.CARD.PRESCRIPTION_LOST', {
      count: p.lostInstallments,
    });
  if (p.monthsToCliff <= 6)
    return t('RAMON.KANBAN.CARD.PRESCRIPTION_SOON', {
      months: p.monthsToCliff,
    });
  return null;
});
```

(`brlCompact` já existe em `helpers/currency.js` — conferir export; se o card usa outro formatador pro `value`, usar o mesmo.) Template: chip no bloco existente (~125-147), estilo do chip `stalled`, cor de alerta (vermelho quando `lostInstallments > 0`, âmbar no caso "soon"):

```html
<span v-if="prescriptionLabel" class="... (classes do chip stalled, tom vermelho/âmbar)">
  ⏳ {{ prescriptionLabel }}
</span>
```

i18n em `RAMON.KANBAN.CARD`:

```json
"PRESCRIPTION_BLEEDING": "{value}/mês evaporando",
"PRESCRIPTION_LOST": "{count} parcelas prescritas",
"PRESCRIPTION_SOON": "prescreve em {months}m"
```

- [ ] **Step 2: Ordenar a fila de retomada**

Em `CommandCenter.vue`, no final da computed `followUpQueue` (após dedup), ordenar por dinheiro prescrevendo desc, estável para o resto (mantém a ordem atual tasks-vencidas→stalled entre iguais):

```js
import { prescriptionInfo } from '../helpers/prescription';

const bleedRate = l => {
  const p = prescriptionInfo(l);
  return p && p.lostInstallments > 0 && p.monthlyValue ? p.monthlyValue : 0;
};
// sort estável do JS moderno: quem sangra mais sobe; empate preserva ordem atual
queue.sort((a, b) => bleedRate(b.lead ?? b) - bleedRate(a.lead ?? a));
```

Adaptar `a.lead ?? a` à forma real dos itens da fila (o scout indica itens com lead embutido vindos de `tasks_overdue`/`stalled` — conferir a estrutura no próprio computed e usar o acesso correto).

- [ ] **Step 3: Verificação local possível** — `npx vitest run` nos specs de ramon (os 3 spec-files com postcss pré-existente não carregam localmente — ignorar, CI cobre) + `npx prettier --write` nos arquivos tocados.

- [ ] **Step 4: Commit** — `git commit -m "feat(ramon): badge de prescricao no card e fila de retomada ordenada por dinheiro prescrevendo"`

---

### Task 5 (ORQUESTRADOR — não delegar): schema.rb, PR e CI

- [ ] **Step 1: Regenerar `db/schema.rb`** via scratch DB na VPS (procedimento comprovado da F2.1a): clone da branch em `/opt/scratch`, `docker compose run --rm --no-deps -v /opt/scratch/ramon-hub:/scratch-src -e DATABASE_URL="postgres://chatwoot:$PW@postgres:5432/ramon_schema_scratch" -w /scratch-src --entrypoint sh chatwoot-web -c "rake db:schema:load db:migrate db:schema:dump"`, scp de volta, dropdb+rm no fim. Commitar o schema.
- [ ] **Step 2: Abrir PR** com título `feat: prescricao como motor de urgencia` e `--body-file` (lição PS 5.1: aspas em here-string quebram).
- [ ] **Step 3: CI verde de verdade** — check-runs do COMMIT exato via `gh pr view N --json statusCheckRollup`, contar N/N completed + zero não-success.
- [ ] **Step 4: Gate do Eduardo** — merge + deploy (pull GHCR `sha-<7>` → tag `v4.15.1-ramon` → `up -d --no-build` em /opt/intranet-ramon) + `rails db:migrate` no container + smoke funcional (setar DCB num lead de teste → badge no card → kit menciona prescrição → fila reordena).

---

## Fora deste plano (registrar, não codar)

- **Bônus taxas inteligencia-inss na triagem:** o system prompt da triagem é registro de banco (`TriageAgent`) — é edição de conteúdo, não código. Rascunho do texto com taxas reais de concessão será proposto ao Eduardo em separado.
- Sem log de activity para os campos novos (`record_change_activities`) — adicionar depois se o Eduardo sentir falta no histórico.
