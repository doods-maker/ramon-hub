# UX 4b — Lacunas de cadência (itens 1–3, 6–7) — Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fechar as 4 lacunas restantes dos itens 1–3/6–7 do backlog 4b do plano mestre: máscara BRL no valor, pedir valor ao marcar ganho pelo select da gaveta/painel, telefone clicável (copiar + wa.me) na gaveta/painel, e UI de configuração do `stalled_after_days` por etapa.

**Architecture:** Tudo frontend Vue 3 (`<script setup>`) — o backend já aceita e serializa todos os dados (`value`, `stage_entered_at`, `stalled_after_days`, `contact_phone`). Dois helpers puros novos (`currency.js`, `phone.js`) em `ramon/helpers/`, mudanças pontuais em `LeadFields.vue`, `WonValueModal.vue`, `LeadCard.vue` e `FunilConfig.vue`. Sem migração, sem endpoint novo.

**Tech Stack:** Vue 3 Composition API, Vuex, Tailwind (só utility classes), Vitest (`pnpm test`), i18n RAMON.* (pt_BR **e** en — convenção do fork, ver F2.1c).

## Global Constraints

- **Sem ambiente local**: quem valida é PR + CI. Rodar `pnpm test <arquivo>` e `pnpm eslint <arquivos>` localmente é possível e obrigatório antes de cada commit; `npx --yes prettier@3.3.3 --check <arquivos>` valida prettier sem node_modules completo.
- **Evento custom Vue SEMPRE camelCase** (kebab-case não passa no eslint do fork).
- **ESLint `no-use-before-define`**: declarar funções antes do primeiro uso no `<script setup>`.
- **Tailwind only** — sem CSS custom, sem scoped, sem inline style.
- **i18n**: nenhuma string crua em template; chaves novas em `pt_BR/ramon.json` **e** `en/ramon.json` (mesma estrutura).
- **Commits**: Conventional Commits `type(ramon): subject`, sem referência a Claude.
- **Vuex**: nunca desestruturar `state` cru em action (`state: moduleState` se precisar).
- Specs de componente seguem o padrão dos specs vizinhos (`shallowMount` + `createStore` com módulos namespaced + `mocks: { $t: k => k }`).

## Estrutura de arquivos

| Arquivo | Papel |
|---|---|
| `app/javascript/dashboard/routes/dashboard/ramon/helpers/currency.js` | **Criar** — `formatBrl`, `parseBrlInput` (puros) |
| `app/javascript/dashboard/routes/dashboard/ramon/helpers/phone.js` | **Criar** — `phoneDigits`, `waMeUrl` (puros) |
| `app/javascript/dashboard/routes/dashboard/ramon/helpers/specs/currency.spec.js` | **Criar** |
| `app/javascript/dashboard/routes/dashboard/ramon/components/lead/LeadFields.vue` | **Modificar** — máscara BRL, prompt de ganho, contato clicável |
| `app/javascript/dashboard/routes/dashboard/ramon/components/kanban/WonValueModal.vue` | **Modificar** — input BRL |
| `app/javascript/dashboard/routes/dashboard/ramon/components/kanban/LeadCard.vue` | **Modificar** — reusar `phone.js` (refactor sem mudança de comportamento) |
| `app/javascript/dashboard/routes/dashboard/ramon/pages/FunilConfig.vue` | **Modificar** — seção Cadência (`stalled_after_days` por etapa) |
| `app/javascript/dashboard/i18n/locale/pt_BR/ramon.json` + `en/ramon.json` | **Modificar** — chaves novas |
| Specs dos componentes acima (pastas `specs/`) | **Modificar/estender** |

---

### Task 1: Helpers puros `currency.js` e `phone.js`

**Files:**
- Create: `app/javascript/dashboard/routes/dashboard/ramon/helpers/currency.js`
- Create: `app/javascript/dashboard/routes/dashboard/ramon/helpers/phone.js`
- Test: `app/javascript/dashboard/routes/dashboard/ramon/helpers/specs/currency.spec.js`
- Test: `app/javascript/dashboard/routes/dashboard/ramon/helpers/specs/phone.spec.js`

**Interfaces:**
- Produces: `formatBrl(value: number|string|null): string` (`''` p/ vazio; senão `"R$ 1.234,56"`), `parseBrlInput(raw: string|null): number|null`, `phoneDigits(phone: string|null): string`, `waMeUrl(phone: string|null): string`.

- [ ] **Step 1: Escrever os specs (falhando)**

`specs/currency.spec.js`:

```js
import { formatBrl, parseBrlInput } from '../currency';

describe('formatBrl', () => {
  it('formats a number as BRL', () => {
    // Intl usa espaço não separável entre R$ e o número
    expect(formatBrl(1234.56)).toBe('R$ 1.234,56');
  });
  it('returns empty string for null/undefined/empty', () => {
    expect(formatBrl(null)).toBe('');
    expect(formatBrl(undefined)).toBe('');
    expect(formatBrl('')).toBe('');
  });
});

describe('parseBrlInput', () => {
  it('parses pt-BR format with thousands and comma', () => {
    expect(parseBrlInput('1.234,56')).toBe(1234.56);
    expect(parseBrlInput('R$ 1.234,56')).toBe(1234.56);
  });
  it('parses comma-only decimals', () => {
    expect(parseBrlInput('1234,5')).toBe(1234.5);
  });
  it('parses plain numbers (dot decimal, no comma)', () => {
    expect(parseBrlInput('1234.56')).toBe(1234.56);
    expect(parseBrlInput('1500')).toBe(1500);
  });
  it('returns null for empty or garbage', () => {
    expect(parseBrlInput('')).toBeNull();
    expect(parseBrlInput(null)).toBeNull();
    expect(parseBrlInput('abc')).toBeNull();
  });
});
```

`specs/phone.spec.js`:

```js
import { phoneDigits, waMeUrl } from '../phone';

describe('phone helpers', () => {
  it('strips non-digits', () => {
    expect(phoneDigits('+55 (48) 99999-0000')).toBe('5548999990000');
    expect(phoneDigits(null)).toBe('');
  });
  it('builds wa.me url', () => {
    expect(waMeUrl('+55 48 99999-0000')).toBe('https://wa.me/5548999990000');
  });
});
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `pnpm test app/javascript/dashboard/routes/dashboard/ramon/helpers/specs/currency.spec.js app/javascript/dashboard/routes/dashboard/ramon/helpers/specs/phone.spec.js`
Expected: FAIL (módulos não existem).

- [ ] **Step 3: Implementar**

`helpers/currency.js`:

```js
export const formatBrl = value => {
  if (value === null || value === undefined || value === '') return '';
  return new Intl.NumberFormat('pt-BR', {
    style: 'currency',
    currency: 'BRL',
  }).format(Number(value));
};

// pt-BR: com vírgula, pontos são milhar ("1.234,56" → 1234.56);
// sem vírgula, trata como número JS padrão ("1234.56" → 1234.56).
export const parseBrlInput = raw => {
  if (raw === null || raw === undefined) return null;
  const cleaned = String(raw).replace(/[R$\s ]/g, '');
  if (!cleaned) return null;
  const normalized = cleaned.includes(',')
    ? cleaned.replace(/\./g, '').replace(',', '.')
    : cleaned;
  const number = Number(normalized);
  return Number.isNaN(number) ? null : number;
};
```

`helpers/phone.js`:

```js
export const phoneDigits = phone => (phone || '').replace(/\D/g, '');

export const waMeUrl = phone => `https://wa.me/${phoneDigits(phone)}`;
```

- [ ] **Step 4: Rodar e ver passar**

Run: mesmo comando do Step 2. Expected: PASS.

- [ ] **Step 5: Lint + commit**

```bash
pnpm eslint app/javascript/dashboard/routes/dashboard/ramon/helpers/currency.js app/javascript/dashboard/routes/dashboard/ramon/helpers/phone.js app/javascript/dashboard/routes/dashboard/ramon/helpers/specs/currency.spec.js app/javascript/dashboard/routes/dashboard/ramon/helpers/specs/phone.spec.js
npx --yes prettier@3.3.3 --check "app/javascript/dashboard/routes/dashboard/ramon/helpers/**"
git add app/javascript/dashboard/routes/dashboard/ramon/helpers
git commit -m "feat(ramon): helpers puros de moeda BRL e telefone wa.me"
```

---

### Task 2: Máscara BRL no input de valor (LeadFields + WonValueModal)

**Files:**
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/components/lead/LeadFields.vue` (input `field-value`, ~linhas 93-98 e 306-313)
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/components/kanban/WonValueModal.vue`
- Test: `app/javascript/dashboard/routes/dashboard/ramon/components/lead/specs/LeadFields.spec.js`

**Interfaces:**
- Consumes: `formatBrl`, `parseBrlInput` de `../../helpers/currency` (Task 1).
- Produces: comportamento — input de valor é `type="text"`, exibe formatado, salva número puro.

- [ ] **Step 1: Escrever specs (falhando)** — adicionar ao `LeadFields.spec.js`:

```js
it('parses BRL input on blur and saves a plain number', async () => {
  const update = vi.fn();
  const wrapper = mountFields(update);
  const input = wrapper.find('[data-testid="field-value"]');
  await input.setValue('1.234,56');
  await input.trigger('blur');
  expect(update).toHaveBeenCalledWith(expect.anything(), {
    id: 3,
    value: 1234.56,
  });
});

it('shows the value formatted as BRL', () => {
  const wrapper = mountFields();
  const input = wrapper.find('[data-testid="field-value"]');
  expect(input.element.value).toContain('100');
  expect(input.element.value).toContain('R$');
});
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `pnpm test app/javascript/dashboard/routes/dashboard/ramon/components/lead/specs/LeadFields.spec.js`
Expected: FAIL (input é `type="number"`, valor cru).

- [ ] **Step 3: Implementar em `LeadFields.vue`**

No `<script setup>`, importar os helpers e mudar a sincronização + o save:

```js
import { formatBrl, parseBrlInput } from '../../helpers/currency';
```

No `watch` de `props.lead` (linha ~44), trocar `value.value = l?.value ?? '';` por:

```js
value.value = formatBrl(l?.value);
```

Trocar `saveValue` (linhas 93-98) por:

```js
const saveValue = () => {
  const next = parseBrlInput(value.value);
  const prev = props.lead?.value == null ? null : Number(props.lead.value);
  value.value = formatBrl(next);
  if (next === prev) return;
  save({ value: next });
};
```

No template, no input `data-testid="field-value"` (linha ~306): trocar `type="number"` e remover `step="0.01"`, deixando:

```html
<input
  v-model="value"
  data-testid="field-value"
  type="text"
  inputmode="decimal"
  class="w-full px-3 py-2 mb-3 text-sm rounded-lg bg-n-alpha-1 text-n-slate-12 border border-n-weak"
  @blur="saveValue"
/>
```

- [ ] **Step 4: Implementar em `WonValueModal.vue`**

```js
import { parseBrlInput } from '../../helpers/currency';

const save = () => emit('confirmValue', { value: parseBrlInput(value.value) });
```

No template, no input `won-value-input`: `type="text"` + `inputmode="decimal"` (remover `step="0.01"`), placeholder opcional não é necessário.

- [ ] **Step 5: Rodar specs afetados**

Run: `pnpm test app/javascript/dashboard/routes/dashboard/ramon/components/lead/specs/LeadFields.spec.js app/javascript/dashboard/routes/dashboard/ramon/components/kanban/specs/KanbanBoard.spec.js`
Expected: PASS (KanbanBoard.spec cobre o fluxo do modal; se algum teste dele fixava `Number(...)` do input, ajustar para `parseBrlInput` semântica — valor numérico igual).

- [ ] **Step 6: Lint + commit**

```bash
pnpm eslint app/javascript/dashboard/routes/dashboard/ramon/components/lead/LeadFields.vue app/javascript/dashboard/routes/dashboard/ramon/components/kanban/WonValueModal.vue app/javascript/dashboard/routes/dashboard/ramon/components/lead/specs/LeadFields.spec.js
npx --yes prettier@3.3.3 --check "app/javascript/dashboard/routes/dashboard/ramon/components/lead/**" "app/javascript/dashboard/routes/dashboard/ramon/components/kanban/WonValueModal.vue"
git add -A app/javascript/dashboard/routes/dashboard/ramon/components
git commit -m "feat(ramon): mascara BRL nos inputs de valor do lead"
```

---

### Task 3: Pedir valor ao marcar ganho pelo select de etapa (LeadFields)

**Files:**
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/components/lead/LeadFields.vue` (onStageChange linhas ~119-141 + template após o bloco `lostPrompt`)
- Test: `app/javascript/dashboard/routes/dashboard/ramon/components/lead/specs/LeadFields.spec.js`

**Interfaces:**
- Consumes: `parseBrlInput` (Task 1); i18n existente `RAMON.FUNIL.WON.{TITLE,VALUE_LABEL,SAVE,SKIP}` (já existe em pt_BR e en — não criar chave nova).
- Produces: comportamento — select p/ etapa `is_won` com lead sem `value` abre prompt inline; "Salvar" manda `lead_stage_id` + `value` num único update; "Pular" manda só a etapa.

**Contexto pro implementador:** o arquivo já tem exatamente esse padrão para etapa de perda (`lostPrompt`, linhas 36-141 e template 171-203). O trabalho é espelhá-lo para ganho, generalizando `commitStage`.

- [ ] **Step 1: Escrever specs (falhando)** — adicionar ao `LeadFields.spec.js`. Atenção: o `build()` do spec precisa ganhar a stage de ganho e o getter de motivos:

No `build()`, trocar o getter `getStages` por:

```js
getStages: () => [
  { id: 1, name: 'Novo' },
  { id: 2, name: 'Fechado', is_won: true },
],
getLostReasons: () => [],
```

Testes novos:

```js
it('prompts for value when moving to a won stage and lead has no value', async () => {
  const update = vi.fn();
  const wrapper = shallowMount(LeadFields, {
    props: { lead: { ...lead, value: null } },
    global: { plugins: [build(update)], mocks: { $t: k => k } },
  });
  await wrapper.find('[data-testid="field-stage"]').setValue(2);
  expect(update).not.toHaveBeenCalled();
  expect(wrapper.find('[data-testid="stage-won-prompt"]').exists()).toBe(true);

  await wrapper.find('[data-testid="stage-won-value"]').setValue('2.500,00');
  await wrapper.find('[data-testid="stage-won-save"]').trigger('click');
  expect(update).toHaveBeenCalledWith(expect.anything(), {
    id: 3,
    lead_stage_id: 2,
    value: 2500,
  });
});

it('skips the value and still moves the stage', async () => {
  const update = vi.fn();
  const wrapper = shallowMount(LeadFields, {
    props: { lead: { ...lead, value: null } },
    global: { plugins: [build(update)], mocks: { $t: k => k } },
  });
  await wrapper.find('[data-testid="field-stage"]').setValue(2);
  await wrapper.find('[data-testid="stage-won-skip"]').trigger('click');
  expect(update).toHaveBeenCalledWith(expect.anything(), {
    id: 3,
    lead_stage_id: 2,
  });
});

it('does not prompt when the lead already has a value', async () => {
  const update = vi.fn();
  const wrapper = mountFields(update); // lead.value = 100
  await wrapper.find('[data-testid="field-stage"]').setValue(2);
  expect(wrapper.find('[data-testid="stage-won-prompt"]').exists()).toBe(false);
  expect(update).toHaveBeenCalledWith(expect.anything(), {
    id: 3,
    lead_stage_id: 2,
  });
});
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `pnpm test app/javascript/dashboard/routes/dashboard/ramon/components/lead/specs/LeadFields.spec.js`
Expected: FAIL (`stage-won-prompt` não existe).

- [ ] **Step 3: Implementar no `<script setup>`**

Adicionar refs junto de `lostPrompt` (linha ~38):

```js
const wonPrompt = ref(false);
const wonValue = ref('');
```

No `watch` de `props.lead`, junto do reset de `lostPrompt`:

```js
wonPrompt.value = false;
wonValue.value = '';
```

Generalizar `commitStage` (linhas 104-117) — payload extra em vez de só lostReason:

```js
const commitStage = async (targetId, extra = {}) => {
  try {
    await store.dispatch('leads/update', {
      id: props.lead.id,
      lead_stage_id: targetId,
      ...extra,
    });
  } catch (e) {
    useAlert(t('RAMON.FUNIL.SAVE_ERROR'));
    stageId.value = props.lead?.lead_stage_id ?? null;
  } finally {
    lostPrompt.value = false;
    wonPrompt.value = false;
  }
};
```

Atualizar `confirmLostStage` para a nova assinatura e `onStageChange` para o gate de ganho:

```js
const onStageChange = targetId => {
  stageId.value = targetId;
  const target = stages.value.find(s => s.id === targetId);
  if (target?.is_lost && !props.lead?.lost_reason) {
    lostReasonName.value = '';
    lostPrompt.value = true;
    return;
  }
  if (target?.is_won && props.lead?.value == null) {
    wonValue.value = '';
    wonPrompt.value = true;
    return;
  }
  commitStage(targetId);
};

const confirmLostStage = () => {
  if (!lostReasonName.value) return;
  commitStage(stageId.value, { lost_reason: lostReasonName.value });
};

const confirmWonStage = () => {
  const parsed = parseBrlInput(wonValue.value);
  commitStage(stageId.value, parsed == null ? {} : { value: parsed });
};

const cancelWonStage = () => {
  wonPrompt.value = false;
  wonValue.value = '';
  stageId.value = props.lead?.lead_stage_id ?? null;
};
```

(Nota: "Pular" = `confirmWonStage` com input vazio → `parsed == null` → move sem valor. Ligar o botão skip direto em `confirmWonStage` NÃO — skip deve ignorar o que estiver digitado: `const skipWonStage = () => commitStage(stageId.value);`)

Declarar também `skipWonStage`:

```js
const skipWonStage = () => commitStage(stageId.value);
```

Atenção `no-use-before-define`: declarar tudo acima do template (ordem: `commitStage` → `onStageChange` → `confirmLostStage`/`cancelLostStage` → `confirmWonStage`/`skipWonStage`/`cancelWonStage`).

O select de etapa usa `:class="lostPrompt ? 'mb-1' : 'mb-3'"` — trocar por `:class="lostPrompt || wonPrompt ? 'mb-1' : 'mb-3'"`.

- [ ] **Step 4: Template** — logo depois do bloco `v-if="lostPrompt"` (linha ~203), adicionar:

```html
<div
  v-if="wonPrompt"
  data-testid="stage-won-prompt"
  class="flex flex-col gap-2 p-2 mb-3 rounded-lg bg-n-alpha-1 border border-n-weak"
>
  <label class="text-xs text-n-slate-10">{{
    $t('RAMON.FUNIL.WON.VALUE_LABEL')
  }}</label>
  <input
    v-model="wonValue"
    data-testid="stage-won-value"
    type="text"
    inputmode="decimal"
    class="w-full px-2 py-1.5 text-sm rounded bg-n-alpha-2 text-n-slate-12"
    @keyup.enter="confirmWonStage"
  />
  <div class="flex justify-end gap-2">
    <button
      data-testid="stage-won-skip"
      class="px-3 py-1 text-xs text-n-slate-11"
      @click="skipWonStage"
    >
      {{ $t('RAMON.FUNIL.WON.SKIP') }}
    </button>
    <button
      data-testid="stage-won-save"
      class="px-3 py-1 text-xs rounded-lg bg-n-iris-9 text-white"
      @click="confirmWonStage"
    >
      {{ $t('RAMON.FUNIL.WON.SAVE') }}
    </button>
  </div>
</div>
```

- [ ] **Step 5: Rodar e ver passar**

Run: `pnpm test app/javascript/dashboard/routes/dashboard/ramon/components/lead/specs/LeadFields.spec.js`
Expected: PASS (todos, inclusive os antigos — o teste "saves the stage on change" usa stage id=1 sem is_won, segue passando).

- [ ] **Step 6: Lint + commit**

```bash
pnpm eslint app/javascript/dashboard/routes/dashboard/ramon/components/lead/LeadFields.vue app/javascript/dashboard/routes/dashboard/ramon/components/lead/specs/LeadFields.spec.js
npx --yes prettier@3.3.3 --check "app/javascript/dashboard/routes/dashboard/ramon/components/lead/**"
git add -A app/javascript/dashboard/routes/dashboard/ramon/components/lead
git commit -m "feat(ramon): pedir valor ao marcar ganho pelo select de etapa"
```

---

### Task 4: Telefone clicável (copiar + wa.me) na gaveta e no painel

**Files:**
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/components/lead/LeadFields.vue` (bloco "Só leitura: contato", linhas ~383-397)
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/components/kanban/LeadCard.vue` (refactor: usar `phone.js`)
- Test: `app/javascript/dashboard/routes/dashboard/ramon/components/lead/specs/LeadFields.spec.js`

**Interfaces:**
- Consumes: `waMeUrl` de `../../helpers/phone` (Task 1); `copyTextToClipboard` de `shared/helpers/clipboard`; i18n existente `RAMON.KANBAN.CARD.{COPY_PHONE,PHONE_COPIED,WHATSAPP}` (reusar — não criar chave nova).
- Produces: no bloco de contato, telefone vira botão de copiar + link wa.me quando o lead **não** tem conversa vinculada (com conversa, o caminho é o dock/própria conversa — já coberto).

**Contexto:** `LeadFields` é renderizado tanto na gaveta (`LeadDrawer.vue` linha 42) quanto no painel da conversa (`LeadConversationPanel.vue` linha 97) — mexer aqui cobre os dois lugares do item 7.

- [ ] **Step 1: Escrever specs (falhando)** — adicionar ao `LeadFields.spec.js`:

```js
it('copies the contact phone', async () => {
  const wrapper = mountFields();
  expect(wrapper.find('[data-testid="contact-copy-phone"]').exists()).toBe(
    true
  );
});

it('shows wa.me link only when the lead has no conversation', () => {
  const withConv = shallowMount(LeadFields, {
    props: { lead: { ...lead, conversation_id: 77 } },
    global: { plugins: [build()], mocks: { $t: k => k } },
  });
  expect(withConv.find('[data-testid="contact-wa-me"]').exists()).toBe(false);

  const withoutConv = mountFields();
  const link = withoutConv.find('[data-testid="contact-wa-me"]');
  expect(link.exists()).toBe(true);
  expect(link.attributes('href')).toBe('https://wa.me/55');
});
```

(`lead.contact_phone` no fixture é `'+55'` → dígitos `55`.)

- [ ] **Step 2: Rodar e ver falhar**

Run: `pnpm test app/javascript/dashboard/routes/dashboard/ramon/components/lead/specs/LeadFields.spec.js`
Expected: FAIL (testids não existem).

- [ ] **Step 3: Implementar em `LeadFields.vue`**

Imports novos no `<script setup>`:

```js
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import { waMeUrl } from '../../helpers/phone';
```

Funções (antes do template, respeitando no-use-before-define):

```js
const copyPhone = async () => {
  await copyTextToClipboard(props.lead.contact_phone);
  useAlert(t('RAMON.KANBAN.CARD.PHONE_COPIED'));
};
```

No template, trocar o parágrafo do telefone (linhas 391-393):

```html
<div
  v-if="lead.contact_phone"
  class="flex items-center gap-2 text-xs text-n-slate-10"
>
  <button
    data-testid="contact-copy-phone"
    :title="$t('RAMON.KANBAN.CARD.COPY_PHONE')"
    class="inline-flex items-center gap-1 hover:text-n-slate-12"
    @click="copyPhone"
  >
    <span class="i-lucide-phone size-3.5" />{{ lead.contact_phone }}
  </button>
  <a
    v-if="!lead.conversation_id"
    data-testid="contact-wa-me"
    :href="waMeUrl(lead.contact_phone)"
    target="_blank"
    rel="noopener noreferrer"
    class="inline-flex items-center gap-1 hover:text-n-iris-11"
  >
    <span class="i-lucide-message-circle size-3.5" />{{
      $t('RAMON.KANBAN.CARD.WHATSAPP')
    }}
  </a>
</div>
```

- [ ] **Step 4: Refactor `LeadCard.vue` para o helper (sem mudança de comportamento)**

Import: `import { waMeUrl } from '../../helpers/phone';`

Remover o computed `phoneDigits` (linhas 80-82) e no template trocar `:href="`https://wa.me/${phoneDigits}`"` por `:href="waMeUrl(lead.contact_phone)"`.

- [ ] **Step 5: Rodar specs afetados**

Run: `pnpm test app/javascript/dashboard/routes/dashboard/ramon/components/lead/specs/LeadFields.spec.js app/javascript/dashboard/routes/dashboard/ramon/components/kanban/specs/LeadCard.spec.js`
Expected: PASS.

- [ ] **Step 6: Lint + commit**

```bash
pnpm eslint app/javascript/dashboard/routes/dashboard/ramon/components/lead/LeadFields.vue app/javascript/dashboard/routes/dashboard/ramon/components/kanban/LeadCard.vue app/javascript/dashboard/routes/dashboard/ramon/components/lead/specs/LeadFields.spec.js
npx --yes prettier@3.3.3 --check "app/javascript/dashboard/routes/dashboard/ramon/components/**"
git add -A app/javascript/dashboard/routes/dashboard/ramon/components
git commit -m "feat(ramon): telefone clicavel (copiar + wa.me) na gaveta e painel do lead"
```

---

### Task 5: UI de cadência por etapa no FunilConfig (`stalled_after_days`)

**Files:**
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/pages/FunilConfig.vue`
- Modify: `app/javascript/dashboard/i18n/locale/pt_BR/ramon.json` e `app/javascript/dashboard/i18n/locale/en/ramon.json`
- Test: `app/javascript/dashboard/routes/dashboard/ramon/pages/specs/FunilConfig.spec.js`

**Interfaces:**
- Consumes: getter `leadConfig/getStages` (retorna stages com `id`, `name`, `stalled_after_days`), action `leadConfig/updateStage({ id, ...payload })` (já existe, `store/modules/leadConfig.js:44` — o controller já permite `stalled_after_days`).
- Produces: seção "Cadência" com um input numérico por etapa; salvar no change; vazio = sem limite (`null`).

- [ ] **Step 1: Escrever spec (falhando)** — adicionar ao `FunilConfig.spec.js` (seguir o padrão de store do arquivo; garantir que o módulo `leadConfig` do teste tenha o getter `getStages` com `[{ id: 1, name: 'Novo', stalled_after_days: 3 }, { id: 2, name: 'Qualificação', stalled_after_days: null }]` e a action `updateStage: updateStageSpy`):

```js
it('renders one cadence input per stage and saves on change', async () => {
  const updateStage = vi.fn();
  const wrapper = mountPage({ updateStage }); // adaptar ao builder local do spec
  const inputs = wrapper.findAll('[data-testid="stage-stalled-days"]');
  expect(inputs).toHaveLength(2);
  expect(inputs[0].element.value).toBe('3');

  await inputs[1].setValue('5');
  expect(updateStage).toHaveBeenCalledWith(expect.anything(), {
    id: 2,
    stalled_after_days: 5,
  });
});

it('clears the limit when the input is emptied', async () => {
  const updateStage = vi.fn();
  const wrapper = mountPage({ updateStage });
  const first = wrapper.findAll('[data-testid="stage-stalled-days"]')[0];
  await first.setValue('');
  expect(updateStage).toHaveBeenCalledWith(expect.anything(), {
    id: 1,
    stalled_after_days: null,
  });
});
```

(Se o spec atual não tiver um builder parametrizável, criar `mountPage` no topo seguindo o `build()` do `LeadFields.spec.js`.)

- [ ] **Step 2: Rodar e ver falhar**

Run: `pnpm test app/javascript/dashboard/routes/dashboard/ramon/pages/specs/FunilConfig.spec.js`
Expected: FAIL.

- [ ] **Step 3: Implementar em `FunilConfig.vue`**

No `<script setup>`:

```js
const stages = computed(() => getters['leadConfig/getStages'].value);

const saveStalled = (stage, raw) => {
  const days = raw === '' ? null : Math.max(0, Number(raw));
  if (days === (stage.stalled_after_days ?? null)) return;
  store.dispatch('leadConfig/updateStage', {
    id: stage.id,
    stalled_after_days: days,
  });
};
```

No template, nova `<section class="mb-8">` entre Benefícios e Prioridades (ou após Prioridades — escolher o fim da página para não deslocar testes existentes):

```html
<section class="mt-8">
  <h2 class="mb-1 text-sm uppercase tracking-widest text-n-slate-9">
    {{ $t('RAMON.FUNIL_CONFIG.CADENCE') }}
  </h2>
  <p class="mb-3 text-xs text-n-slate-10">
    {{ $t('RAMON.FUNIL_CONFIG.CADENCE_HINT') }}
  </p>
  <ul>
    <li
      v-for="s in stages"
      :key="s.id"
      class="flex items-center justify-between px-3 py-2 rounded-lg hover:bg-n-alpha-2"
    >
      <span class="text-sm text-n-slate-12">{{ s.name }}</span>
      <span class="flex items-center gap-2">
        <input
          :value="s.stalled_after_days"
          data-testid="stage-stalled-days"
          type="number"
          min="0"
          class="w-20 px-3 py-1.5 text-sm rounded-lg bg-n-alpha-2 text-n-slate-12"
          @change="e => saveStalled(s, e.target.value)"
        />
        <span class="text-xs text-n-slate-9">{{
          $t('RAMON.FUNIL_CONFIG.CADENCE_DAYS')
        }}</span>
      </span>
    </li>
  </ul>
</section>
```

- [ ] **Step 4: i18n** — em `pt_BR/ramon.json`, dentro de `FUNIL_CONFIG`:

```json
"CADENCE": "Cadência por etapa",
"CADENCE_HINT": "Dias sem andamento até o lead ser marcado como parado (vazio = sem limite; o dobro fica vermelho)",
"CADENCE_DAYS": "dias"
```

Em `en/ramon.json`, mesmo lugar:

```json
"CADENCE": "Stage cadence",
"CADENCE_HINT": "Days without progress until the lead is flagged as stalled (empty = no limit; twice that turns red)",
"CADENCE_DAYS": "days"
```

- [ ] **Step 5: Rodar e ver passar**

Run: `pnpm test app/javascript/dashboard/routes/dashboard/ramon/pages/specs/FunilConfig.spec.js`
Expected: PASS.

- [ ] **Step 6: Lint + commit**

```bash
pnpm eslint app/javascript/dashboard/routes/dashboard/ramon/pages/FunilConfig.vue app/javascript/dashboard/routes/dashboard/ramon/pages/specs/FunilConfig.spec.js
npx --yes prettier@3.3.3 --check "app/javascript/dashboard/routes/dashboard/ramon/pages/**" "app/javascript/dashboard/i18n/locale/pt_BR/ramon.json" "app/javascript/dashboard/i18n/locale/en/ramon.json"
git add -A app/javascript/dashboard/routes/dashboard/ramon/pages app/javascript/dashboard/i18n
git commit -m "feat(ramon): config de cadencia (stalled_after_days) por etapa no funil"
```

---

## Fechamento (fora das tasks — orquestrador)

1. `pnpm test app/javascript/dashboard/routes/dashboard/ramon` completo + `pnpm eslint` nos arquivos tocados.
2. Push da branch, abrir PR (formato do AGENTS.md, parágrafo de produto + "How to test").
3. **Verificação de CI obrigatória**: `gh pr view N --json statusCheckRollup` filtrando `conclusion != SUCCESS` no commit exato — nunca lista truncada.
4. Merge/deploy = gate do Eduardo.
