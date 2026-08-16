# Onda D — Copiloto Proativo — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Entregar a Onda D da spec do redesign (D4 proativo): coach de objeção em tempo real na conversa, termômetro da conversa, alerta de risco de esfriar com atalho pra retomada W4, e qualificação da tese ao vivo (N/M com "perguntar →").

**Architecture:** Coach = novo gatilho de LLM em texto incoming (`RamonLeadListener` → `Ramon::CoachObjecaoJob` → `Ramon::CoachObjecaoService`), que ao detectar objeção emite um **evento inline** via `Ramon::EventoInline` (`ramon_event: 'coach'`) com 2 opções do playbook; o front estende a bolha `RamonEvent` pra renderizar as opções com "Usar →" (bus `INSERT_INTO_NORMAL_EDITOR` — nada é enviado, só cai no editor). Termômetro = heurística SEM LLM no front (gaps das mensagens já carregadas + `lead.stalled`). Risco de esfriar = cartão no painel quando `stalled`, com botão que enfileira `Ramon::FollowUpDraftJob` por lead (novo `perform_for` público com os mesmos guards). Qualificação viva = cartão N/M sobre `thesis_items(section: 'qualificacao')` com status manual em `custom_attributes['qualificacao_status']` (padrão `doc_status`) e "perguntar →" no editor.

**Tech Stack:** Rails, Vue 3 `<script setup>`, Tailwind tokens, Vuex, vitest, RSpec (só CI).

**Spec:** `docs/superpowers/specs/2026-08-14-redesign-ux-copiloto-design.md` (D4 + Onda D) · Mockup: `comercial\docs\mockups\2026-08-14-redesign-material\conversa-v2-copiloto.html` (coach :166-174, risco :199-203, termômetro :205-212, qualificação :214-222).

## Global Constraints

- **Princípio de aprovação intocado:** NADA desta onda envia mensagem ao cliente. "Usar →" só insere no editor; a retomada W4 nasce nota RASCUNHO (comportamento existente do FollowUpDraftService); eventos inline são internos por construção.
- **OAB-safe nos prompts:** coach nunca produz texto com promessa de resultado/valor/prazo do INSS — o system prompt manda explicitamente e reusa a receita do `ConversationCopilotService::DRAFT_SYSTEM_PROMPT` (concordar → amenizar → contornar → avançar).
- **DeepSeek sem json_schema** — JSON pedido no prompt + parse defensivo (padrão `DocMatchService#parse_item_id`). `LlmClient` intocado.
- **Custo do coach controlado:** roda só em incoming COM texto (≥ 20 chars), lead com tese, e com gap mínimo de 10 minutos desde o último coach da conversa (`custom_attributes['coach']['ultima_em']` no lead, reload+merge só da chave). Falha de LLM = silêncio (log), nunca erro visível.
- **Sem migração; sem modelo novo.** Coach viaja como activity message (`Ramon::EventoInline`); estados novos em custom_attributes do lead (`coach`, `qualificacao_status`).
- **`custom_attributes` do lead:** sempre `lead.reload` + merge só da chave nova (lição lost update); front PATCH manda só a chave alterada (leads_controller faz deep_merge — diferente do endpoint de CONVERSA, que substitui).
- **Onda C corre em paralelo** (branch feat/onda-c-modos-copiloto): esta onda NÃO toca `ResponseBuilderJob`, `ConversationHeader.vue`, nem cria bloco i18n `RAMON.COPILOTO`. Conflito esperado só em `ramon.json` (blocos distintos) — resolve no rebase.
- Nesta máquina não há Ruby (RSpec = CI); front: `TZ=UTC ./node_modules/.bin/vitest --no-watch <path>`; eslint por arquivo; grep antes de criar spec; Tailwind tokens; i18n pt_BR+en; camelCase; conventional commit; worktree novo = `pnpm install` real (`npx pnpm@10.2.0`) + junction `node_modules/postcss-import` → store `.pnpm`.

---

### Task 1: Backend — coach de objeção (service + job + gatilho no listener)

**Files:**
- Create: `app/services/ramon/coach_objecao_service.rb`
- Create: `app/jobs/ramon/coach_objecao_job.rb`
- Modify: `app/listeners/ramon_lead_listener.rb` (método `message_created`, :25-37)
- Test: Create `spec/services/ramon/coach_objecao_service_spec.rb` + estender `spec/listeners/ramon_lead_listener_spec.rb` (grep antes; o spec do listener EXISTE — confirmar com `ls spec/listeners/`)

**Interfaces:**
- Consumes: `Ramon::LlmClient.complete` (`lib/ramon/llm_client.rb:25`); `Ramon::EventoInline.registrar(conversation, texto, tipo:, extra:)` (`app/services/ramon/evento_inline.rb:11-21`); `thesis_items(section: 'objecao')` (`app/models/thesis_item.rb:2`); `Ramon::Pseudonymizer.mask`.
- Produces: activity com `content_attributes` = `{ 'ramon_event' => 'coach', 'objecao' => <rótulo>, 'opcoes' => [{'titulo' =>, 'texto' =>}, ...] }` (chaves string, JSON-nativo — Sidekiq strict_args). **Task 2 consome exatamente esse shape (camelizado: `ramonEvent`/`objecao`/`opcoes[].titulo/texto`).**

- [ ] **Step 1: Testes que falham**

`spec/services/ramon/coach_objecao_service_spec.rb`:

```ruby
require 'rails_helper'

describe Ramon::CoachObjecaoService do
  let(:account) { create(:account) }
  let(:thesis) { create(:thesis, account: account) }
  let!(:objecao_item) do
    create(:thesis_item, thesis: thesis, section: 'objecao',
                         title: 'Advogado é caro', content: 'A análise é gratuita e o honorário é no êxito.')
  end
  let(:conversation) { create(:conversation, account: account) }
  let(:lead) { create(:lead, account: account, conversation: conversation, thesis: thesis) }
  let(:message) do
    create(:message, account: account, conversation: conversation, message_type: :incoming,
                     content: 'minha vizinha pagou caro e o INSS negou, vou pensar mais um pouco')
  end

  def llm(content)
    Ramon::LlmClient::Result.new(content: content, input_tokens: 1, output_tokens: 1)
  end

  it 'objeção detectada → registra evento coach com 2 opções e grava ultima_em' do
    allow(Ramon::LlmClient).to receive(:complete).and_return(
      llm('{"objecao": "custo", "opcoes": [{"titulo": "Segurança primeiro", "texto": "..."}, {"titulo": "Prova concreta", "texto": "..."}]}')
    )
    expect { described_class.new(message, lead).perform }
      .to have_enqueued_job(Conversations::ActivityMessageJob).with(
        conversation,
        hash_including(content_attributes: hash_including('ramon_event' => 'coach', 'objecao' => 'custo'))
      )
    expect(lead.reload.custom_attributes.dig('coach', 'ultima_em')).to be_present
  end

  it 'sem objeção ({"objecao": "nenhuma"}) → não registra evento nem grava coach' do
    allow(Ramon::LlmClient).to receive(:complete).and_return(llm('{"objecao": "nenhuma"}'))
    expect { described_class.new(message, lead).perform }
      .not_to have_enqueued_job(Conversations::ActivityMessageJob)
  end

  it 'fail-safe: JSON inválido/exceção → silêncio' do
    allow(Ramon::LlmClient).to receive(:complete).and_raise(Ramon::LlmClient::TransientError)
    expect { described_class.new(message, lead).perform }.not_to raise_error
  end

  it 'gap mínimo: coach há menos de 10 min → não roda o LLM' do
    lead.update!(custom_attributes: lead.custom_attributes.merge('coach' => { 'ultima_em' => 2.minutes.ago.iso8601 }))
    expect(Ramon::LlmClient).not_to receive(:complete)
    described_class.new(message, lead).perform
  end
end
```

(Adaptar as factories aos nomes reais — grep `create(:thesis_item` e `create(:lead` nos specs existentes e copiar o setup do `doc_match_service_spec.rb`, que já monta lead+conversa+tese.)

No spec do listener, adicionar: incoming com texto e lead com tese → `have_enqueued_job(Ramon::CoachObjecaoJob)`; incoming curta (< 20 chars) → não enfileira.

- [ ] **Step 2: Implementar o serviço**

`app/services/ramon/coach_objecao_service.rb`:

```ruby
# Coach de objeção em tempo real (Onda D, spec D4): mensagem incoming com
# texto → LLM decide se há objeção e monta 2 linhas de resposta a partir do
# playbook da tese (thesis_items section 'objecao'). O resultado vira evento
# inline na conversa ("Usar →" só INSERE no editor — princípio de aprovação).
# Fail-safe: qualquer erro = silêncio. Gap mínimo de 10 min por conversa.
class Ramon::CoachObjecaoService
  PROVIDER = 'deepseek'.freeze
  GAP_MINUTOS = 10
  MIN_CHARS = 20

  SYSTEM_PROMPT = <<~PROMPT.freeze
    Você é coach de fechamento de um escritório previdenciário. Recebe a última mensagem de um
    cliente e o playbook de objeções da tese. Se a mensagem contiver uma OBJEÇÃO (custo,
    desconfiança, tempo, "vou pensar", medo de perder), monte exatamente 2 opções de resposta
    curtas (estilo WhatsApp, 2-3 frases), seguindo a receita: concordar → amenizar → contornar →
    avançar. Use os argumentos do playbook quando servirem.
    Regras obrigatórias: NUNCA prometa resultado do caso, valor ou prazo do INSS (regra da OAB).
    Responda APENAS JSON válido (sem markdown):
    {"objecao": "<rótulo curto>", "opcoes": [{"titulo": "...", "texto": "..."}, {"titulo": "...", "texto": "..."}]}
    ou {"objecao": "nenhuma"} se não houver objeção. Na dúvida, "nenhuma".
  PROMPT

  def initialize(message, lead)
    @message = message
    @lead = lead
  end

  def perform
    return if @message.content.to_s.strip.length < MIN_CHARS
    return if recente?

    parsed = ask_llm
    return if parsed.blank? || parsed['objecao'].blank? || parsed['objecao'] == 'nenhuma'

    opcoes = Array(parsed['opcoes']).first(2).filter_map do |o|
      next if o['texto'].blank?

      { 'titulo' => o['titulo'].to_s.presence || 'Opção', 'texto' => o['texto'].to_s }
    end
    return if opcoes.empty?

    registrar_evento(parsed['objecao'].to_s, opcoes)
    marcar_ultima_em
  rescue StandardError => e
    Rails.logger.warn("[Ramon::CoachObjecaoService] silêncio (#{e.class}: #{e.message}) message=#{@message.id}")
  end

  private

  def recente?
    ultima = @lead.custom_attributes.dig('coach', 'ultima_em')
    ultima.present? && Time.zone.parse(ultima.to_s) > GAP_MINUTOS.minutes.ago
  rescue ArgumentError
    false
  end

  def ask_llm
    playbook = @lead.thesis.thesis_items.where(section: 'objecao')
                    .map { |i| "- #{i.title}: #{i.content}" }.join("\n")
    texto = Ramon::Pseudonymizer.mask(@message.content.to_s, names: [@lead.name, @lead.contact&.name].compact)
    result = Ramon::LlmClient.complete(
      provider: PROVIDER, model: ENV.fetch('RAMON_COPILOT_MODEL', 'deepseek-chat'),
      system: SYSTEM_PROMPT,
      user: "Playbook de objeções:\n#{playbook}\n\nMensagem do cliente:\n#{texto}"
    )
    parsed = JSON.parse(result.content.to_s.sub(/\A```(?:json)?\s*/, '').sub(/```\s*\z/, ''))
    parsed.is_a?(Hash) ? parsed : nil
  rescue JSON::ParserError
    nil
  end

  def registrar_evento(objecao, opcoes)
    Ramon::EventoInline.registrar(
      @message.conversation,
      "⚡ Coach do hub: objeção detectada (#{objecao}) — 2 respostas prontas do playbook.",
      tipo: 'coach',
      extra: { 'objecao' => objecao, 'opcoes' => opcoes }
    )
  end

  # lição lost update: reload + merge só da chave coach
  def marcar_ultima_em
    @lead.reload
    @lead.update!(custom_attributes: @lead.custom_attributes.to_h.merge(
      'coach' => { 'ultima_em' => Time.zone.now.iso8601 }
    ))
  end
end
```

- [ ] **Step 3: Job + gatilho no listener**

`app/jobs/ramon/coach_objecao_job.rb`:

```ruby
class Ramon::CoachObjecaoJob < ApplicationJob
  queue_as :low
  retry_on Ramon::LlmClient::TransientError, wait: 30.seconds, attempts: 2

  def perform(message_id)
    message = Message.find_by(id: message_id)
    return if message.blank?

    lead = message.account.leads.find_by(conversation_id: message.conversation_id)
    return if lead.blank? || lead.thesis_id.blank?

    Ramon::CoachObjecaoService.new(message, lead).perform
  end
end
```

No `ramon_lead_listener.rb#message_created`, junto do enqueue do DocMatch (:36), adicionar:

```ruby
    Ramon::CoachObjecaoJob.perform_later(message.id) if message.content.to_s.strip.length >= 20
```

(usar a MESMA guarda de incoming/lead que o método já tem; não duplicar lookups — ler o método atual e encaixar no fluxo existente.)

- [ ] **Step 4: Commit**

```bash
git add app/services/ramon/coach_objecao_service.rb app/jobs/ramon/coach_objecao_job.rb app/listeners/ramon_lead_listener.rb spec/
git commit -m "feat(ramon): coach de objecao em tempo real via evento inline (fail-safe)"
```

---

### Task 2: Front — opções do coach na bolha RamonEvent ("Usar →")

**Files:**
- Modify: `app/javascript/dashboard/components-next/message/bubbles/RamonEvent.vue`
- Test: estender o spec da bolha se existir (grep `grep -rl "RamonEvent" app/javascript --include="*.spec.js"`); senão criar `.../bubbles/specs/RamonEvent.spec.js` seguindo o padrão de mock do `useDocSugestao.spec.js`
- Modify: `pt_BR/ramon.json` + `en/ramon.json` (bloco `RAMON.COACH`)

**Interfaces:**
- Consumes: `contentAttributes` camelizado da Task 1: `ramonEvent === 'coach'`, `objecao`, `opcoes[] = [{titulo, texto}]`; bus `emitter.emit(BUS_EVENTS.INSERT_INTO_NORMAL_EDITOR, texto)` (assinatura exata: 1 arg string — `LeadCopilot.vue:35`).
- Produces: nada consumido por outras tasks.

- [ ] **Step 1: Teste que falha** — casos: (1) evento coach renderiza as 2 opções (titulo + texto) com botão `data-testid="coach-usar"`; (2) clique em "Usar →" emite `insertIntoNormalEditor` com o TEXTO da opção e mostra alerta `RAMON.COACH.USADO`; (3) evento não-coach (doc_match) não renderiza opções. Mock do emitter: `vi.mock('shared/helpers/mitt', () => ({ emitter: { emit: vi.fn() } }))`.

- [ ] **Step 2: Implementar** — em `RamonEvent.vue`, adicionar:

```js
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { useAlert } from 'dashboard/composables';

const isCoach = computed(() => contentAttributes.value?.ramonEvent === 'coach');
const opcoes = computed(() => (isCoach.value ? contentAttributes.value?.opcoes || [] : []));

const usar = opcao => {
  emitter.emit(BUS_EVENTS.INSERT_INTO_NORMAL_EDITOR, opcao.texto);
  useAlert(t('RAMON.COACH.USADO'));
};
```

Template (depois do bloco de ações do doc_match, mesmo container centrado; estilo do mockup `.opcao` com tokens):

```vue
    <div v-if="opcoes.length" class="mt-2 flex flex-col gap-1.5 text-left">
      <button
        v-for="(opcao, index) in opcoes"
        :key="index"
        type="button"
        data-testid="coach-usar"
        class="flex items-start gap-2 rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-xs text-n-slate-12 hover:border-n-iris-9"
        @click="usar(opcao)"
      >
        <span class="min-w-0"><b>{{ opcao.titulo }}:</b> {{ opcao.texto }}</span>
        <span class="ml-auto shrink-0 font-bold text-n-iris-11">{{ $t('RAMON.COACH.USAR') }}</span>
      </button>
    </div>
```

(`useI18n` já está disponível? — conferir o script atual da bolha; se só usa `$t` no template, importar `useI18n` pro `usar`.) i18n: `RAMON.COACH = { "USAR": "Usar →", "USADO": "Resposta inserida no editor — revise antes de enviar." }` (en: "Use →" / "Reply inserted in the editor — review before sending.").

- [ ] **Step 3: vitest + eslint + commit**

```bash
TZ=UTC ./node_modules/.bin/vitest --no-watch app/javascript/dashboard/components-next/message
git add -A app/javascript
git commit -m "feat(ramon): opcoes do coach com usar-na-reply-box na bolha de evento"
```

---

### Task 3: Backend — retomada W4 sob demanda (1 lead)

**Files:**
- Modify: `app/services/ramon/follow_up_draft_service.rb` (expor `perform_for(lead)` público; `draft_for` continua privado)
- Create: `app/jobs/ramon/follow_up_draft_job.rb`
- Modify: `app/controllers/api/v1/accounts/leads_controller.rb` + `config/routes.rb` (member `post :follow_up_draft`)
- Modify: `app/javascript/dashboard/api/leads.js` + store `leads` (action `followUpDraft`)
- Test: estender `spec/services/ramon/follow_up_draft_service_spec.rb` + spec de request do leads_controller (grep o arquivo de request specs existente)

**Interfaces:**
- Consumes: guards existentes `eligible?` (:40-54) e `draft_for` (:56-68) — intocados.
- Produces: `Ramon::FollowUpDraftService#perform_for(lead)` → true/false (false quando inelegível); rota `POST /api/v1/accounts/:account_id/leads/:id/follow_up_draft` → 202; action Vuex `leads/followUpDraft(leadId)`. **Task 4 consome a action.**

- [ ] **Step 1: Testes que falham**

No spec do service:

```ruby
  describe '#perform_for' do
    it 'gera rascunho pra 1 lead elegível (nota + task + evento) e retorna true' do
      expect(described_class.new(account: account).perform_for(stalled_lead)).to be(true)
      expect(stalled_lead.lead_notes.last.body).to include('RASCUNHO')
      expect(stalled_lead.lead_tasks.open_tasks.where(kind: 'follow_up')).to exist
    end

    it 'lead inelegível (task follow_up aberta) → false e nada criado' do
      stalled_lead.lead_tasks.create!(account: account, kind: 'follow_up', title: 'x', due_at: 1.day.from_now)
      expect { expect(described_class.new(account: account).perform_for(stalled_lead)).to be(false) }
        .not_to change(stalled_lead.lead_notes, :count)
    end
  end
```

(adaptar `stalled_lead` ao let existente do arquivo). Request spec: POST da rota nova → 202 e job enfileirado; agente sem acesso → mesmo status dos endpoints ramon vizinhos (copiar o padrão do `lead_colheitas` request spec, que já existe — grep).

- [ ] **Step 2: Implementar**

No `FollowUpDraftService`, acima do `private`:

```ruby
  # Retomada sob demanda pra UM lead (botão "Preparar retomada" do painel,
  # Onda D). Mesmos guards do lote (eligible?), sem o teto diário.
  def perform_for(lead)
    return false unless eligible?(lead)

    draft_for(lead)
    true
  end
```

`app/jobs/ramon/follow_up_draft_job.rb`:

```ruby
class Ramon::FollowUpDraftJob < ApplicationJob
  queue_as :low

  def perform(lead_id)
    lead = Lead.find_by(id: lead_id)
    return if lead.blank?

    Ramon::FollowUpDraftService.new(account: lead.account).perform_for(lead)
  end
end
```

Controller (padrão `lead_colheitas_controller`): member `post :follow_up_draft` no resources de leads em `config/routes.rb` + action no `leads_controller.rb`:

```ruby
  def follow_up_draft
    Ramon::FollowUpDraftJob.perform_later(@lead.id)
    head :accepted
  end
```

(conferir o before_action que carrega `@lead` no controller e reusar). Front API `leads.js`: `followUpDraft(leadId)` → `post(\`${this.url}/${leadId}/follow_up_draft\`)`; store action `followUpDraft({ }, leadId)` só chama a API (sem mutation — o resultado chega por broadcast do lead/nota).

- [ ] **Step 3: Commit**

```bash
git add app/services/ramon/follow_up_draft_service.rb app/jobs/ramon/follow_up_draft_job.rb app/controllers/api/v1/accounts/leads_controller.rb config/routes.rb app/javascript/dashboard/api/leads.js app/javascript/dashboard/store/modules/leads.js spec/
git commit -m "feat(ramon): retomada W4 sob demanda por lead (perform_for + endpoint 202)"
```

---

### Task 4: Front — cartões Temperatura e Risco de esfriar no painel

**Files:**
- Create: `app/javascript/dashboard/routes/dashboard/ramon/composables/useTemperatura.js`
- Create: `.../composables/specs/useTemperatura.spec.js`
- Modify: `.../components/lead/LeadPanelBody.vue` (aba Resumo — cartões novos entre "Próximo passo" e "Documentos")
- Modify: `pt_BR/ramon.json` + `en/ramon.json` (bloco `RAMON.TERMOMETRO` + `RAMON.RISCO`)
- Test: estender `.../lead/specs/LeadPanelBody.spec.js`

**Interfaces:**
- Consumes: mensagens da conversa carregada (`getSelectedChat.messages` — conferir o shape real no store de conversas); `lead.stalled`, `lead.follow_up_count`, `stage_entered_at`; action `leads/followUpDraft` (Task 3).
- Produces: `useTemperatura(messagesRef)` → `{ nivel: 'quente'|'morna'|'fria'|null, motivo: string|null }`.

- [ ] **Step 1: Teste que falha do composable**

```js
import { ref } from 'vue';
import { useTemperatura } from '../useTemperatura';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));

const msg = (type, minutesAgo, content = 'oi tudo bem por aí') => ({
  message_type: type, // 0 incoming, 1 outgoing
  created_at: Math.floor(Date.now() / 1000) - minutesAgo * 60,
  content,
  private: false,
});

describe('useTemperatura', () => {
  it('incoming recente (<60min) e ritmo curto → quente', () => {
    const { nivel } = useTemperatura(ref([msg(1, 90), msg(0, 30), msg(1, 20), msg(0, 10)]));
    expect(nivel.value).toBe('quente');
  });

  it('última incoming velha (>24h) → fria', () => {
    const { nivel } = useTemperatura(ref([msg(0, 60 * 30)]));
    expect(nivel.value).toBe('fria');
  });

  it('sinal "vou pensar" numa incoming recente rebaixa pra morna', () => {
    const { nivel } = useTemperatura(ref([msg(0, 10, 'vou pensar mais um pouco')]));
    expect(nivel.value).toBe('morna');
  });

  it('sem incoming → null (sem cartão)', () => {
    const { nivel } = useTemperatura(ref([msg(1, 10)]));
    expect(nivel.value).toBeNull();
  });
});
```

- [ ] **Step 2: Implementar o composable**

```js
import { computed } from 'vue';

// ponytail: heurística local sobre as mensagens JÁ carregadas da conversa —
// sem LLM, sem backend. Régua: última incoming <1h = quente; <24h = morna;
// senão fria. Sinal de hesitação ("vou pensar" etc.) numa incoming recente
// rebaixa quente→morna. Upgrade path: janela maior via endpoint se precisar.
const HESITACAO = /vou pensar|depois eu vejo|vou conversar|mais pra frente|qualquer coisa eu chamo/i;

export function useTemperatura(messages) {
  const incoming = computed(() =>
    (messages.value || []).filter(m => m.message_type === 0 && !m.private)
  );

  const nivel = computed(() => {
    const last = incoming.value[incoming.value.length - 1];
    if (!last) return null;
    const horas = (Date.now() / 1000 - last.created_at) / 3600;
    let n = 'fria';
    if (horas < 1) n = 'quente';
    else if (horas < 24) n = 'morna';
    const recentes = incoming.value.slice(-3);
    if (n === 'quente' && recentes.some(m => HESITACAO.test(m.content || ''))) n = 'morna';
    return n;
  });

  const hesitando = computed(() =>
    incoming.value.slice(-3).some(m => HESITACAO.test(m.content || ''))
  );

  return { nivel, hesitando };
}
```

- [ ] **Step 3: Cartões no `LeadPanelBody.vue`** (aba Resumo, depois do `<LeadNextAction />`)

Script: `const chatMessages = computed(() => currentChat.value?.messages || []);` — o painel tem acesso ao `getSelectedChat`? Conferir: o LeadPanelBody recebe `conversationId` mas não o chat; usar `useMapGetter('getSelectedChat')` (padrão LeadFollowUpBanner) SÓ quando `inConversation`. `const { nivel, hesitando } = useTemperatura(chatMessages);`. Risco: `const risco = computed(() => inConversation.value && props.lead?.stalled);` + `followUpPending = ref(false)` e:

```js
const prepararRetomada = async () => {
  if (followUpPending.value) return;
  followUpPending.value = true;
  try {
    await store.dispatch('leads/followUpDraft', props.lead.id);
    useAlert(t('RAMON.RISCO.PREPARADO'));
  } catch (e) {
    useAlert(t('RAMON.FUNIL.SAVE_ERROR'));
  } finally {
    followUpPending.value = false;
  }
};
```

Template:

```vue
        <!-- Temperatura (só na conversa; heurística local) -->
        <div v-if="inConversation && nivel" :class="CARD" data-testid="panel-card-termometro">
          <p class="text-[10.5px] font-semibold uppercase tracking-widest text-n-slate-10">
            {{ $t('RAMON.TERMOMETRO.TITLE') }}
          </p>
          <div class="mt-2 flex items-center gap-2">
            <div class="relative h-1.5 flex-1 rounded-full bg-gradient-to-r from-n-ruby-9 via-n-amber-9 to-n-teal-9 opacity-80">
              <span
                class="absolute -top-1 h-3.5 w-1 rounded bg-n-slate-12"
                :style="{ left: nivel === 'quente' ? '85%' : nivel === 'morna' ? '48%' : '10%' }"
              />
            </div>
            <span
              class="text-[11px] font-bold uppercase"
              :class="nivel === 'quente' ? 'text-n-teal-11' : nivel === 'morna' ? 'text-n-amber-11' : 'text-n-ruby-11'"
            >
              {{ $t(`RAMON.TERMOMETRO.${nivel.toUpperCase()}`) }}
            </span>
          </div>
          <p v-if="hesitando" class="mt-1.5 text-xs text-n-slate-11">
            {{ $t('RAMON.TERMOMETRO.HESITANDO') }}
          </p>
        </div>

        <!-- Risco de esfriar (stalled) -->
        <div
          v-if="risco"
          :class="CARD"
          class="border-l-4 border-l-n-ruby-9 bg-n-ruby-9/5"
          data-testid="panel-card-risco"
        >
          <p class="text-[12.5px] font-bold text-n-ruby-11">{{ $t('RAMON.RISCO.TITLE') }}</p>
          <p class="mt-0.5 text-xs text-n-slate-11">
            {{ $t('RAMON.RISCO.APOIO', { days: daysInStage ?? 0, count: Number(lead.follow_up_count) || 0 }) }}
          </p>
          <button
            type="button"
            data-testid="risco-preparar-retomada"
            class="mt-2 text-[11.5px] font-bold text-n-iris-11 underline disabled:opacity-50"
            :disabled="followUpPending"
            @click="prepararRetomada"
          >
            {{ $t('RAMON.RISCO.PREPARAR') }}
          </button>
        </div>
```

i18n pt_BR:

```json
"TERMOMETRO": { "TITLE": "Temperatura", "QUENTE": "Quente", "MORNA": "Morna", "FRIA": "Fria", "HESITANDO": "Sinal de hesitação nas últimas mensagens." },
"RISCO": { "TITLE": "Risco de esfriar", "APOIO": "Nesta etapa há {days} d · {count} retomada(s) já feitas.", "PREPARAR": "Preparar retomada (W4) →", "PREPARADO": "Retomada em preparo — o rascunho aparece nas notas e o evento na conversa." }
```

(en espelhado). Atualizar `LeadPanelBody.spec.js`: cartão risco aparece com `lead.stalled: true` e o clique dispara `leads/followUpDraft`; termômetro só com mensagens mockadas no getter do chat (seguir os mocks existentes do spec).

- [ ] **Step 4: vitest + eslint + commit**

```bash
TZ=UTC ./node_modules/.bin/vitest --no-watch app/javascript/dashboard/routes/dashboard/ramon
git add -A app/javascript
git commit -m "feat(ramon): cartoes temperatura e risco de esfriar com atalho de retomada"
```

---

### Task 5: Front — qualificação viva N/M com "perguntar →"

**Files:**
- Create: `.../components/lead/QualificacaoViva.vue`
- Create: `.../lead/specs/QualificacaoViva.spec.js`
- Modify: `.../lead/LeadPanelBody.vue` (montar depois do cartão Caso, antes do LeadQuizResumo)
- Modify: `pt_BR/ramon.json` + `en/ramon.json` (bloco `RAMON.QUALIFICACAO`)

**Interfaces:**
- Consumes: `theses` store (`theses/getTheses` + action `theses/show` — padrão ensureItems do `DocChecklist.vue:28-36`); itens `section === 'qualificacao'` (`title` = pergunta, `content` = gabarito); `custom_attributes['qualificacao_status']` (map `item_id` → `'ok'|'falta'`), PATCH via `leads/update` (deep_merge no backend — mandar só a chave); bus `INSERT_INTO_NORMAL_EDITOR` (mesma assinatura da Task 2).
- Produces: nada consumido por outras tasks.

- [ ] **Step 1: Teste que falha** — casos: (1) renderiza N/M no título (`{ok}/{total}`) e um `.criterio` por item; (2) clique no critério cicla ok→falta→sem-status e o PATCH manda SÓ `{ qualificacao_status: {...} }`; (3) "perguntar →" emite `insertIntoNormalEditor` com o `title` do item; (4) lead sem tese ou tese sem itens de qualificação → não renderiza. Mocks: theses store getter com items inline; emitter mockado.

- [ ] **Step 2: Implementar `QualificacaoViva.vue`** (espelho do DocChecklist, seções trocadas):

```vue
<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';

const props = defineProps({ lead: { type: Object, required: true } });
defineOptions({ name: 'QualificacaoViva' });

const { t } = useI18n();
const store = useStore();
const theses = useMapGetter('theses/getTheses');

const thesis = computed(() => theses.value.find(x => x.id === props.lead?.thesis_id));
const ensureItems = async () => {
  const thesisId = props.lead?.thesis_id;
  if (!thesisId) return;
  const current = theses.value.find(x => x.id === thesisId);
  if (!current || !current.items) await store.dispatch('theses/show', thesisId);
};
watch(() => props.lead?.thesis_id, ensureItems, { immediate: true });

const criterios = computed(() =>
  (thesis.value?.items || []).filter(item => item.section === 'qualificacao')
);
const statusMap = computed(
  () => props.lead?.custom_attributes?.qualificacao_status || {}
);
const statusOf = item => statusMap.value[item.id] || null;
const okCount = computed(
  () => criterios.value.filter(item => statusOf(item) === 'ok').length
);

// ciclo: null → ok → falta → null (backend faz deep_merge — só a chave vai)
const pendingIds = ref(new Set());
const cycle = async item => {
  if (pendingIds.value.has(item.id)) return;
  pendingIds.value.add(item.id);
  const next = { null: 'ok', ok: 'falta', falta: null }[String(statusOf(item))];
  try {
    await store.dispatch('leads/update', {
      id: props.lead.id,
      custom_attributes: { qualificacao_status: { [item.id]: next } },
    });
  } catch (e) {
    useAlert(t('RAMON.FUNIL.SAVE_ERROR'));
  } finally {
    pendingIds.value.delete(item.id);
  }
};

const perguntar = item => {
  emitter.emit(BUS_EVENTS.INSERT_INTO_NORMAL_EDITOR, item.title);
  useAlert(t('RAMON.QUALIFICACAO.PERGUNTA_INSERIDA'));
};
</script>

<template>
  <div
    v-if="lead?.thesis_id && criterios.length"
    class="rounded-xl border border-n-weak bg-n-solid-1 shadow-sm p-3"
    data-testid="panel-card-qualificacao"
  >
    <div class="flex items-center justify-between">
      <p class="text-[10.5px] font-semibold uppercase tracking-widest text-n-slate-10">
        {{ $t('RAMON.QUALIFICACAO.TITLE') }}
      </p>
      <span class="text-xs font-semibold text-n-slate-12" data-testid="qualificacao-count">
        {{ $t('RAMON.QUALIFICACAO.COUNT', { ok: okCount, total: criterios.length }) }}
      </span>
    </div>
    <div class="mt-1.5 flex flex-col">
      <div
        v-for="item in criterios"
        :key="item.id"
        class="flex items-center gap-2 py-1.5 text-[12.5px]"
        data-testid="qualificacao-criterio"
      >
        <button
          type="button"
          data-testid="qualificacao-toggle"
          class="grid size-4.5 shrink-0 place-items-center rounded-full text-[10px]"
          :class="
            statusOf(item) === 'ok'
              ? 'bg-n-teal-3 text-n-teal-11'
              : statusOf(item) === 'falta'
                ? 'bg-n-amber-3 text-n-amber-11'
                : 'bg-n-alpha-2 text-n-slate-10'
          "
          :disabled="pendingIds.has(item.id)"
          :title="$t('RAMON.QUALIFICACAO.CYCLE_HINT')"
          @click="cycle(item)"
        >
          {{ statusOf(item) === 'ok' ? '✓' : statusOf(item) === 'falta' ? '!' : '·' }}
        </button>
        <span class="min-w-0 truncate" :class="statusOf(item) === 'ok' ? 'text-n-slate-12' : 'text-n-slate-11'">
          {{ item.title }}
        </span>
        <button
          v-if="statusOf(item) !== 'ok'"
          type="button"
          data-testid="qualificacao-perguntar"
          class="ml-auto shrink-0 text-[11px] font-bold text-n-iris-11"
          @click="perguntar(item)"
        >
          {{ $t('RAMON.QUALIFICACAO.PERGUNTAR') }}
        </button>
      </div>
    </div>
  </div>
</template>
```

i18n pt_BR: `"QUALIFICACAO": { "TITLE": "Qualificação", "COUNT": "{ok}/{total}", "CYCLE_HINT": "Clique: confirmado → falta → limpar", "PERGUNTAR": "perguntar →", "PERGUNTA_INSERIDA": "Pergunta inserida no editor — ajuste e envie." }` (en espelhado).

Montagem no `LeadPanelBody.vue` resumo: `<QualificacaoViva :lead="lead" />` logo após o cartão Caso (o "perguntar →" pressupõe conversa; renderizar sempre — na gaveta o emit cai no vazio? NÃO: na gaveta não há ReplyBox — condicionar o botão perguntar a `inConversation` via prop `context` como o DocChecklist faz, prop `{ context: props.context }`; fora da conversa o botão perguntar copia pro clipboard, padrão chargePending do DocChecklist. Implementar exatamente esse fallback).

- [ ] **Step 3: Atualizar `LeadPanelBody.spec.js`** (cartão aparece com tese que tem critérios; stub do componente conta como presente) e rodar a suíte ramon inteira.

- [ ] **Step 4: vitest + eslint + commit**

```bash
TZ=UTC ./node_modules/.bin/vitest --no-watch app/javascript/dashboard/routes/dashboard/ramon
git add -A app/javascript
git commit -m "feat(ramon): qualificacao viva n-m com perguntar na reply box"
```

---

## Self-Review (feito na escrita)

- **Cobertura do escopo da Onda D (spec :82-83):** coach → T1+T2; termômetro → T4; risco+W4 → T3+T4; qualificação viva → T5. Tudo sem enviar nada ao cliente (constraint).
- **Tipos consistentes:** `ramon_event 'coach'` + `opcoes[{titulo,texto}]` (T1) ↔ `ramonEvent/opcoes[].titulo/texto` (T2); `leads/followUpDraft` (T3) ↔ dispatch no cartão de risco (T4); `qualificacao_status` map item_id→'ok'|'falta' só-a-chave no PATCH (T5, deep_merge do leads_controller).
- **Fail-safe:** coach silencia em qualquer erro (spec); retomada inelegível → false sem efeitos.
- **Paralelismo com a Onda C:** zero interseção de arquivos além do `ramon.json` (blocos distintos) — rebase trivial. `RamonEvent.vue` é da Onda B (mergeada), não da C.
- **Sem placeholder:** steps de teste das T4/T5 têm código; T2/T5 têm template completo; pontos a conferir no código real estão nomeados com instrução exata (shape de `getSelectedChat.messages`, before_action do leads_controller, factories dos specs).
