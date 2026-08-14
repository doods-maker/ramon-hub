# Onda 2 — Pós-venda ("Coleta de Documentos") Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fechar o pós-venda do funil: aba "Documentos" no painel do lead, cobrança como rascunho na caixa de resposta, badge docs X/Y no Kanban, visão "Pós-venda" (ganhos com docs pendentes), IA casando anexo recebido↔item do checklist, export incremental dos docs conferidos pro Google Drive e tarefa no ADVBOX quando o pacote fecha.

**Architecture:** Zero migração — todo estado novo vive em `leads.custom_attributes` (jsonb), como `doc_status` já faz. Drive e tarefa ADVBOX são features atrás de env (padrão `NTFY_TOPIC`): sem env, no-op silencioso. O casamento anexo↔item reusa o padrão `checklist_ok` da colheita (LLM texto-apenas recebe `id: item` + nome do arquivo + últimas mensagens; devolve JSON tolerante). Lead ganho NUNCA sai de "Fechado" (ADR-0001); "Concluído" é derivado (checklist completo + pacote no Drive).

**Tech Stack:** Rails 7 (fork Chatwoot v4.15.1), Vue 3 `<script setup>`, sidekiq, RubyLLM via `Ramon::LlmClient` (deepseek), gems novas: `google-apis-drive_v3`, `googleauth`, `prawn`.

**Spec:** `docs/superpowers/specs/2026-08-13-funil-estrategico-design.md` (decisões 6–10) + `docs/adr/0001-pos-venda-como-estado-derivado.md` + `docs/adr/0002-drive-como-ponte-de-documentos-para-advbox.md`.

## Global Constraints

- **Idioma da UI: pt-BR** — strings novas em `app/javascript/dashboard/i18n/locale/pt_BR/ramon.json` E `.../en/ramon.json` (paridade estrutural; namespace `RAMON.DOCS` já existe em ambos no mesmo offset).
- **Sem migração de banco.** Estado novo só em `custom_attributes` (chaves novas: `doc_sugestao`, `doc_anexos`, `drive`).
- **PATCH de `custom_attributes` faz `deep_merge` server-side** (`leads_controller.rb:168-176`) — mandar SÓ a chave que mudou; chave nunca é removida, só sobrescrita.
- **Broadcast do lead**: escalar novo no jbuilder slim TEM espelho no event data (`lead.rb#push_event_data`); só tipos JSON-nativos (inteiro/string — nunca BigDecimal).
- **Specs RSpec: SÓ estender arquivos existentes** (lição knapsack 20/07). Exceção: no máximo 2 arquivos novos (`spec/services/ramon/doc_match_service_spec.rb`, `spec/services/ramon/drive_export_service_spec.rb`); se um shard core sem relação falhar no CI depois disso, fundir esses specs em arquivos existentes em vez de caçar a lógica. Specs Vue (vitest) novos são livres.
- **Princípio de aprovação**: NADA é enviado ao cliente pelo código — cobrança vira rascunho no editor (quem envia é o Eduardo); IA só sugere, humano confirma.
- **LLM**: provider deepseek via `Ramon::LlmClient.complete` — sem json_schema; prompt pede "APENAS um JSON válido" + parse tolerante (padrão `night_copilot_service.rb:76-85`); texto de conversa passa por `Ramon::Pseudonymizer.mask`.
- Rubocop 150 col; eventos Vue camelCase; sem string literal em template (i18n); `with_modified_env` em spec para ENV.
- Executar em worktree próprio (`ramon-hub-wt-onda2`); lembrar: junction de `node_modules` + cópia de `.husky/_` (pnpm não é global).
- Branch única, 1 commit por task, 1 PR no final; merge só com CI 100% verde (regime autônomo).

**Envs novas (todas opcionais — sem elas a feature é no-op):**
| ENV | Uso |
|---|---|
| `RAMON_DRIVE_CREDENTIALS` | path do JSON da service account no container |
| `RAMON_DRIVE_ROOT_ID` | id da pasta-raiz no Drive (contém `Clientes` e `A enviar ao ADVBOX`) |
| `RAMON_ADVBOX_CONTROLLER_ID` | id de usuário ADVBOX da controller (tarefa do pacote completo) |
| `RAMON_ADVBOX_DOCS_TASK_ID` | id do tipo de tarefa ADVBOX usado nessa tarefa |

---

### Task 1: Aba "Documentos" no painel do lead

Tira o `DocChecklist` de dentro do `LeadFields` (enterrado atrás de "editar todos os campos") e dá a ele uma aba própria, com dot quando há pendência.

**Files:**
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/composables/useLeadPanelSections.js:7-14` (whitelist `LEAD_PANEL_TABS`)
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/components/lead/LeadPanelBody.vue` (array `TABS` ~:210, corpo da aba ~:468-653, guarda `shownTab` ~:218)
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/components/lead/LeadFields.vue:9,666` (REMOVER import + render do DocChecklist)
- Modify: `app/javascript/dashboard/i18n/locale/pt_BR/ramon.json` e `.../en/ramon.json` (`RAMON.LEAD_PANEL.TABS.DOCUMENTS`)
- Test: `app/javascript/dashboard/routes/dashboard/ramon/components/lead/specs/DocChecklist.spec.js` (estender)

**Interfaces:**
- Produces: aba `id: 'documentos'` renderizando `<DocChecklist :lead="lead" :context="props.context" />` — Task 2 depende do prop `context` chegar no DocChecklist.

- [ ] **Step 1: Adicionar `'documentos'` à whitelist**

Em `useLeadPanelSections.js`, dentro do array `LEAD_PANEL_TABS`, adicionar `'documentos'` (depois de `'simulador'`). Sem isso `setTab('documentos')` é no-op silencioso — é a armadilha documentada do arquivo.

- [ ] **Step 2: Declarar a aba em `LeadPanelBody.vue`**

No computed `TABS` (~:210), depois da entrada `simulador`:

```js
...(props.lead?.thesis_id ? [{ id: 'documentos', label: 'DOCUMENTS', dot: docsDot }] : []),
```

Criar o dot (perto de `iaDot`/`simuladorDot`, ~:196-204) — âmbar quando há item não-recebido, seguindo o mesmo padrão de computed ref lido como `tab.dot?.value` no template:

```js
// Dot âmbar: existe item de documento ainda não recebido (docs_total/received
// vêm do jbuilder — Task 3; antes dela o dot fica apagado, sem erro).
const docsDot = computed(() =>
  props.lead?.docs_total > 0 && props.lead?.docs_received < props.lead?.docs_total
    ? 'bg-n-amber-9'
    : null
);
```

(Conferir como `iaDot` expressa a cor — copiar o formato exato do valor devolvido, que pode ser classe ou token.)

- [ ] **Step 3: Guarda no `shownTab`**

No computed `shownTab` (~:218-222), espelhar o precedente do `contrato`:

```js
const shownTab = computed(() => {
  if (activeTab.value === 'contrato' && !zapsignEligible.value) return 'resumo';
  if (activeTab.value === 'documentos' && !props.lead?.thesis_id) return 'resumo';
  return activeTab.value;
});
```

- [ ] **Step 4: Corpo da aba**

Na cadeia `v-if/v-else-if` do template (~:468-653), adicionar:

```html
<div v-else-if="shownTab === 'documentos'" class="flex flex-col gap-3">
  <DocChecklist :lead="lead" :context="context" />
</div>
```

Importar `DocChecklist` no `<script setup>` do `LeadPanelBody.vue`. Em `DocChecklist.vue`, adicionar o prop novo (default preserva comportamento fora da conversa):

```js
context: { type: String, default: 'drawer' },
```

- [ ] **Step 5: Remover do LeadFields**

Apagar o import (`LeadFields.vue:9`) e o render (`:666`) do `DocChecklist`. Nenhum outro consumidor existe (verificado — só o spec).

- [ ] **Step 6: i18n**

`pt_BR/ramon.json`, em `RAMON.LEAD_PANEL.TABS`: `"DOCUMENTS": "Documentos"`. Mesmo path no `en/ramon.json`: `"DOCUMENTS": "Documents"`.

- [ ] **Step 7: Estender `DocChecklist.spec.js`**

Adicionar teste de que o componente monta com o prop `context` e o existente segue verde:

```js
it('aceita o prop context sem mudar o render', () => {
  const wrapper = mountComponent({ context: 'conversation' });
  expect(wrapper.find('[data-testid="doc-count"]').exists()).toBe(true);
});
```

(Usar o helper de mount que o spec já tem.)

- [ ] **Step 8: Rodar lint + testes front**

Run: `pnpm eslint app/javascript/dashboard/routes/dashboard/ramon --no-error-on-unmatched-pattern` e `pnpm test -- DocChecklist`
Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add -A && git commit -m "feat(ramon): aba Documentos propria no painel do lead"
```

---

### Task 2: "Cobrar pendentes" vira rascunho na caixa de resposta

No contexto conversa, o botão insere o texto no editor (`INSERT_INTO_NORMAL_EDITOR` — mesmo mecanismo do LeadCopilot); na gaveta do Kanban (sem ReplyBox montado) continua clipboard.

**Files:**
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/components/lead/DocChecklist.vue:98-127` (função `chargePending`)
- Modify: `pt_BR/ramon.json` + `en/ramon.json` (`RAMON.DOCS.DRAFT_READY`)
- Test: `.../specs/DocChecklist.spec.js` (estender)

**Interfaces:**
- Consumes: prop `context` da Task 1; `emitter` de `shared/helpers/mitt` + `BUS_EVENTS.INSERT_INTO_NORMAL_EDITOR` de `shared/constants/busEvents` (`busEvents.js:15`).

- [ ] **Step 1: Teste primeiro (estender o spec)**

```js
it('no contexto conversa, cobrar pendentes emite INSERT_INTO_NORMAL_EDITOR e nao copia', async () => {
  const wrapper = mountComponent({ context: 'conversation' });
  const spy = vi.spyOn(emitter, 'emit');
  await wrapper.find('[data-testid="doc-charge"]').trigger('click');
  expect(spy).toHaveBeenCalledWith(BUS_EVENTS.INSERT_INTO_NORMAL_EDITOR, expect.stringContaining('•'));
});
```

(Importar `emitter`/`BUS_EVENTS` no spec; conferir como specs existentes mockam o clipboard.)

- [ ] **Step 2: Run — deve falhar** (`pnpm test -- DocChecklist`).

- [ ] **Step 3: Implementar em `chargePending`**

Trocar o miolo (mantendo a montagem das linhas i18n e a marcação `pendente → solicitado` que já existem):

```js
// Princípio de aprovação: o texto cai como RASCUNHO no editor — quem envia é
// o Eduardo. Na gaveta (sem ReplyBox montado) o clipboard continua o caminho.
if (props.context === 'conversation') {
  emitter.emit(BUS_EVENTS.INSERT_INTO_NORMAL_EDITOR, lines.join('\n'));
  useAlert(t('RAMON.DOCS.DRAFT_READY'));
} else {
  await copyTextToClipboard(lines.join('\n'));
  useAlert(t('RAMON.DOCS.COPIED'));
}
```

Imports novos no componente: `import { emitter } from 'shared/helpers/mitt';` e `import { BUS_EVENTS } from 'shared/constants/busEvents';` (copiar o estilo exato de `LeadCopilot.vue:5-6`).

- [ ] **Step 4: i18n**

`RAMON.DOCS.DRAFT_READY`: pt_BR `"Rascunho na caixa de resposta — revise e envie"`; en `"Draft added to the reply box — review and send"`.

- [ ] **Step 5: Run — PASS** + eslint.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat(ramon): cobranca de docs vira rascunho na caixa de resposta"
```

---

### Task 3: Escalares `docs_received`/`docs_total` no slim + badge no card

O índice do Kanban é slim (sem `custom_attributes`) — o badge precisa de escalares próprios, padrão `follow_up_count` (jbuilder + espelho no broadcast).

**Files:**
- Modify: `app/models/lead.rb` (método `docs_counts` + merge no `push_event_data` ~:49-75)
- Modify: `app/views/api/v1/accounts/leads/_lead.json.jbuilder` (fora do `unless slim`, junto de `follow_up_count`)
- Modify: `app/controllers/api/v1/accounts/leads_controller.rb` (includes do índice: adicionar `{ thesis: :thesis_items }` — conferir a lista atual de `includes` do index/`filtered_leads`)
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/components/kanban/LeadCard.vue` (badge na linha 2, ~:353-360 como referência)
- Modify: `pt_BR/ramon.json` + `en/ramon.json` (`RAMON.DOCS.CARD_TITLE`)
- Test: `spec/models/lead_spec.rb` e `spec/controllers/api/v1/accounts/leads_controller_spec.rb` (estender — NÃO criar arquivo)

**Interfaces:**
- Produces: `Lead#docs_counts` → `{ received: Integer, total: Integer }` (chaves símbolo); JSON do lead (slim incluso) ganha `docs_received`/`docs_total`. Tasks 1 (dot), 4 (visão) e 7 (checklist completo) consomem.

- [ ] **Step 1: Teste do modelo (estender `spec/models/lead_spec.rb`)**

```ruby
describe '#docs_counts' do
  let(:thesis) { create(:thesis, account: account) }
  let!(:doc_item) { create(:thesis_item, thesis: thesis, section: 'documento', content: 'RG') }
  let!(:outro_item) { create(:thesis_item, thesis: thesis, section: 'colheita', content: 'Renda') }

  it 'conta so itens de documento, com recebido vindo do doc_status' do
    lead = create(:lead, account: account, thesis: thesis,
                  custom_attributes: { 'doc_status' => { doc_item.id.to_s => 'recebido' } })
    expect(lead.docs_counts).to eq(received: 1, total: 1)
  end

  it 'zera sem tese' do
    lead = create(:lead, account: account)
    expect(lead.docs_counts).to eq(received: 0, total: 0)
  end
end
```

(Conferir os factories existentes de thesis/thesis_item no spec — reusar os `let` que o arquivo já tiver.)

- [ ] **Step 2: Run — FAIL** (`bundle exec rspec spec/models/lead_spec.rb -e docs_counts`; sem ambiente local, este run acontece no CI — validar por leitura e deixar o CI provar).

- [ ] **Step 3: Implementar `Lead#docs_counts`**

Em `app/models/lead.rb` (perto dos helpers de leitura existentes):

```ruby
# Contagem do checklist de documentos (badge do card + visão Pós-venda).
# Loaded-aware: o índice do Kanban precarrega thesis_items — sem query por lead.
def docs_counts
  return { received: 0, total: 0 } if thesis_id.blank? || thesis.nil?

  items = if thesis.association(:thesis_items).loaded?
            thesis.thesis_items.select { |i| i.section == 'documento' }
          else
            thesis.thesis_items.where(section: 'documento').to_a
          end
  status = custom_attributes&.dig('doc_status') || {}
  { received: items.count { |i| status[i.id.to_s] == 'recebido' }, total: items.size }
end
```

- [ ] **Step 4: jbuilder + broadcast + includes**

No `_lead.json.jbuilder`, logo após o bloco `follow_up_*` (fora do `unless slim`), com o mesmo estilo de comentário-doutrina do arquivo:

```ruby
docs = lead.docs_counts
json.docs_received docs[:received]
json.docs_total docs[:total]
```

Em `lead.rb#push_event_data`, adicionar ao hash final (espelho do jbuilder — inteiros, JSON-nativos):

```ruby
docs = docs_counts
# ...dentro do hash:
docs_received: docs[:received],
docs_total: docs[:total],
```

No `leads_controller` (índice), acrescentar `{ thesis: :thesis_items }` ao `includes` existente (o índice já precarrega 7 associações — só estender a lista; `thesis` sozinho já pode estar lá: nesse caso trocar por `{ thesis: :thesis_items }`).

- [ ] **Step 5: Teste do índice (estender `leads_controller_spec.rb`)**

No bloco do `GET index` já existente, adicionar expectativa de que o payload traz `docs_received`/`docs_total` (mesmo estilo das asserções vizinhas de `follow_up_count`).

- [ ] **Step 6: Badge no `LeadCard.vue`**

Na linha 2 (após o badge follow-up, ~:360):

```html
<span
  v-if="lead.docs_total > 0"
  data-testid="docs-badge"
  :title="$t('RAMON.DOCS.CARD_TITLE', { received: lead.docs_received, total: lead.docs_total })"
  class="inline-flex items-center gap-0.5"
  :class="lead.docs_received >= lead.docs_total ? 'text-n-teal-11' : 'text-n-slate-10'"
>
  <span class="i-lucide-file-check size-3" />{{ lead.docs_received }}/{{ lead.docs_total }}
</span>
```

i18n `RAMON.DOCS.CARD_TITLE`: pt_BR `"Documentos: {received} de {total} recebidos"`; en `"Documents: {received} of {total} received"`.

- [ ] **Step 7: Rubocop + eslint** (`bundle exec rubocop -a` nos arquivos tocados; `pnpm eslint`).

- [ ] **Step 8: Commit**

```bash
git add -A && git commit -m "feat(ramon): docs X/Y no slim do kanban e badge no card"
```

---

### Task 4: Visão "Pós-venda" (endpoint + página + menu)

Ganhos com docs pendentes, ordenados por dias desde o ganho — padrão RadarPrescricao (endpoint dedicado; quadro salvo não expressa isso: não há filtro de docs nem `custom_attributes` no slim).

**Files:**
- Create: `app/controllers/api/v1/accounts/ramon_pos_venda_controller.rb`
- Create: `app/views/api/v1/accounts/ramon_pos_venda/show.json.jbuilder`
- Modify: `app/services/ramon/lead_radar.rb` (método `pos_venda`)
- Modify: `config/routes.rb` (perto da rota do `ramon_prescription_radar`)
- Create: `app/javascript/dashboard/api/ramonPosVenda.js`
- Create: `app/javascript/dashboard/routes/dashboard/ramon/pages/PosVenda.vue`
- Modify: `.../ramon/ramon.routes.js` + `.../ramon/components/IntranetSidebar.vue` (seção COMERCIAL)
- Modify: `pt_BR/ramon.json` + `en/ramon.json` (namespace novo `RAMON.POS_VENDA` + `RAMON.NAV.POS_VENDA`)
- Test: `spec/controllers/api/v1/accounts/leads_controller_spec.rb` NÃO — usar o spec de request que cobre o radar (localizar `spec/**/*prescription_radar*` e estender o MESMO arquivo com um describe do pós-venda; se não existir spec do radar, estender `spec/services/ramon/lead_radar_spec.rb` se houver — senão o describe novo entra em `spec/models/lead_spec.rb` cobrindo só o service)

**Interfaces:**
- Consumes: `Lead#docs_counts` (Task 3).
- Produces: `GET /api/v1/accounts/:account_id/ramon_pos_venda` → `{ pendentes: [...], concluidos: [...] }`; cada item: `{ id, name, won_at, dias, docs_received, docs_total, conversation_id, drive_concluido }`. Rota front `ramon_pos_venda`.

- [ ] **Step 1: Service — `Ramon::LeadRadar.pos_venda`**

Em `lead_radar.rb` (module_function, como os vizinhos):

```ruby
# Pós-venda (ADR-0001): ganhos ficam em "Fechado"; aqui a visão deriva o
# estado — pendente = checklist de documento incompleto; concluído = completo.
# Ganho sem item de documento na tese fica fora (nada a coletar).
def pos_venda(account)
  ganhos = account.leads.funil.where.not(won_at: nil)
                  .includes(:contact, thesis: :thesis_items)
  com_docs = ganhos.select { |l| l.docs_counts[:total].positive? }
  pendentes, concluidos = com_docs.partition { |l| l.docs_counts[:received] < l.docs_counts[:total] }
  { pendentes: pendentes.sort_by(&:won_at), concluidos: concluidos.sort_by(&:won_at).reverse.first(20) }
end
```

(`docs_counts` é chamado 2–3x por lead sobre associação carregada — sem query extra; memo desnecessário.)

- [ ] **Step 2: Controller + rota + jbuilder**

Controller no padrão do radar (herda do mesmo base controller — copiar a classe do `ramon_prescription_radar_controller` como referência de permissão/estrutura):

```ruby
class Api::V1::Accounts::RamonPosVendaController < Api::V1::Accounts::BaseController
  def show
    @dados = Ramon::LeadRadar.pos_venda(Current.account)
  end
end
```

Rota (`config/routes.rb`, ao lado do radar): `resource :ramon_pos_venda, controller: 'ramon_pos_venda', only: [:show]`.

`show.json.jbuilder`:

```ruby
%i[pendentes concluidos].each do |grupo|
  json.set! grupo do
    json.array! @dados[grupo] do |lead|
      docs = lead.docs_counts
      json.id lead.id
      json.name lead.contact&.name || lead.name
      json.won_at lead.won_at
      json.dias ((Time.zone.now - lead.won_at) / 1.day).floor
      json.docs_received docs[:received]
      json.docs_total docs[:total]
      json.conversation_id lead.conversation_id
      json.drive_concluido lead.custom_attributes&.dig('drive', 'concluido_em').present?
    end
  end
end
```

- [ ] **Step 3: Spec do endpoint** — estender o arquivo de spec do radar (ver Files acima): request GET autenticado devolve 200, lead ganho com doc pendente aparece em `pendentes`, lead com checklist completo em `concluidos`, lead ganho de tese sem item `documento` não aparece.

- [ ] **Step 4: Front — API + página + rota + menu**

`ramonPosVenda.js` (copiar o shape do `ramonPrescriptionRadar.js`, endpoint `ramon_pos_venda`).

`PosVenda.vue` no padrão `RadarPrescricao.vue` (206 linhas — copiar a estrutura): tripla `data/loading/error` + `fetchData` + `onMounted`; `RamonPageHeader` com título i18n; skeleton; erro com retry; vazio próprio ("Nenhum ganho com documentos pendentes 🎉"). Lista `pendentes`: nome, `{dias} dias desde o ganho`, `docs X/Y`, borda-esquerda âmbar quando `dias > 7`. Clique na linha = padrão `openLead` do radar (`router.push` pro funil + `leads/select`); botão secundário "Conversa" navega pra conversa quando `conversation_id` presente (conferir como o LeadCard/`open-conversation` monta essa rota e copiar). Seção "Concluídos" abaixo, colapsada por padrão, mostrando check teal + `drive_concluido` como chip "no Drive".

Rota em `ramon.routes.js` (lazy, `world: 'intranet'`, permissions `['administrator', 'agent']`, name `ramon_pos_venda`). Item no `IntranetSidebar.vue` seção COMERCIAL, depois do Radar: `{ key: 'posvenda', label: t('RAMON.NAV.POS_VENDA'), icon: 'i-lucide-package-check', to: accountScopedRoute('ramon_pos_venda'), names: ['ramon_pos_venda'] }`.

i18n: `RAMON.NAV.POS_VENDA = "Pós-venda"`; namespace `RAMON.POS_VENDA` com `TITLE`, `SUBTITLE` ("Ganhos aguardando documentos — do mais antigo pro mais novo"), `DIAS` (`"{dias} dias desde o ganho"`), `EMPTY`, `ERROR`, `RETRY`, `CONCLUIDOS`, `DRIVE_CHIP` ("no Drive"), `OPEN_CONVERSATION`. Paridade no `en`.

- [ ] **Step 5: Lint + testes** (`rubocop`, `eslint`, rspec do arquivo estendido).

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat(ramon): visao Pos-venda — ganhos com docs pendentes"
```

---

### Task 5: IA casa anexo↔item (backend)

Anexo incoming (imagem/arquivo) em lead com docs pendentes → job LLM sugere o item do checklist. Texto-apenas (deepseek sem visão): a pista é nome do arquivo + tipo + últimas mensagens. Grava sugestão em `custom_attributes['doc_sugestao']`; o broadcast leva ao painel.

**Files:**
- Create: `app/services/ramon/doc_match_service.rb`
- Create: `app/jobs/ramon/doc_match_job.rb`
- Modify: `app/listeners/ramon_lead_listener.rb:25-34` (`message_created`)
- Test: `spec/services/ramon/doc_match_service_spec.rb` (1 dos 2 arquivos novos permitidos) + estender o spec existente do `ramon_lead_listener` (localizar em `spec/listeners/`)

**Interfaces:**
- Consumes: `Ramon::LlmClient.complete(provider:, model:, system:, user:, sensitive: false)` → `Result(content,...)`; `Ramon::Pseudonymizer.mask(text, names:)`; padrão de parse tolerante e `checklist_block` de `colheita_extraction_service.rb:90-99`.
- Produces: `custom_attributes['doc_sugestao'] = { 'item_id' => Integer, 'attachment_id' => Integer, 'message_id' => Integer, 'em' => iso8601, 'resolvida' => false }`. Task 6 (front) consome esse shape exato.

- [ ] **Step 1: Spec do service (arquivo novo permitido)**

```ruby
require 'rails_helper'

describe Ramon::DocMatchService do
  let(:account) { create(:account) }
  let(:thesis) { create(:thesis, account: account) }
  let!(:rg) { create(:thesis_item, thesis: thesis, section: 'documento', content: 'RG') }
  let(:conversation) { create(:conversation, account: account) }
  let(:lead) { create(:lead, account: account, thesis: thesis, conversation: conversation) }
  let(:message) do
    create(:message, account: account, conversation: conversation, message_type: :incoming).tap do |m|
      m.attachments.create!(account_id: account.id, file_type: :image,
                            file: fixture_file_upload('spec/assets/avatar.png', 'image/png'))
    end
  end

  it 'grava doc_sugestao quando o LLM aponta um item valido' do
    allow(Ramon::LlmClient).to receive(:complete)
      .and_return(Ramon::LlmClient::Result.new(content: %({"item_id": #{rg.id}}), input_tokens: 1, output_tokens: 1))
    described_class.new(message).perform
    expect(lead.reload.custom_attributes.dig('doc_sugestao', 'item_id')).to eq(rg.id)
  end

  it 'nao grava com item fora do checklist' do
    allow(Ramon::LlmClient).to receive(:complete)
      .and_return(Ramon::LlmClient::Result.new(content: '{"item_id": 999999}', input_tokens: 1, output_tokens: 1))
    described_class.new(message).perform
    expect(lead.reload.custom_attributes['doc_sugestao']).to be_nil
  end
end
```

(Conferir factory de attachment/fixture existente — reusar o asset que os specs de attachment do core já usam.)

- [ ] **Step 2: Implementar o service**

```ruby
module Ramon
  class DocMatchService
    PROVIDER = ENV.fetch('RAMON_COPILOT_MODEL_PROVIDER', 'deepseek') # ponytail: mesmo provider dos copilots
    SYSTEM_PROMPT = <<~PROMPT.freeze
      Você recebe um checklist de documentos de um caso previdenciário, os dados de um
      arquivo que o cliente acabou de enviar e o fim da conversa. Aponte QUAL item do
      checklist o arquivo provavelmente é. Responda APENAS um JSON válido (sem markdown):
      {"item_id": <id do item>} ou {"item_id": null} se não der pra afirmar.
      Na dúvida, responda null — nunca chute.
    PROMPT

    def initialize(message)
      @message = message
    end

    def perform
      lead = @message.account.leads.find_by(conversation_id: @message.conversation_id)
      return if lead.blank? || lead.thesis_id.blank?

      itens = pendentes(lead)
      return if itens.empty?

      attachment = @message.attachments.detect { |a| %w[image file].include?(a.file_type) }
      return if attachment.blank?

      item_id = ask_llm(lead, itens, attachment)
      return if item_id.blank? || itens.none? { |i| i.id == item_id }

      gravar_sugestao(lead, item_id, attachment)
    end

    private

    def pendentes(lead)
      status = lead.custom_attributes&.dig('doc_status') || {}
      lead.thesis.thesis_items.where(section: 'documento').reject { |i| status[i.id.to_s] == 'recebido' }
    end

    def ask_llm(lead, itens, attachment)
      checklist = itens.map { |i| "#{i.id}: #{i.title.presence || i.content}" }.join("\n")
      arquivo = "arquivo: #{attachment.file.filename} (#{attachment.file.content_type})"
      conversa = Ramon::Pseudonymizer.mask(transcript(lead), names: [lead.contact&.name].compact)
      result = Ramon::LlmClient.complete(
        provider: PROVIDER, model: ENV.fetch('RAMON_COPILOT_MODEL', 'deepseek-chat'),
        system: SYSTEM_PROMPT,
        user: "Checklist:\n#{checklist}\n\n#{arquivo}\n\nFim da conversa:\n#{conversa}"
      )
      parse_item_id(result.content)
    end

    def parse_item_id(content)
      parsed = JSON.parse(content.to_s.sub(/\A```(?:json)?\s*/, '').sub(/```\s*\z/, ''))
      parsed.is_a?(Hash) ? parsed['item_id'] : nil
    rescue JSON::ParserError
      Rails.logger.warn("[Ramon::DocMatchService] resposta não-JSON do LLM para message=#{@message.id}")
      nil
    end

    def transcript(lead)
      lead.conversation.messages.where(message_type: [:incoming, :outgoing], private: false)
          .order(:created_at).last(10)
          .filter_map { |m| m.content_for_llm.presence }
          .reject { |t| t == '[Attachment]' }.join("\n")
    end

    def gravar_sugestao(lead, item_id, attachment)
      lead.reload # padrão advbox: merge sobre o estado atual, só a chave nova
      lead.update!(custom_attributes: lead.custom_attributes.to_h.merge(
        'doc_sugestao' => { 'item_id' => item_id, 'attachment_id' => attachment.id,
                            'message_id' => @message.id, 'em' => Time.zone.now.iso8601,
                            'resolvida' => false }
      ))
    end
  end
end
```

(Conferir a API exata de `attachment.file.filename`; se o blob ainda não estiver anexado — lição do concern enterprise — o `retry_on` do job cobre.)

- [ ] **Step 3: Job**

```ruby
module Ramon
  class DocMatchJob < ApplicationJob
    queue_as :low
    retry_on Ramon::LlmClient::TransientError, wait: :polynomially_longer, attempts: 3
    retry_on ActiveStorage::FileNotFoundError, wait: 5.seconds, attempts: 3

    def perform(message_id)
      message = Message.find_by(id: message_id)
      return if message.blank?

      Ramon::DocMatchService.new(message).perform
    end
  end
end
```

- [ ] **Step 4: Gancho no listener**

Em `ramon_lead_listener.rb#message_created` (depois dos hooks existentes — o método já garante `incoming` e resolve o lead; NÃO duplicar essas buscas, só enfileirar):

```ruby
# Anexo de documento → IA sugere o item do checklist (confirmação humana no painel).
Ramon::DocMatchJob.perform_later(message.id) if message.attachments.any? { |a| %w[image file].include?(a.file_type) }
```

(Colocar no ponto do método onde `lead` já está resolvido e presente; pular quando o lead não tem tese — o service re-checa de qualquer forma.)

- [ ] **Step 5: Estender o spec do listener** — mensagem incoming com anexo de imagem enfileira `Ramon::DocMatchJob`; sem anexo, não enfileira (mesmo estilo dos exemplos vizinhos; `have_enqueued_job`).

- [ ] **Step 6: Rubocop + rspec dos arquivos tocados.**

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "feat(ramon): IA sugere item do checklist para anexo recebido"
```

---

### Task 6: Sugestão da IA no painel — confirmação de 1 clique

Chip no topo do `DocChecklist`: «Parece "RG" — marcar recebido?» com Confirmar/Dispensar. Confirmar grava `recebido` + vincula o anexo (`doc_anexos`) — é esse vínculo que a Task 7 exporta.

**Files:**
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/components/lead/DocChecklist.vue`
- Modify: `pt_BR/ramon.json` + `en/ramon.json` (`RAMON.DOCS.SUGESTAO.*`)
- Test: `.../specs/DocChecklist.spec.js` (estender)

**Interfaces:**
- Consumes: shape `doc_sugestao` da Task 5; PATCH `leads/update` com deep_merge server-side.
- Produces: `custom_attributes['doc_anexos'] = { '<item_id>' => attachment_id }` (chave string, valor inteiro) — Task 7 lê esse mapa. `doc_sugestao.resolvida = true` esconde o chip (deep_merge não remove chave — flag, não deleção).

- [ ] **Step 1: Testes primeiro (estender o spec)**

```js
it('mostra o chip quando ha doc_sugestao pendente e some quando resolvida', () => { /* lead com custom_attributes.doc_sugestao {item_id, resolvida:false} → chip visível; resolvida:true → ausente */ });
it('confirmar marca recebido, vincula anexo e resolve a sugestao', async () => {
  /* clique em [data-testid="doc-sugestao-confirm"] → dispatch leads/update com
     { doc_status: {'<id>': 'recebido'}, doc_anexos: {'<id>': attachment_id},
       doc_sugestao: { resolvida: true } } dentro de custom_attributes */
});
```

(Escrever as asserções completas no estilo dos testes de `cycle` que o spec já tem.)

- [ ] **Step 2: Run — FAIL.**

- [ ] **Step 3: Implementar no `DocChecklist.vue`**

Computed + ações:

```js
const sugestao = computed(() => {
  const s = props.lead.custom_attributes?.doc_sugestao;
  if (!s || s.resolvida) return null;
  const item = docItems.value.find(i => i.id === s.item_id);
  // Sugestão de item já recebido não ajuda — trata como resolvida visualmente.
  if (!item || statusFor(item) === 'recebido') return null;
  return { ...s, item };
});

const resolverSugestao = async aceitar => {
  const patch = { doc_sugestao: { resolvida: true } };
  if (aceitar) {
    patch.doc_status = { [sugestao.value.item.id]: 'recebido' };
    patch.doc_anexos = { [sugestao.value.item.id]: sugestao.value.attachment_id };
  }
  await store.dispatch('leads/update', { id: props.lead.id, custom_attributes: patch });
};
```

(O deep_merge do servidor completa o resto — mandar SÓ as chaves alteradas; reusar o guard `pendingIds`/loading local do componente pra evitar duplo clique. `statusFor` = o helper que o componente já usa pro ciclo; conferir o nome real.)

Template, acima da lista:

```html
<div v-if="sugestao" data-testid="doc-sugestao"
     class="flex items-center gap-2 rounded-lg bg-n-amber-9/10 px-3 py-2 text-n-amber-11">
  <span class="i-lucide-sparkles size-3.5" />
  <span class="text-xs">{{ $t('RAMON.DOCS.SUGESTAO.TEXTO', { item: sugestao.item.title || sugestao.item.content }) }}</span>
  <button data-testid="doc-sugestao-confirm" class="text-xs font-semibold underline" @click="resolverSugestao(true)">
    {{ $t('RAMON.DOCS.SUGESTAO.CONFIRMAR') }}
  </button>
  <button data-testid="doc-sugestao-dismiss" class="text-xs underline opacity-70" @click="resolverSugestao(false)">
    {{ $t('RAMON.DOCS.SUGESTAO.DISPENSAR') }}
  </button>
</div>
```

i18n `RAMON.DOCS.SUGESTAO`: `TEXTO` pt_BR `'Parece "{item}" — marcar como recebido?'` / en `'Looks like "{item}" — mark as received?'`; `CONFIRMAR` "Marcar recebido"/"Mark received"; `DISPENSAR` "Dispensar"/"Dismiss".

- [ ] **Step 4: Run — PASS** + eslint.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(ramon): confirmacao de 1 clique da sugestao anexo-item"
```

---

### Task 7: Ponte Drive — client + export incremental

Cada doc conferido COM anexo vinculado vira PDF renomeado em `Clientes/<Nome — CPF>/` + atalho do dia em `A enviar ao ADVBOX/<data>/` (ADR-0002). Checklist completo → pasta ganha sufixo `— COMPLETO`. Tudo atrás de `RAMON_DRIVE_*`; idempotente via `custom_attributes['drive']`.

**Files:**
- Modify: `Gemfile` (`google-apis-drive_v3`, `googleauth`, `prawn` — os 3 com `require: false` se o padrão do Gemfile pedir; rodar `bundle lock` pra atualizar o lockfile sem instalar tudo)
- Create: `lib/ramon/drive_client.rb`
- Create: `app/services/ramon/drive_export_service.rb`
- Create: `app/jobs/ramon/drive_export_job.rb`
- Modify: `app/models/lead.rb` (callback `enqueue_drive_export` junto dos callbacks de won ~:44-46)
- Test: `spec/services/ramon/drive_export_service_spec.rb` (2º e ÚLTIMO arquivo novo permitido; `Ramon::DriveClient` mockado)

**Interfaces:**
- Consumes: `doc_status`/`doc_anexos` (Tasks 3/6); `Lead#docs_counts`.
- Produces: `custom_attributes['drive'] = { 'pasta_id' => String, 'itens' => { '<item_id>' => file_id }, 'concluido_em' => iso8601 }`. `Ramon::DriveClient` com `configured?`, `ensure_folder(name, parent_id)`, `upload(name:, io:, content_type:, parent_id:)`, `shortcut(target_id:, name:, parent_id:)`, `rename(file_id, name)`. Task 8 roda dentro do fluxo de conclusão deste service.

- [ ] **Step 1: DriveClient**

```ruby
require 'google/apis/drive_v3'
require 'googleauth'

module Ramon
  # Ponte hub → Google Drive (ADR-0002). Service account: o Eduardo compartilha a
  # pasta-raiz com o e-mail da conta de serviço; sem as envs, feature desligada.
  class DriveClient
    FOLDER_MIME = 'application/vnd.google-apps.folder'.freeze
    SHORTCUT_MIME = 'application/vnd.google-apps.shortcut'.freeze

    class << self
      def configured?
        ENV.fetch('RAMON_DRIVE_CREDENTIALS', nil).present? && ENV.fetch('RAMON_DRIVE_ROOT_ID', nil).present?
      end

      def root_id = ENV.fetch('RAMON_DRIVE_ROOT_ID')

      # Acha (ou cria) subpasta pelo nome exato dentro do pai. Nome vai escapado na query.
      def ensure_folder(name, parent_id)
        q = "name = '#{name.gsub("'", "\\\\'")}' and '#{parent_id}' in parents " \
            "and mimeType = '#{FOLDER_MIME}' and trashed = false"
        existing = service.list_files(q: q, fields: 'files(id)').files.first
        return existing.id if existing

        service.create_file({ name: name, mime_type: FOLDER_MIME, parents: [parent_id] }, fields: 'id').id
      end

      def upload(name:, io:, content_type:, parent_id:)
        service.create_file({ name: name, parents: [parent_id] },
                            upload_source: io, content_type: content_type, fields: 'id').id
      end

      def shortcut(target_id:, name:, parent_id:)
        service.create_file({ name: name, mime_type: SHORTCUT_MIME, parents: [parent_id],
                              shortcut_details: { target_id: target_id } }, fields: 'id').id
      end

      def rename(file_id, name)
        service.update_file(file_id, { name: name }, fields: 'id')
      end

      private

      def service
        @service ||= Google::Apis::DriveV3::DriveService.new.tap do |s|
          s.authorization = Google::Auth::ServiceAccountCredentials.make_creds(
            json_key_io: File.open(ENV.fetch('RAMON_DRIVE_CREDENTIALS')),
            scope: 'https://www.googleapis.com/auth/drive'
          )
        end
      end
    end
  end
end
```

(Memoização de `@service` em singleton de classe vive por processo — ok, credencial não muda. Implementer: conferir a assinatura exata de `update_file` na gem.)

- [ ] **Step 2: Spec do export service (arquivo novo, DriveClient mockado)**

Casos mínimos: (a) sem env → `perform` retorna sem tocar o client (`expect(Ramon::DriveClient).not_to receive(:upload)`); (b) item `recebido` com anexo vinculado e ainda não exportado → upload + shortcut + `drive.itens` gravado; (c) item já em `drive.itens` → não re-exporta; (d) checklist completo → `rename` com `— COMPLETO` + `concluido_em` gravado + (Task 8) tarefa ADVBOX; (e) anexo png → conteúdo enviado é PDF (nome termina em `.pdf`).

- [ ] **Step 3: Export service**

```ruby
module Ramon
  # Export incremental do checklist pro Drive (ADR-0002). Idempotente: o que já
  # está em custom_attributes['drive']['itens'] nunca re-sobe; job pode re-rodar.
  class DriveExportService
    def initialize(lead)
      @lead = lead
    end

    def perform
      return unless DriveClient.configured?
      return if @lead.won_at.blank? || @lead.thesis_id.blank?

      pendentes_de_export.each { |item, attachment| exportar(item, attachment) }
      concluir if checklist_completo? && drive_state['concluido_em'].blank?
    end

    private

    def drive_state = @lead.custom_attributes&.dig('drive') || {}

    def doc_anexos = @lead.custom_attributes&.dig('doc_anexos') || {}

    def pendentes_de_export
      status = @lead.custom_attributes&.dig('doc_status') || {}
      exportados = drive_state['itens'] || {}
      @lead.thesis.thesis_items.where(section: 'documento').filter_map do |item|
        key = item.id.to_s
        next unless status[key] == 'recebido' && doc_anexos[key].present? && exportados[key].blank?

        attachment = Attachment.find_by(id: doc_anexos[key], account_id: @lead.account_id)
        attachment && [item, attachment]
      end
    end

    def exportar(item, attachment)
      nome_item = item.title.presence || item.content.truncate(60)
      pdf_io, content_type, ext = to_pdf(attachment)
      file_id = DriveClient.upload(name: "#{nome_item} — #{nome_cliente}#{ext}", io: pdf_io,
                                   content_type: content_type, parent_id: pasta_cliente_id)
      DriveClient.shortcut(target_id: file_id, name: "#{nome_cliente} — #{nome_item}#{ext}",
                           parent_id: pasta_do_dia_id)
      merge_drive('itens' => (drive_state['itens'] || {}).merge(item.id.to_s => file_id))
    end

    # jpg/png viram PDF de 1 página via prawn; PDF passa direto; heic/etc sobem
    # no formato original. ponytail: conversão além disso só se aparecer na prática.
    def to_pdf(attachment)
      bytes = attachment.file.download
      case attachment.file.content_type
      when 'application/pdf'
        [StringIO.new(bytes), 'application/pdf', '.pdf']
      when 'image/jpeg', 'image/jpg', 'image/png'
        doc = Prawn::Document.new(page_size: 'A4', margin: 24)
        doc.image StringIO.new(bytes), fit: [doc.bounds.width, doc.bounds.height]
        [StringIO.new(doc.render), 'application/pdf', '.pdf']
      else
        ext = File.extname(attachment.file.filename.to_s)
        [StringIO.new(bytes), attachment.file.content_type, ext]
      end
    end

    def nome_cliente
      @nome_cliente ||= (@lead.contact&.name.presence || @lead.name).to_s.strip
    end

    def pasta_cliente_id
      @pasta_cliente_id ||= drive_state['pasta_id'].presence || begin
        clientes = DriveClient.ensure_folder('Clientes', DriveClient.root_id)
        cpf = @lead.contact&.cpf
        id = DriveClient.ensure_folder([nome_cliente, cpf.presence].compact.join(' — '), clientes)
        merge_drive('pasta_id' => id)
        id
      end
    end

    def pasta_do_dia_id
      @pasta_do_dia_id ||= begin
        raiz = DriveClient.ensure_folder('A enviar ao ADVBOX', DriveClient.root_id)
        DriveClient.ensure_folder(Time.zone.today.iso8601, raiz)
      end
    end

    def checklist_completo?
      docs = @lead.docs_counts
      docs[:total].positive? && docs[:received] >= docs[:total]
    end

    def concluir
      DriveClient.rename(pasta_cliente_id, "#{pasta_nome_atual} — COMPLETO")
      merge_drive('concluido_em' => Time.zone.now.iso8601)
      Ramon::AdvboxDocsTaskService.new(@lead).perform # Task 8; no-op sem env
    end

    def pasta_nome_atual
      cpf = @lead.contact&.cpf
      [nome_cliente, cpf.presence].compact.join(' — ')
    end

    def merge_drive(patch)
      @lead.reload # padrão advbox_closing: merge só da chave 'drive' sobre estado fresco
      @lead.update!(custom_attributes: @lead.custom_attributes.to_h.merge(
        'drive' => drive_state.merge(patch)
      ))
    end
  end
end
```

(Implementer: conferir o nome real da coluna/método do CPF no contato — o levantamento mostrou `contact_cpf` no jbuilder, vindo de coluna RamonPessoa no Contact.)

- [ ] **Step 4: Job + callback**

```ruby
module Ramon
  class DriveExportJob < ApplicationJob
    queue_as :low
    retry_on Google::Apis::TransmissionError, Google::Apis::ServerError, wait: :polynomially_longer, attempts: 3

    def perform(lead_id)
      lead = Lead.find_by(id: lead_id)
      return if lead.blank?

      Ramon::DriveExportService.new(lead).perform
    end
  end
end
```

Em `lead.rb`, junto dos callbacks de ganho:

```ruby
after_update_commit :enqueue_drive_export, if: :saved_change_to_custom_attributes?

def enqueue_drive_export
  return if won_at.blank? || ENV.fetch('RAMON_DRIVE_CREDENTIALS', nil).blank?

  # Job barato e idempotente: o service filtra o que já subiu; disparar em todo
  # update de custom_attributes de lead ganho é aceitável e cobre o backlog
  # (docs recebidos antes do ganho sobem no 1º update pós-ganho).
  Ramon::DriveExportJob.perform_later(id)
end
```

Adicionar também `:enqueue_drive_export` na cadeia de `saved_change_to_won_at?` existente (`after_update_commit` de won ~:44-46) para o backlog subir no instante do ganho.

(Cuidado com loop: o job atualiza `custom_attributes` → re-dispara o callback → re-enfileira 1 job que não acha nada pendente e não escreve nada → para. Sem escrita, sem novo job — convergência em 1 rodada extra; deixar comentário no callback.)

- [ ] **Step 5: Rubocop + rspec** (specs do service; `bundle lock` limpo no CI).

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat(ramon): export incremental dos docs conferidos pro Drive"
```

---

### Task 8: Tarefa ADVBOX pra controller no pacote completo

Checklist completo + pasta renomeada → tarefa no ADVBOX pra controller subir os documentos. Atrás de `RAMON_ADVBOX_CONTROLLER_ID` + `RAMON_ADVBOX_DOCS_TASK_ID` + `ADVBOX_API_TOKEN`.

**Files:**
- Create: `app/services/ramon/advbox_docs_task_service.rb`
- Test: `spec/services/ramon/drive_export_service_spec.rb` (estender o describe da conclusão — NÃO criar 3º arquivo)

**Interfaces:**
- Consumes: `Ramon::AdvboxClient.create_post(payload)` (payload padrão de `advbox_closing_service.rb:125-134`: `from`/`tasks_id`/`lawsuits_id` strings, `guests` array de int); `custom_attributes['advbox']` gravado pela cascata de ganho (conferir a chave exata do lawsuit id em `AdvboxClosingService#step` — provavelmente `'lawsuit_id'`).
- Produces: `custom_attributes['drive']['advbox_task_id']` (idempotência).

- [ ] **Step 1: Estender o spec do DriveExportService** — no describe de conclusão: com envs setadas (`with_modified_env`) e `custom_attributes['advbox']` com lawsuit, `Ramon::AdvboxClient.create_post` recebe payload com `from` = controller id e `comments` mencionando o lead; sem env → não chama; segunda rodada (task id já gravado) → não chama de novo.

- [ ] **Step 2: Implementar**

```ruby
module Ramon
  # Pacote de documentos completo no Drive → tarefa no ADVBOX pra controller
  # fazer o upload manual (ADR-0002). Sem envs, no-op.
  class AdvboxDocsTaskService
    def initialize(lead)
      @lead = lead
    end

    def perform
      controller_id = ENV.fetch('RAMON_ADVBOX_CONTROLLER_ID', nil)
      task_type_id = ENV.fetch('RAMON_ADVBOX_DOCS_TASK_ID', nil)
      return if controller_id.blank? || task_type_id.blank? || ENV.fetch('ADVBOX_API_TOKEN', nil).blank?
      return if @lead.custom_attributes&.dig('drive', 'advbox_task_id').present?

      lawsuit_id = @lead.custom_attributes&.dig('advbox', 'lawsuit_id')
      return Rails.logger.warn("[Ramon::AdvboxDocsTaskService] lead=#{@lead.id} sem lawsuit no advbox") if lawsuit_id.blank?

      resp = Ramon::AdvboxClient.create_post(
        from: controller_id.to_s, guests: [controller_id.to_i],
        tasks_id: task_type_id.to_s, lawsuits_id: lawsuit_id.to_s,
        start_date: Time.zone.today.iso8601,
        comments: "Documentos completos no Drive (pasta \"#{pasta}\") — subir ao ADVBOX e apagar o atalho do dia. Lead ##{@lead.id}."
      )
      gravar(resp)
    rescue Ramon::AdvboxClient::RequestError => e
      Rails.logger.warn("[Ramon::AdvboxDocsTaskService] lead=#{@lead.id} advbox recusou: #{e.code}")
    end

    private

    def pasta
      nome = (@lead.contact&.name.presence || @lead.name).to_s.strip
      cpf = @lead.contact&.cpf
      "#{[nome, cpf.presence].compact.join(' — ')} — COMPLETO"
    end

    def gravar(resp)
      @lead.reload
      drive = (@lead.custom_attributes&.dig('drive') || {}).merge('advbox_task_id' => resp&.dig('id') || true)
      @lead.update!(custom_attributes: @lead.custom_attributes.to_h.merge('drive' => drive))
    end
  end
end
```

(`UnavailableError` NÃO é resgatado — sobe pro `DriveExportJob` re-tentar, padrão do closing service. Implementer: conferir a chave real do lawsuit em `AdvboxClosingService` e o shape do retorno de `create_post`.)

- [ ] **Step 3: Rubocop + rspec.**

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat(ramon): tarefa ADVBOX pra controller quando o pacote fecha"
```

---

## Self-Review (feito na escrita)

- **Cobertura da spec:** decisão 7 (visão Pós-venda + Concluído) → Task 4 + 7; decisão 8 sintomas 1–4 → Tasks 1, 2, 5+6, 3; decisão 9 (portal como apoio) → sem trabalho novo (upload do portal já vira mensagem incoming → passa pelo mesmo listener da Task 5 — cobre os dois caminhos de graça); decisão 10/ADR-0002 → Tasks 7 + 8. Fora de escopo confirmado: valor estimado/previsão/cabeça de coluna/views BI = Onda 3.
- **Tipos:** `docs_counts` → chaves símbolo `{received:, total:}` em todas as menções; `doc_sugestao`/`doc_anexos`/`drive` → chaves string (jsonb); `item_id` inteiro no `doc_sugestao`, string como chave em `doc_status`/`doc_anexos` (consistente com o `doc_status` existente).
- **Sem placeholder:** todo step de código tem o código; pontos que exigem conferência local do implementador estão marcados com "(conferir ...)" e nomeiam o arquivo exato.

## Gates do Eduardo (fora do código — listar no doc de smoke)

1. Criar service account no Google Cloud, baixar o JSON, compartilhar a pasta-raiz do Drive com o e-mail da conta, montar o JSON na VPS e setar `RAMON_DRIVE_CREDENTIALS` + `RAMON_DRIVE_ROOT_ID` no chatwoot.env.
2. Escolher os IDs do ADVBOX (via `advbox_configuracoes`): usuário da controller (`RAMON_ADVBOX_CONTROLLER_ID`) e tipo de tarefa (`RAMON_ADVBOX_DOCS_TASK_ID`).
3. Smoke das 3 ondas será testado JUNTO ao fim da Onda 3 (decisão 13/08) — o doc de smoke desta onda nasce com esse banner.
