# Onda C — Modos do Copiloto por Conversa — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Entregar o D5 da spec do redesign: 4 modos de copiloto POR CONVERSA (manual / rascunho / piloto_limitado / piloto_total), com seletor no topo da conversa, carimbo visível em toda mensagem enviada pelo piloto e pausa de 1 clique — Eduardo autorizou explicitamente os dois pilotos (spec D5, 14/08).

**Architecture:** O modo vive em `conversation.custom_attributes['copiloto_modo']` (broadcast `CONVERSATION_UPDATED` já inclui custom_attributes — front atualiza ao vivo de graça). O `Captain::Conversation::ResponseBuilderJob` consulta o modo em DOIS pontos: `perform` retorna cedo no modo manual (nem chama o LLM), e `create_outgoing_message` — o gate ÚNICO por onde resposta E handoff passam — decide rascunho×outgoing. `piloto_limitado` classifica "é logística?" via `Ramon::LlmClient` (DeepSeek, prompt-JSON sem json_schema, fail-safe = rascunho). Mensagem de piloto sai com `content_attributes['ramon_piloto']` (carimbo) e o front renderiza selo + botão Pausar (1 clique → rascunho).

**Tech Stack:** Rails (enterprise/ overlay do Captain), Vue 3 `<script setup>`, Tailwind tokens bronze, Vuex (`updateCustomAttributes` existente), vitest, RSpec (só CI).

**Spec:** `docs/superpowers/specs/2026-08-14-redesign-ux-copiloto-design.md` (D5 + Onda C + Guardrails) · Mockup: `comercial\docs\mockups\2026-08-14-redesign-material\conversa-v2-copiloto.html` (botão "✦ Copiloto: Rascunho ▾" nos chips do topo + popup com radios e descrições; carimbo = variante `.evento-auto.enviado` verde).

## Global Constraints

- **Modo padrão de TODA conversa: `rascunho`** (spec Guardrails). Chave ausente/valor inválido em `copiloto_modo` ⇒ comporta como rascunho. Piloto SÓ quando explicitamente escolhido na conversa.
- **Auto-resolver do Captain segue DESLIGADO** — esta onda NÃO toca em `captain_auto_resolve_*`, `InboxPendingConversationsResolutionJob` nem em `settings` da conta.
- **DeepSeek NÃO aceita json_schema** (lição PR #110; `agentable.rb:57-67`). Classificador usa prompt pedindo JSON + parse robusto (padrão `DocMatchService#parse_item_id`); `LlmClient.complete` não expõe response_format — NÃO mexer no LlmClient.
- **Fail-safe do piloto_limitado:** qualquer erro/dúvida do classificador (exceção, JSON inválido, resposta ambígua) ⇒ vira RASCUNHO, nunca envia. Na dúvida, não envia.
- **Handoff passa pelo mesmo gate:** em rascunho vira nota (comportamento atual); em piloto_limitado e piloto_total a mensagem de handoff PODE sair (é logística — hardcoded, sem classificador).
- **Carimbo obrigatório:** toda outgoing de piloto leva `content_attributes['ramon_piloto'] = { 'modo' =>, 'em' => iso8601 }` (chaves string). Front mostra selo "enviada pelo piloto" + Pausar.
- **Pausar (1 clique)** grava `copiloto_modo: 'rascunho'` na conversa.
- **⚠️ Endpoint `POST /conversations/:id/custom_attributes` SUBSTITUI o hash inteiro** (`conversations_controller.rb:136-139`) — o front SEMPRE manda `{ ...chat.custom_attributes, copiloto_modo: x }` mesclado.
- **Sem migração.** Sem tocar em dado de produção do assistente (config/instructions/response_guidelines são dado, não código).
- Nesta máquina não há Ruby (RSpec = CI); front testa `TZ=UTC ./node_modules/.bin/vitest --no-watch <path>`; eslint por arquivo com `./node_modules/.bin/eslint`; SEMPRE grep antes de "criar" spec; Tailwind tokens only; i18n pt_BR+en (`ramon.json`); eventos Vue camelCase; conventional commit; worktree novo precisa `pnpm install` real + junction `node_modules/postcss-import` → store `.pnpm` (lição Onda B).
- Arquivos do Captain vivem em `enterprise/` — manter overlay (não mover pra OSS).

---

### Task 1: Backend — modo por conversa + gate no ResponseBuilderJob + carimbo

**Files:**
- Create: `enterprise/lib/ramon/copiloto_modo.rb`
- Modify: `enterprise/app/jobs/captain/conversation/response_builder_job.rb` (`perform` :8-29, `create_outgoing_message` :169-183)
- Test: ESTENDER `spec/enterprise/jobs/captain/conversation/response_builder_job_spec.rb` (existe — tem exemplo de `ramon_modo_rascunho` na :213)

**Interfaces:**
- Consumes: `conversation.custom_attributes['copiloto_modo']`; `@assistant.modo_rascunho?` (fica como está — ver gate abaixo).
- Produces: `Ramon::CopilotoModo.of(conversation)` → um de `%w[manual rascunho piloto_limitado piloto_total]` (default `'rascunho'`); outgoing de piloto com `content_attributes['ramon_piloto']` = `{ 'modo' =>, 'em' => }`. **Tasks 2, 3 e 4 dependem desses contratos.**

- [ ] **Step 1: Testes que falham (estender o spec existente — ler o arquivo inteiro e reusar os `let`)**

```ruby
describe 'modos do copiloto por conversa (Onda C)' do
  def set_modo(modo)
    conversation.update!(custom_attributes: conversation.custom_attributes.to_h.merge('copiloto_modo' => modo))
  end

  it 'manual: não chama o LLM nem cria mensagem' do
    set_modo('manual')
    expect(Captain::Llm::AssistantChatService).not_to receive(:new)
    expect { described_class.perform_now(conversation, assistant) }
      .not_to change(conversation.messages, :count)
  end

  it 'rascunho (default, chave ausente): resposta vira nota privada RASCUNHO' do
    described_class.perform_now(conversation, assistant)
    nota = conversation.messages.last
    expect(nota).to have_attributes(private: true)
    expect(nota.content).to start_with('RASCUNHO')
  end

  it 'piloto_total: resposta sai outgoing pública com carimbo ramon_piloto' do
    set_modo('piloto_total')
    described_class.perform_now(conversation, assistant)
    msg = conversation.messages.last
    expect(msg).to have_attributes(message_type: 'outgoing', private: false)
    expect(msg.content_attributes['ramon_piloto']).to include('modo' => 'piloto_total')
  end

  it 'valor inválido em copiloto_modo comporta como rascunho' do
    set_modo('xablau')
    described_class.perform_now(conversation, assistant)
    expect(conversation.messages.last.private).to be(true)
  end
end
```

Adaptar aos stubs que o spec já usa pro `AssistantChatService`/resposta do LLM (ler como o exemplo `ramon_modo_rascunho` da :213 monta o cenário e seguir o MESMO padrão).

- [ ] **Step 2: Criar `Ramon::CopilotoModo`**

`enterprise/lib/ramon/copiloto_modo.rb`:

```ruby
# Modo do copiloto POR CONVERSA (Onda C, spec D5). Fonte única da leitura:
# custom_attributes['copiloto_modo'], default rascunho — piloto é opt-in
# explícito por conversa (decisão Eduardo 14/08).
module Ramon::CopilotoModo
  MODOS = %w[manual rascunho piloto_limitado piloto_total].freeze
  DEFAULT = 'rascunho'.freeze

  module_function

  def of(conversation)
    modo = conversation&.custom_attributes&.[]('copiloto_modo').to_s
    MODOS.include?(modo) ? modo : DEFAULT
  end

  def piloto?(modo)
    modo.start_with?('piloto_')
  end
end
```

- [ ] **Step 3: Gate no `ResponseBuilderJob`**

Em `perform` (:8-29), logo após o guard `conversation_pending?` existente:

```ruby
    @copiloto_modo = Ramon::CopilotoModo.of(@conversation)
    return if @copiloto_modo == 'manual' # IA quieta: nem gasta LLM
```

Em `create_outgoing_message` (:169-183), trocar a linha do rascunho por:

```ruby
  def create_outgoing_message(message_content, agent_name: nil, preserve_waiting_since: false)
    # Onda C: o modo POR CONVERSA decide. Rascunho continua sendo o default e
    # também o fallback do flag global antigo (assistant.modo_rascunho?).
    modo = @copiloto_modo || Ramon::CopilotoModo.of(@conversation)
    return create_draft_note(message_content) unless Ramon::CopilotoModo.piloto?(modo)
```

E no create do outgoing (:175-183), acrescentar o carimbo ao hash de atributos existente:

```ruby
      content_attributes: { 'ramon_piloto' => { 'modo' => modo, 'em' => Time.zone.now.iso8601 } },
```

⚠️ NÃO remover `modo_rascunho?` do assistant (fica como flag legado de console; com os modos por conversa o gate acima já cobre o caso — rascunho é default). Handoff (`:153-158`) passa pelo MESMO `create_outgoing_message` — comportamento desejado: em piloto sai como logística (constraint global), nada a mudar além do gate. A Task 2 restringe o piloto_limitado só pras respostas normais (o handoff não passa pelo classificador — ver flag `@handoff` lá).

- [ ] **Step 4: Conferir CI-style (linhas ≤150, sem Ruby local) e commit**

```bash
git add enterprise/lib/ramon/copiloto_modo.rb enterprise/app/jobs/captain/conversation/response_builder_job.rb spec/enterprise/jobs/captain/conversation/response_builder_job_spec.rb
git commit -m "feat(ramon): modos do copiloto por conversa no response builder (manual/rascunho/pilotos + carimbo)"
```

---

### Task 2: Backend — classificador de logística do piloto_limitado (fail-safe)

**Files:**
- Create: `app/services/ramon/piloto_logistica_service.rb`
- Create: `spec/services/ramon/piloto_logistica_service_spec.rb` (grep antes: `ls spec/services/ramon/ | grep piloto` — se não existir, criar)
- Modify: `enterprise/app/jobs/captain/conversation/response_builder_job.rb` (o gate da Task 1)
- Test: estender também `response_builder_job_spec.rb`

**Interfaces:**
- Consumes: `Ramon::LlmClient.complete(provider:, model:, system:, user:)` (`lib/ramon/llm_client.rb:25`); padrão de parse do `DocMatchService#parse_item_id`.
- Produces: `Ramon::PilotoLogisticaService.logistica?(texto)` → `true`/`false` — **false em QUALQUER erro** (fail-safe). Task 1 (gate) consome.

- [ ] **Step 1: Testes que falham**

```ruby
require 'rails_helper'

describe Ramon::PilotoLogisticaService do
  def result_with(content)
    Ramon::LlmClient::Result.new(content: content, input_tokens: 1, output_tokens: 1)
  end

  it 'true quando o LLM responde logistica true' do
    allow(Ramon::LlmClient).to receive(:complete).and_return(result_with('{"logistica": true}'))
    expect(described_class.logistica?('Bom dia! Consegue me mandar o PPP até amanhã?')).to be(true)
  end

  it 'false quando o LLM responde false' do
    allow(Ramon::LlmClient).to receive(:complete).and_return(result_with('{"logistica": false}'))
    expect(described_class.logistica?('Seu benefício deve sair em 30 dias')).to be(false)
  end

  it 'fail-safe: JSON inválido vira false' do
    allow(Ramon::LlmClient).to receive(:complete).and_return(result_with('acho que sim'))
    expect(described_class.logistica?('qualquer')).to be(false)
  end

  it 'fail-safe: exceção do LLM vira false' do
    allow(Ramon::LlmClient).to receive(:complete).and_raise(Ramon::LlmClient::TransientError)
    expect(described_class.logistica?('qualquer')).to be(false)
  end
end
```

- [ ] **Step 2: Implementar o serviço**

`app/services/ramon/piloto_logistica_service.rb`:

```ruby
# Piloto com limites (Onda C): decide se uma resposta do copiloto é PURA
# logística (cobrança de documento, confirmação de horário, mensagem de
# cadência) e portanto pode sair sozinha. Fail-safe: na dúvida ou em erro,
# false — a mensagem vira rascunho. DeepSeek sem json_schema (lição PR #110):
# JSON pedido no prompt + parse defensivo, padrão DocMatchService.
class Ramon::PilotoLogisticaService
  PROVIDER = 'deepseek'.freeze

  SYSTEM_PROMPT = <<~PROMPT.freeze
    Você audita a resposta que um assistente de escritório de advocacia quer enviar a um cliente.
    Ela só pode sair sozinha se for PURA logística: pedir/cobrar documento, confirmar ou propor
    horário, saudação/lembrete curto de acompanhamento. Se contiver QUALQUER análise do caso,
    valor, honorário, prazo do INSS, promessa ou orientação jurídica, NÃO é logística.
    Responda APENAS um JSON válido (sem markdown): {"logistica": true} ou {"logistica": false}.
    Na dúvida, responda false.
  PROMPT

  def self.logistica?(texto)
    result = Ramon::LlmClient.complete(
      provider: PROVIDER, model: ENV.fetch('RAMON_COPILOT_MODEL', 'deepseek-chat'),
      system: SYSTEM_PROMPT, user: "Resposta a auditar:\n#{texto}"
    )
    parsed = JSON.parse(result.content.to_s.sub(/\A```(?:json)?\s*/, '').sub(/```\s*\z/, ''))
    parsed.is_a?(Hash) && parsed['logistica'] == true
  rescue StandardError => e
    Rails.logger.warn("[Ramon::PilotoLogisticaService] fail-safe rascunho (#{e.class}: #{e.message})")
    false
  end
end
```

- [ ] **Step 3: Ligar no gate (Task 1) — só pra resposta normal, handoff não classifica**

No `create_outgoing_message`, o gate da Task 1 vira:

```ruby
    modo = @copiloto_modo || Ramon::CopilotoModo.of(@conversation)
    return create_draft_note(message_content) unless Ramon::CopilotoModo.piloto?(modo)

    if modo == 'piloto_limitado' && !@enviando_handoff && !Ramon::PilotoLogisticaService.logistica?(message_content)
      return create_draft_note(message_content)
    end
```

E em `perform_handoff`/caminho do handoff (`:153-158`): setar `@enviando_handoff = true` imediatamente antes da chamada a `create_outgoing_message` do handoff (e nada mais) — handoff é logística por definição (constraint global).

- [ ] **Step 4: Testes de integração no `response_builder_job_spec.rb`**

```ruby
  it 'piloto_limitado: logística sai, não-logística vira rascunho' do
    set_modo('piloto_limitado')
    allow(Ramon::PilotoLogisticaService).to receive(:logistica?).and_return(false)
    described_class.perform_now(conversation, assistant)
    expect(conversation.messages.last.private).to be(true)
  end
```

(+ o espelho com `true` esperando outgoing com carimbo `'modo' => 'piloto_limitado'`.)

- [ ] **Step 5: Commit**

```bash
git add app/services/ramon/piloto_logistica_service.rb spec/services/ramon/piloto_logistica_service_spec.rb enterprise/app/jobs/captain/conversation/response_builder_job.rb spec/enterprise/jobs/captain/conversation/response_builder_job_spec.rb
git commit -m "feat(ramon): classificador de logistica fail-safe do piloto limitado"
```

---

### Task 3: Front — seletor de modo no topo da conversa

**Files:**
- Create: `app/javascript/dashboard/routes/dashboard/ramon/components/conversation/CopilotoModoSelector.vue`
- Create: `.../conversation/specs/CopilotoModoSelector.spec.js`
- Modify: `app/javascript/dashboard/components/widgets/conversation/ConversationHeader.vue` (bloco :165-178, junto do LeadPanelToggle)
- Modify: `pt_BR/ramon.json` + `en/ramon.json` (bloco `RAMON.COPILOTO`)

**Interfaces:**
- Consumes: getter `getSelectedChat`; action `updateCustomAttributes` (`store/modules/conversations/actions.js:475-491`; ⚠️ backend SUBSTITUI o hash — sempre mandar merge completo).
- Produces: seletor que grava `copiloto_modo`; Task 4 consome os mesmos textos i18n do bloco `RAMON.COPILOTO`.

- [ ] **Step 1: Teste que falha**

`CopilotoModoSelector.spec.js` (seguir o padrão de mount do `LeadFollowUpBanner.spec.js`, que mocka `getSelectedChat`):

```js
// casos: (1) botão mostra o modo atual (default Rascunho quando sem chave);
// (2) abrir popup lista os 4 modos com descrições; (3) escolher "Piloto total"
// dispara conversations/updateCustomAttributes com o hash MESCLADO
// { ...custom_attributes, copiloto_modo: 'piloto_total' }; (4) broadcast que
// muda custom_attributes muda o rótulo do botão (reatividade via getter).
```

Escrever os 4 `it` com asserts reais (dispatch payload exato no caso 3 — é a proteção contra o replace do backend).

- [ ] **Step 2: Implementar o componente**

Estrutura (estilo do mockup: botão pílula "✦ Copiloto: <modo> ▾" + popup card com 4 opções radio, descrições e a nota de guardrail no piloto_limitado):

```vue
<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';

defineOptions({ name: 'CopilotoModoSelector' });
const { t } = useI18n();
const store = useStore();
const currentChat = useMapGetter('getSelectedChat');

const MODOS = ['manual', 'rascunho', 'piloto_limitado', 'piloto_total'];
const open = ref(false);
const saving = ref(false);

const modo = computed(() => {
  const m = currentChat.value?.custom_attributes?.copiloto_modo;
  return MODOS.includes(m) ? m : 'rascunho';
});

const escolher = async novo => {
  if (saving.value || novo === modo.value) return;
  saving.value = true;
  try {
    // backend SUBSTITUI o hash: mandar sempre o merge completo
    await store.dispatch('updateCustomAttributes', {
      conversationId: currentChat.value.id,
      customAttributes: {
        ...(currentChat.value.custom_attributes || {}),
        copiloto_modo: novo,
      },
    });
    open.value = false;
  } finally {
    saving.value = false;
  }
};
</script>
```

Template: botão `data-testid="copiloto-modo-btn"` (pílula `rounded-full bg-n-iris-9/10 text-n-iris-11 text-xs px-2 py-1`, label `✦ {{ t('RAMON.COPILOTO.BTN', { modo: t(\`RAMON.COPILOTO.MODOS.${modo}.NOME\`) }) }} ▾`); popup `v-if="open"` absoluto (`absolute right-0 top-9 z-50 w-80 rounded-xl border border-n-weak bg-n-solid-1 shadow-lg p-3`) com um `<button data-testid="copiloto-modo-opcao-<modo>">` por modo mostrando NOME + DESC (e no piloto_limitado também `NOTA` em texto menor `text-n-slate-10`); fechar com `onClickOutside`-like simples (`@click` num overlay `fixed inset-0` atrás do popup). Sem novo CSS — Tailwind tokens.

i18n (`pt_BR/ramon.json`, bloco novo `RAMON.COPILOTO` — textos do mockup, aprovados):

```json
"COPILOTO": {
  "BTN": "Copiloto: {modo}",
  "TITULO": "Modo do copiloto — só nesta conversa",
  "MODOS": {
    "manual": { "NOME": "Manual", "DESC": "A IA não sugere nada. Você escreve tudo." },
    "rascunho": { "NOME": "Rascunho", "DESC": "A IA prepara respostas; nada sai sem você apertar Enviar." },
    "piloto_limitado": { "NOME": "Piloto com limites", "DESC": "A IA envia sozinha SÓ mensagens de logística: cobrança de documentos, confirmação de horário, mensagem de cadência.", "NOTA": "Nunca envia: valores, análise do caso, promessas. Toda mensagem enviada fica marcada na conversa e você pode pausar com 1 clique." },
    "piloto_total": { "NOME": "Piloto total", "DESC": "A IA responde tudo sozinha. Toda mensagem fica carimbada e você pode pausar com 1 clique." }
  },
  "CARIMBO": "enviada pelo piloto ({modo})",
  "PAUSAR": "Pausar piloto",
  "PAUSADO": "Piloto pausado — voltou pro modo Rascunho."
}
```

(espelhar em `en/ramon.json` com traduções diretas).

- [ ] **Step 3: Montar no `ConversationHeader.vue`**

Ao lado do `<LeadPanelToggle />` (:174): `<CopilotoModoSelector v-if="currentChat.id" />` + import. Container do popup precisa `relative` — envolver num `<div class="relative">`.

- [ ] **Step 4: vitest verde + eslint + commit**

```bash
TZ=UTC ./node_modules/.bin/vitest --no-watch app/javascript/dashboard/routes/dashboard/ramon/components/conversation
git add -A app/javascript
git commit -m "feat(ramon): seletor de modo do copiloto por conversa no topo"
```

---

### Task 4: Front — carimbo "enviada pelo piloto" na bolha + Pausar 1 clique

**Files:**
- Create: `app/javascript/dashboard/components-next/message/PilotoCarimbo.vue`
- Create: spec ao lado dos specs de message existentes (grep `ls app/javascript/dashboard/components-next/message/**/*.spec.js` primeiro; se a pasta não tem specs, criar `.../message/specs/PilotoCarimbo.spec.js`)
- Modify: `app/javascript/dashboard/components-next/message/Message.vue` (renderizar o carimbo sob a bolha outgoing quando `contentAttributes.ramonPiloto` presente)

**Interfaces:**
- Consumes: `content_attributes['ramon_piloto']` da Task 1 (camelizado: `ramonPiloto = { modo, em }`); i18n `RAMON.COPILOTO.CARIMBO/PAUSAR/PAUSADO` da Task 3; action `updateCustomAttributes` (mesmo merge-completo da Task 3).
- Produces: nada consumido por outras tasks.

- [ ] **Step 1: Teste que falha** — casos: (1) carimbo renderiza com o modo traduzido quando `ramonPiloto` presente; (2) clique em Pausar dispara `updateCustomAttributes` com merge completo + `copiloto_modo: 'rascunho'` e mostra alerta `PAUSADO`; (3) sem `ramonPiloto` não renderiza nada. Mock igual ao RamonEvent (getSelectedChat + dispatch).

- [ ] **Step 2: Implementar `PilotoCarimbo.vue`**

```vue
<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useMessageContext } from './provider.js';

defineOptions({ name: 'PilotoCarimbo' });
const { t } = useI18n();
const store = useStore();
const currentChat = useMapGetter('getSelectedChat');
const { contentAttributes } = useMessageContext();

const piloto = computed(() => contentAttributes.value?.ramonPiloto || null);
const pausando = ref(false);
const aindaEmPiloto = computed(() =>
  (currentChat.value?.custom_attributes?.copiloto_modo || '').startsWith('piloto_')
);

const pausar = async () => {
  if (pausando.value) return;
  pausando.value = true;
  try {
    await store.dispatch('updateCustomAttributes', {
      conversationId: currentChat.value.id,
      customAttributes: {
        ...(currentChat.value.custom_attributes || {}),
        copiloto_modo: 'rascunho',
      },
    });
    useAlert(t('RAMON.COPILOTO.PAUSADO'));
  } finally {
    pausando.value = false;
  }
};
</script>

<template>
  <div
    v-if="piloto"
    data-testid="piloto-carimbo"
    class="mt-0.5 flex items-center gap-2 self-end text-[10.5px] text-n-teal-11"
  >
    <span>✦ {{ t('RAMON.COPILOTO.CARIMBO', { modo: t(`RAMON.COPILOTO.MODOS.${piloto.modo}.NOME`) }) }}</span>
    <button
      v-if="aindaEmPiloto"
      type="button"
      data-testid="piloto-pausar"
      class="font-semibold underline disabled:opacity-50"
      :disabled="pausando"
      @click="pausar"
    >
      {{ t('RAMON.COPILOTO.PAUSAR') }}
    </button>
  </div>
</template>
```

- [ ] **Step 3: Ligar no `Message.vue`** — dentro do container da bolha (ramo NÃO-activity), após o componente da bolha, renderizar `<PilotoCarimbo v-if="contentAttributes.ramonPiloto" />` (import junto dos outros). Ler o template em volta do `componentToRender` pra achar o ponto onde o meta/status da mensagem renderiza e posicionar o carimbo logo abaixo, alinhado à direita (mensagem outgoing).

- [ ] **Step 4: vitest + eslint + commit**

```bash
git add -A app/javascript
git commit -m "feat(ramon): carimbo 'enviada pelo piloto' com pausa de 1 clique"
```

---

## Self-Review (feito na escrita)

- **Cobertura do escopo da Onda C (spec :80-81):** seletor 4 modos → Task 3; carimbo → Tasks 1+4; pausa 1 clique → Task 4; classificador de logística → Task 2. Coach/termômetro/risco/qualificação = Onda D (fora). Auto-resolver intocado (constraint).
- **Consistência de tipos:** `copiloto_modo` string ∈ MODOS (backend `CopilotoModo.of` ↔ front `MODOS` array); `ramon_piloto`/`ramonPiloto` `{modo, em}`; merge-completo do custom_attributes nas DUAS escritas do front (Tasks 3 e 4 — mesmo shape).
- **Fail-safe provado por teste:** classificador com 4 specs (true/false/JSON-inválido/exceção); modo inválido → rascunho (spec da Task 1).
- **Handoff:** decidido e testável — passa pelo gate, não passa pelo classificador (flag `@enviando_handoff`). Sem isso, um handoff em piloto_limitado gastaria classificador à toa e poderia virar nota órfã.
- **Sem placeholder:** único step com prosa em vez de código é o Step 1 das Tasks 3/4 (casos de teste enumerados com asserts nomeados) — o implementer escreve os `it` seguindo o padrão do spec vizinho citado; todos os valores exatos (chaves, payloads, testids, i18n) estão no plano.
