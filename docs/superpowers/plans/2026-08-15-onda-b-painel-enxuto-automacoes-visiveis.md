# Onda B — Painel Enxuto + Automações Visíveis — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Entregar a Onda B do redesign "Material claro": eventos de automação inline no fluxo da conversa, chip de SLA no topo, selo de transcrição no áudio e a aba Resumo do painel do lead reorganizada em cartões enxutos (Andamento / Próximo passo / Documentos / Caso, resto recolhido).

**Architecture:** Backend cria activity messages (`message_type: :activity`) com `content_attributes['ramon_event']` a partir dos 2 pontos de automação já existentes (`Ramon::FollowUpDraftService` e `Ramon::DocMatchService`) — activity nunca vaza pro contato (`action_cable_listener.rb:220-226`). Front ganha uma bolha nova no ramo activity do `Message.vue` (padrão dyte: switch por `content_attributes`, sem content_type novo), um chip SLA no `LeadFollowUpBanner` (dados `lead.sla` já chegam por broadcast), selo no bloco de transcrição já renderizado em `chips/Audio.vue`, e a aba Resumo do `LeadPanelBody` reorganizada em cartões com tokens da Onda A.

**Tech Stack:** Rails (fork Chatwoot v4.15.1), Vue 3 `<script setup>`, Tailwind (tokens `n-iris-*` da paleta bronze), Vuex, vitest, RSpec (só CI).

**Spec:** `docs/superpowers/specs/2026-08-14-redesign-ux-copiloto-design.md` (D3 + D4, Onda B) · Mockups aprovados: `comercial\docs\mockups\2026-08-14-redesign-material\conversa.html` e `conversa-v2-copiloto.html`.

## Global Constraints

- **Nesta máquina NÃO há Ruby/bundle nem Postgres.** Specs RSpec: escrever e deixar o CI validar. Front: `TZ=UTC ./node_modules/.bin/vitest --no-watch <path>` (nunca `pnpm eslint` — roda o repo inteiro; usar `./node_modules/.bin/eslint <paths>`).
- **SEMPRE `grep -r "NomeDoArquivo" spec/ app/javascript --include="*spec*" -l` antes de "criar" spec** — o glob do harness já falhou 2× em achar spec existente; estender, nunca duplicar/apagar.
- **Evento custom Vue SEMPRE camelCase** (eslint recusa kebab-case).
- **Tailwind only, tokens da paleta** (`bg-n-iris-9`, `text-n-iris-11`, `bg-n-solid-1`, `border-n-weak`, `bg-n-alpha-1/2`) — zero cor hardcoded; a Onda B inclusive REMOVE 2 hardcodes dark que sobraram.
- **i18n: sem string crua em template.** Editar só `pt_BR/ramon.json` + `en/ramon.json` (espelhar chaves). Texto de activity gerado no backend fica em PT direto no service (padrão do fork: `FollowUpDraftService`).
- **Sidekiq strict_args:** argumento de job só JSON-nativo; `content_attributes` com chaves string.
- **`custom_attributes`: sempre `lead.reload` + merge só da chave nova** (lição lost update); no front, PATCH manda só a chave alterada (`leads_controller.rb:169-178` faz deep_merge).
- **Princípio de aprovação intocado:** NADA nesta onda envia mensagem ao cliente. Activity é interna por construção. A confirmação de doc segue humana (Confirmar/Dispensar) — o "Desfazer" automático do mockup fica pra quando os modos piloto existirem (Onda C); anotar no smoke doc pro Eduardo julgar.
- **Título de PR = conventional commit** (`feat: ...`).
- Worktree novo de front precisa **`pnpm install` REAL** (junction de node_modules quebra o vitest).

---

### Task 1: Backend — eventos de automação inline (`Ramon::EventoInline`)

**Files:**
- Create: `app/services/ramon/evento_inline.rb`
- Modify: `app/services/ramon/follow_up_draft_service.rb` (método `draft_for`, linhas 56-65)
- Modify: `app/services/ramon/doc_match_service.rb` (métodos `perform` :21-32, `item_valido?` :40-46, `gravar_sugestao` :86-93)
- Test: estender specs existentes (grep: `grep -rl "FollowUpDraftService\|DocMatchService" spec/` — NÃO criar arquivo novo se existir)

**Interfaces:**
- Consumes: `Conversations::ActivityMessageJob` (`app/jobs/conversations/activity_message_job.rb` — `perform_later(conversation, message_params)`), associação `Lead#conversation` (CONFIRMADA: `app/models/lead.rb:10` `belongs_to :conversation, optional: true`). Specs a estender (CONFIRMADOS): `spec/services/ramon/follow_up_draft_service_spec.rb` e `spec/services/ramon/doc_match_service_spec.rb`.
- Produces: activity messages com `content_attributes: { 'ramon_event' => 'cadencia_follow_up' }` e `{ 'ramon_event' => 'doc_match', 'item_id' =>, 'attachment_id' =>, 'lead_id' => }`. **A Task 2 depende EXATAMENTE dessas chaves** (no front chegam camelizadas: `ramonEvent`, `itemId`, `attachmentId`, `leadId`).

- [ ] **Step 1: Escrever os testes que falham (estender specs existentes)**

No spec do `FollowUpDraftService` (contexto onde `draft_for` roda com sucesso):

```ruby
it 'registra evento de automação na conversa (activity via job)' do
  expect do
    described_class.new(account: account).perform
  end.to have_enqueued_job(Conversations::ActivityMessageJob).with(
    lead.conversation,
    hash_including(
      message_type: :activity,
      content_attributes: hash_including('ramon_event' => 'cadencia_follow_up')
    )
  )
end
```

No spec do `DocMatchService` (contexto onde a sugestão é gravada):

```ruby
it 'registra evento de automação doc_match na conversa' do
  expect { described_class.new(message).perform }
    .to have_enqueued_job(Conversations::ActivityMessageJob).with(
      message.conversation,
      hash_including(
        message_type: :activity,
        content_attributes: hash_including(
          'ramon_event' => 'doc_match',
          'item_id' => item.id
        )
      )
    )
end
```

Ajustar os `let`/factories ao que o spec existente já usa (não inventar factory nova). Se o spec usa `perform_enqueued_jobs`, trocar a asserção por checagem da message criada: `expect(conversation.messages.activity.last.content_attributes['ramon_event']).to eq('doc_match')`.

- [ ] **Step 2: Criar o helper `Ramon::EventoInline`**

`app/services/ramon/evento_inline.rb`:

```ruby
# Evento de automação visível na conversa (Onda B): activity message com
# content_attributes['ramon_event'] que o front renderiza como bolha própria
# ("o hub trabalhando à vista"). Activity nunca é entregue ao contato
# (action_cable_listener descarta activity do token do contato) — interno
# por construção.
module Ramon::EventoInline
  module_function

  # extra: só valores JSON-nativos e chaves string (Sidekiq strict_args).
  def registrar(conversation, texto, tipo:, extra: {})
    return if conversation.blank?

    Conversations::ActivityMessageJob.perform_later(
      conversation,
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      message_type: :activity,
      content: texto,
      content_attributes: { 'ramon_event' => tipo }.merge(extra)
    )
  end
end
```

- [ ] **Step 3: Chamar no `FollowUpDraftService#draft_for` (APÓS a transação — enqueue dentro dela dispararia antes do commit)**

```ruby
def draft_for(lead)
  attempt = lead.custom_attributes.dig('follow_up', 'tentativas').to_i + 1
  body = "RASCUNHO (revisar antes de enviar) — retomada nº #{attempt}:\n#{message_for(lead, attempt)}"
  # atômico: falha parcial deixaria nota órfã sem task/contador → retomada duplicada amanhã
  lead.transaction do
    lead.lead_notes.create!(account: @account, body: body.truncate(1000))
    lead.lead_tasks.create!(account: @account, kind: 'follow_up', title: "Retomada nº #{attempt}", due_at: Time.current.end_of_day)
    register_attempt(lead, attempt)
  end
  Ramon::EventoInline.registrar(lead.conversation,
                                "⟳ Cadência do hub preparou o rascunho de retomada nº #{attempt} — revise e envie pelo painel.",
                                tipo: 'cadencia_follow_up')
end
```

(`eligible?` já garante `conversation_id` presente; o guard `blank?` do helper cobre corrida de conversa apagada.)

- [ ] **Step 4: Chamar no `DocMatchService` com o ITEM (não só o id)**

Em `perform`, trocar o final para obter o objeto do item:

```ruby
  def perform
    lead = @message.account.leads.find_by(conversation_id: @message.conversation_id)
    return if lead.blank? || lead.thesis_id.blank? || attachment.blank?

    itens = pendentes(lead)
    return if itens.empty?

    item = itens.find { |i| i.id == ask_llm(lead, itens, attachment) }
    if item.blank?
      Rails.logger.info("[Ramon::DocMatchService] item fora do checklist pendente ou nulo, message=#{@message.id}")
      return
    end

    gravar_sugestao(lead, item, attachment)
  end
```

Remover `item_valido?` (absorvido acima). Em `gravar_sugestao`, nova assinatura e evento após o `update!`:

```ruby
  def gravar_sugestao(lead, item, attachment)
    lead.reload # padrão advbox: merge sobre o estado atual, só a chave nova
    lead.update!(custom_attributes: lead.custom_attributes.to_h.merge(
      'doc_sugestao' => { 'item_id' => item.id, 'attachment_id' => attachment.id,
                          'message_id' => @message.id, 'em' => Time.zone.now.iso8601,
                          'resolvida' => false }
    ))
    Ramon::EventoInline.registrar(@message.conversation,
                                  "✦ IA do hub leu o anexo e sugeriu: é \"#{item.title.presence || item.content}\" — confirme aqui ou na aba Documentos.",
                                  tipo: 'doc_match',
                                  extra: { 'item_id' => item.id, 'attachment_id' => attachment.id, 'lead_id' => lead.id })
  end
```

- [ ] **Step 5: Rubocop nos 3 arquivos tocados (sem Ruby local → conferência visual de estilo: linhas ≤150, módulo compacto) e commit**

```bash
git add app/services/ramon/evento_inline.rb app/services/ramon/follow_up_draft_service.rb app/services/ramon/doc_match_service.rb spec/
git commit -m "feat(ramon): eventos de automacao inline na conversa (cadencia + doc_match)"
```

RSpec valida no CI (constraint global).

---

### Task 2: Front — bolha `RamonEvent` no fluxo + ações Confirmar/Dispensar do doc_match

**Files:**
- Create: `app/javascript/dashboard/components-next/message/bubbles/RamonEvent.vue`
- Create: `app/javascript/dashboard/routes/dashboard/ramon/composables/useDocSugestao.js`
- Modify: `app/javascript/dashboard/components-next/message/Message.vue` (ramo activity, linhas 535-537 + import)
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/components/lead/DocChecklist.vue` (linhas 86-108 → usar o composable)
- Modify: `app/javascript/dashboard/i18n/locale/pt_BR/ramon.json` + `.../en/ramon.json`
- Test: `.../ramon/composables/specs/useDocSugestao.spec.js` (novo — grep antes p/ confirmar que não existe) + estender spec existente do DocChecklist se houver (grep)

**Interfaces:**
- Consumes: `content_attributes` da Task 1 (camelizados pelo front: `ramonEvent`, `itemId`, `attachmentId`, `leadId`); `useMessageContext()` (`components-next/message/provider.js` expõe `content`, `contentAttributes`); getter `leads/getLeadByConversationId`; getter `getSelectedChat`; action `leads/update`.
- Produces: `useDocSugestao(lead)` → `{ pending: Ref<boolean>, resolver(aceitar, { itemId, attachmentId }): Promise }`. A Task 5 NÃO depende desta; o DocChecklist passa a consumir este composable.

- [ ] **Step 1: Escrever teste que falha do composable**

`app/javascript/dashboard/routes/dashboard/ramon/composables/specs/useDocSugestao.spec.js`:

```js
import { ref } from 'vue';
import { useDocSugestao } from '../useDocSugestao';

const dispatch = vi.fn().mockResolvedValue();
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: (...args) => dispatch(...args) }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));

describe('useDocSugestao', () => {
  beforeEach(() => dispatch.mockClear());

  it('aceitar grava resolvida + recebido + anexo vinculado (merge só das chaves)', async () => {
    const { resolver } = useDocSugestao(ref({ id: 7 }));
    await resolver(true, { itemId: 3, attachmentId: 99 });
    expect(dispatch).toHaveBeenCalledWith('leads/update', {
      id: 7,
      custom_attributes: {
        doc_sugestao: { resolvida: true },
        doc_status: { 3: 'recebido' },
        doc_anexos: { 3: 99 },
      },
    });
  });

  it('dispensar grava só resolvida', async () => {
    const { resolver } = useDocSugestao(ref({ id: 7 }));
    await resolver(false, { itemId: 3, attachmentId: 99 });
    expect(dispatch).toHaveBeenCalledWith('leads/update', {
      id: 7,
      custom_attributes: { doc_sugestao: { resolvida: true } },
    });
  });

  it('guard: segunda chamada em voo é ignorada', async () => {
    let release;
    dispatch.mockReturnValueOnce(new Promise(r => (release = r)));
    const { resolver } = useDocSugestao(ref({ id: 7 }));
    const first = resolver(true, { itemId: 3, attachmentId: 99 });
    resolver(false, { itemId: 3, attachmentId: 99 });
    release();
    await first;
    expect(dispatch).toHaveBeenCalledTimes(1);
  });
});
```

- [ ] **Step 2: Rodar e ver falhar**

`TZ=UTC ./node_modules/.bin/vitest --no-watch app/javascript/dashboard/routes/dashboard/ramon/composables/specs/useDocSugestao.spec.js`
Esperado: FAIL (módulo não existe).

- [ ] **Step 3: Implementar o composable (lógica EXTRAÍDA de `DocChecklist.vue:86-108` — mesma semântica)**

`app/javascript/dashboard/routes/dashboard/ramon/composables/useDocSugestao.js`:

```js
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';

// Resolver único da sugestão da IA (custom_attributes.doc_sugestao):
// resolvida:true sempre; aceitar também grava recebido + vincula o anexo.
// Compartilhado entre DocChecklist (painel) e RamonEvent (bolha na conversa).
export function useDocSugestao(lead) {
  const store = useStore();
  const { t } = useI18n();
  const pending = ref(false);

  const resolver = async (aceitar, { itemId, attachmentId }) => {
    if (pending.value) return;
    pending.value = true;
    const patch = { doc_sugestao: { resolvida: true } };
    if (aceitar) {
      patch.doc_status = { [itemId]: 'recebido' };
      patch.doc_anexos = { [itemId]: attachmentId };
    }
    try {
      await store.dispatch('leads/update', {
        id: lead.value.id,
        custom_attributes: patch,
      });
    } catch (e) {
      useAlert(t('RAMON.FUNIL.SAVE_ERROR'));
    } finally {
      pending.value = false;
    }
  };

  return { pending, resolver };
}
```

- [ ] **Step 4: Rodar e ver passar**

Mesmo comando do Step 2. Esperado: PASS (3 testes).

- [ ] **Step 5: Refatorar `DocChecklist.vue` para usar o composable**

Substituir o bloco `sugestaoPending`/`resolverSugestao` (linhas 86-108) por:

```js
const { pending: sugestaoPending, resolver } = useDocSugestao(
  computed(() => props.lead)
);
const resolverSugestao = aceitar =>
  resolver(aceitar, {
    itemId: sugestao.value.item.id,
    attachmentId: sugestao.value.attachment_id,
  });
```

Import no topo: `import { useDocSugestao } from '../../composables/useDocSugestao';` (ajustar profundidade relativa real). O template não muda (`sugestaoPending`/`resolverSugestao` mantêm nome). Rodar o spec existente do DocChecklist (grep primeiro) — deve continuar verde.

- [ ] **Step 6: Criar a bolha `RamonEvent.vue`**

`app/javascript/dashboard/components-next/message/bubbles/RamonEvent.vue` (estilo do mockup `conversa.html` `.evento-auto`: centrado, tint bronze, borda tracejada):

```vue
<script setup>
import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useMessageContext } from '../provider.js';
import { useDocSugestao } from 'dashboard/routes/dashboard/ramon/composables/useDocSugestao';

const { content, contentAttributes } = useMessageContext();

const currentChat = useMapGetter('getSelectedChat');
const leadByConv = useMapGetter('leads/getLeadByConversationId');
const lead = computed(() => {
  const id = currentChat.value?.id;
  return id ? leadByConv.value(Number(id)) : undefined;
});

const isDocMatch = computed(
  () => contentAttributes.value?.ramonEvent === 'doc_match'
);

// Ações só enquanto a MESMA sugestão (mesmo anexo) segue pendente no lead —
// evento antigo vira registro estático.
const sugestaoAtiva = computed(() => {
  if (!isDocMatch.value) return false;
  const s = lead.value?.custom_attributes?.doc_sugestao;
  return (
    !!s &&
    !s.resolvida &&
    Number(s.attachment_id) === Number(contentAttributes.value?.attachmentId)
  );
});

const { pending, resolver } = useDocSugestao(lead);
const responder = aceitar =>
  resolver(aceitar, {
    itemId: contentAttributes.value?.itemId,
    attachmentId: contentAttributes.value?.attachmentId,
  });
</script>

<template>
  <div
    data-bubble-name="ramon-event"
    class="mx-auto max-w-[78%] rounded-xl border border-dashed border-n-iris-9/50 bg-n-iris-9/10 px-4 py-2 text-center text-xs text-n-iris-11"
  >
    <span v-dompurify-html="content" />
    <div
      v-if="sugestaoAtiva"
      class="mt-1.5 flex items-center justify-center gap-4"
    >
      <button
        type="button"
        data-testid="ramon-event-confirm"
        class="font-semibold underline disabled:opacity-60"
        :disabled="pending"
        @click="responder(true)"
      >
        {{ $t('RAMON.DOCS.SUGESTAO.CONFIRMAR') }}
      </button>
      <button
        type="button"
        data-testid="ramon-event-dismiss"
        class="underline opacity-70 disabled:opacity-40"
        :disabled="pending"
        @click="responder(false)"
      >
        {{ $t('RAMON.DOCS.SUGESTAO.DISPENSAR') }}
      </button>
    </div>
  </div>
</template>
```

- [ ] **Step 7: Ligar no ramo activity do `Message.vue`**

Linhas 535-537 viram:

```vue
    <div v-if="variant === MESSAGE_VARIANTS.ACTIVITY">
      <RamonEventBubble v-if="contentAttributes.ramonEvent" />
      <ActivityBubble v-else :content="content" />
    </div>
```

Import junto dos outros bubbles: `import RamonEventBubble from './bubbles/RamonEvent.vue';`

- [ ] **Step 8: eslint nos arquivos tocados + vitest da pasta + commit**

```bash
./node_modules/.bin/eslint app/javascript/dashboard/components-next/message/bubbles/RamonEvent.vue app/javascript/dashboard/components-next/message/Message.vue app/javascript/dashboard/routes/dashboard/ramon/composables/useDocSugestao.js app/javascript/dashboard/routes/dashboard/ramon/components/lead/DocChecklist.vue
TZ=UTC ./node_modules/.bin/vitest --no-watch app/javascript/dashboard/routes/dashboard/ramon
git add -A app/javascript
git commit -m "feat(ramon): bolha de evento de automacao inline com confirmar/dispensar do doc_match"
```

---

### Task 3: Front — chip de SLA de 1ª resposta no topo da conversa

**Files:**
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/components/conversation/LeadFollowUpBanner.vue`
- Modify: `pt_BR/ramon.json` + `en/ramon.json` (bloco novo `RAMON.SLA`)
- Test: ESTENDER `app/javascript/dashboard/routes/dashboard/ramon/components/conversation/specs/LeadFollowUpBanner.spec.js` (CONFIRMADO que existe)

**Interfaces:**
- Consumes: `lead.sla = { due_at, replied_at, minutes }` (já no payload `_lead.json.jbuilder:26-34` e no broadcast `lead_cadence.rb:50` — zero mudança de backend).
- Produces: nada consumido por outras tasks.

- [ ] **Step 1: Teste que falha (3 estados do chip)**

No spec do banner, adicionar (adaptar helpers de mount existentes do arquivo):

```js
describe('chip de SLA', () => {
  const mountWithSla = sla => mountBanner({ lead: { ...baseLead, sla } });

  it('respondido dentro do prazo → chip ok com minutos gastos', () => {
    const due = new Date('2026-08-15T12:15:00Z');
    const wrapper = mountWithSla({
      due_at: due.toISOString(),
      replied_at: '2026-08-15T12:05:00Z',
      minutes: 15,
    });
    const chip = wrapper.find('[data-testid="lead-sla-chip"]');
    expect(chip.exists()).toBe(true);
    expect(chip.classes().join(' ')).toContain('n-teal');
  });

  it('pendente e vencido → chip estourado', () => {
    const wrapper = mountWithSla({
      due_at: '2020-01-01T00:00:00Z',
      replied_at: null,
      minutes: 15,
    });
    expect(
      wrapper.find('[data-testid="lead-sla-chip"]').classes().join(' ')
    ).toContain('n-ruby');
  });

  it('sem sla no payload → sem chip', () => {
    const wrapper = mountWithSla(null);
    expect(wrapper.find('[data-testid="lead-sla-chip"]').exists()).toBe(false);
  });
});
```

- [ ] **Step 2: Rodar e ver falhar** — `TZ=UTC ./node_modules/.bin/vitest --no-watch <path do spec>`.

- [ ] **Step 3: Implementar o chip no `LeadFollowUpBanner.vue`**

No script, depois de `label` (linha 65):

```js
// Chip de SLA de 1ª resposta (Ramon::Cadencia via payload do lead).
// replied_at presente → verde com o tempo gasto (due - alvo = criação);
// pendente no prazo → âmbar com contagem; vencido → ruby. Date.now() aqui
// não é reativo — o chip re-renderiza quando o lead muda (broadcast), o que
// basta: o estado "estourado" chega junto com qualquer atividade nova.
const slaChip = computed(() => {
  const sla = lead.value?.sla;
  if (!sla?.due_at) return null;
  const due = new Date(sla.due_at).getTime();
  const targetMs = (Number(sla.minutes) || 0) * 60000;
  if (sla.replied_at) {
    const taken = Math.max(
      0,
      Math.round((new Date(sla.replied_at).getTime() - (due - targetMs)) / 60000)
    );
    return {
      tone: 'bg-n-teal-3 text-n-teal-11',
      icon: 'i-lucide-check',
      text: t('RAMON.SLA.CHIP_OK', { minutes: taken }),
    };
  }
  const leftMin = Math.round((due - Date.now()) / 60000);
  if (leftMin >= 0)
    return {
      tone: 'bg-n-amber-3 text-n-amber-11',
      icon: 'i-lucide-timer',
      text: t('RAMON.SLA.CHIP_PENDING', { minutes: leftMin }),
    };
  return {
    tone: 'bg-n-ruby-3 text-n-ruby-11',
    icon: 'i-lucide-timer-off',
    text: t('RAMON.SLA.CHIP_BREACHED'),
  };
});
```

Template: envolver os chips num grupo (o `v-if` do root sai do botão e vai pro grupo):

```vue
<template>
  <span v-if="label || slaChip" class="hidden sm:inline-flex items-center gap-1.5">
    <span
      v-if="slaChip"
      data-testid="lead-sla-chip"
      :title="slaChip.text"
      class="inline-flex items-center gap-1 px-2 py-1 text-xs rounded-full"
      :class="slaChip.tone"
    >
      <span class="size-3.5 shrink-0" :class="slaChip.icon" />
      <span class="truncate max-w-40">{{ slaChip.text }}</span>
    </span>
    <button
      v-if="label"
      type="button"
      data-testid="lead-follow-up-banner"
      :title="label"
      class="inline-flex items-center gap-1 min-w-0 max-w-48 px-2 py-1 text-xs rounded-full bg-n-amber-3 text-n-amber-11 hover:bg-n-amber-4"
      @click="openPanel"
    >
      <span class="i-lucide-history size-3.5 shrink-0" />
      <span class="truncate">{{ label }}</span>
    </button>
  </span>
</template>
```

i18n (`pt_BR/ramon.json`, bloco novo dentro de `RAMON`):

```json
"SLA": {
  "CHIP_OK": "SLA 1º contato · {minutes} min",
  "CHIP_PENDING": "SLA · responde em {minutes} min",
  "CHIP_BREACHED": "SLA estourado"
}
```

`en/ramon.json`: `"SLA": { "CHIP_OK": "First-response SLA · {minutes} min", "CHIP_PENDING": "SLA · reply within {minutes} min", "CHIP_BREACHED": "SLA breached" }`.

- [ ] **Step 4: Rodar e ver passar; conferir que os testes antigos do banner seguem verdes.**

- [ ] **Step 5: eslint no arquivo + commit**

```bash
git add app/javascript/dashboard/routes/dashboard/ramon/components/conversation/LeadFollowUpBanner.vue app/javascript/dashboard/i18n/locale/pt_BR/ramon.json app/javascript/dashboard/i18n/locale/en/ramon.json <spec>
git commit -m "feat(ramon): chip de SLA de 1a resposta no topo da conversa"
```

---

### Task 4: Front — selo "transcrito" no bloco de transcrição do áudio

**Files:**
- Modify: `app/javascript/dashboard/components-next/message/chips/Audio.vue` (bloco linhas 225-241)
- Modify: `pt_BR/ramon.json` + `en/ramon.json`

**Interfaces:** nenhuma — mudança visual pura sobre o bloco que já renderiza `attachment.transcribedText` (whisper grava em `attachment.meta`, chega via `audio_metadata`).

- [ ] **Step 1: Aplicar o selo (mockup `conversa-v2-copiloto.html` `.transcricao`: borda esquerda bronze + label uppercase)**

O bloco vira:

```vue
    <div
      v-if="attachment.transcribedText && showTranscribedText"
      data-testid="audio-transcript"
      class="text-n-slate-12 p-3 text-sm bg-n-alpha-1 rounded-lg w-full break-words border-l-2 border-n-iris-9"
    >
      <p
        class="mb-1 text-[10px] font-semibold uppercase tracking-widest text-n-iris-11"
      >
        ✦ {{ $t('RAMON.AUDIO.TRANSCRIBED') }}
      </p>
      {{ displayedTranscript }}
      <button
        v-if="isTranscriptLong"
        class="block mt-1 p-0 border-0 bg-transparent text-n-slate-11 hover:text-n-slate-12 font-medium"
        @click="isTranscriptExpanded = !isTranscriptExpanded"
      >
        {{
          isTranscriptExpanded
            ? $t('CONVERSATION.VOICE_CALL.TRANSCRIPT_SHOW_LESS')
            : $t('CONVERSATION.VOICE_CALL.TRANSCRIPT_SHOW_MORE')
        }}
      </button>
    </div>
```

i18n: `RAMON.AUDIO.TRANSCRIBED` → pt_BR `"transcrito na hora"`, en `"transcribed"` (`"AUDIO": { "TRANSCRIBED": ... }` dentro de `RAMON`).

- [ ] **Step 2: eslint + vitest de regressão da pasta message (se houver specs de Audio) + commit**

```bash
./node_modules/.bin/eslint app/javascript/dashboard/components-next/message/chips/Audio.vue
git add app/javascript/dashboard/components-next/message/chips/Audio.vue app/javascript/dashboard/i18n/locale/pt_BR/ramon.json app/javascript/dashboard/i18n/locale/en/ramon.json
git commit -m "feat(ramon): selo 'transcrito na hora' no bloco de transcricao do audio"
```

(Sem spec novo: mudança 100% visual sobre computed já coberto; YAGNI.)

---

### Task 5: Front — aba Resumo do painel em cartões enxutos (D3)

**Files:**
- Create: `app/javascript/dashboard/routes/dashboard/ramon/components/lead/MiniEsteira.vue`
- Create: `.../lead/specs/MiniEsteira.spec.js`
- Modify: `.../lead/LeadPanelBody.vue` (header :467-469 e aba resumo :502-651)
- Modify: `.../lead/LeadNextAction.vue` (linha 91 — gradiente dark hardcoded → tokens de cartão)
- Modify: `.../conversation/LeadCopilot.vue` (linha 77 — `bg-[#c9a97c]/[.14]` → token)
- Modify: `pt_BR/ramon.json` + `en/ramon.json`
- Test: `.../lead/specs/LeadPanelBody.spec.js` (ESTENDER — 390 linhas existentes; grep antes) + `MiniEsteira.spec.js` novo

**Interfaces:**
- Consumes: `stages` (getter `leadConfig/getStages`, já injetado no painel :42 — cada stage tem `id, name, color, position, probability, is_won, is_lost`); escalares do lead: `docs_received`, `docs_total`, `created_at`, `value`, `lead_stage_id`, `thesis_name`, `benefit_type_name`, `channel`.
- Produces: `MiniEsteira.vue` com props `{ stages: Array, currentId: Number }` (a Ficha pode reusar depois — fora desta onda).

- [ ] **Step 1: Teste que falha da MiniEsteira**

`.../lead/specs/MiniEsteira.spec.js`:

```js
import { mount } from '@vue/test-utils';
import MiniEsteira from '../MiniEsteira.vue';

const stages = [
  { id: 1, name: 'Novo', position: 1, is_lost: false },
  { id: 2, name: 'Qualificação', position: 2, is_lost: false },
  { id: 3, name: 'Reunião', position: 3, is_lost: false },
  { id: 9, name: 'Perdido', position: 9, is_lost: true },
];

describe('MiniEsteira', () => {
  it('renderiza uma barra por etapa não-perdida, na ordem de position', () => {
    const wrapper = mount(MiniEsteira, {
      props: { stages, currentId: 2 },
    });
    expect(wrapper.findAll('[data-testid="mini-esteira-barra"]')).toHaveLength(3);
  });

  it('marca feitas e atual em bronze; futuras no trilho', () => {
    const wrapper = mount(MiniEsteira, {
      props: { stages, currentId: 2 },
    });
    const barras = wrapper.findAll('[data-testid="mini-esteira-barra"]');
    expect(barras[0].classes()).toContain('bg-n-iris-9');
    expect(barras[1].classes()).toContain('bg-n-iris-9');
    expect(barras[2].classes()).toContain('bg-n-alpha-2');
  });
});
```

- [ ] **Step 2: Rodar e ver falhar** — `TZ=UTC ./node_modules/.bin/vitest --no-watch <path>`.

- [ ] **Step 3: Implementar `MiniEsteira.vue`**

```vue
<script setup>
import { computed } from 'vue';

const props = defineProps({
  stages: { type: Array, default: () => [] },
  currentId: { type: Number, default: null },
});
defineOptions({ name: 'MiniEsteira' });

// Perdido fica fora da trilha (mockup: caminho linear até o ganho).
const trilha = computed(() =>
  [...props.stages]
    .filter(s => !s.is_lost)
    .sort((a, b) => (a.position ?? 0) - (b.position ?? 0))
);
const currentIndex = computed(() =>
  trilha.value.findIndex(s => s.id === props.currentId)
);
</script>

<template>
  <div class="flex gap-1" data-testid="mini-esteira">
    <i
      v-for="(stage, index) in trilha"
      :key="stage.id"
      :title="stage.name"
      data-testid="mini-esteira-barra"
      class="h-1 flex-1 rounded-full"
      :class="
        currentIndex >= 0 && index <= currentIndex
          ? 'bg-n-iris-9'
          : 'bg-n-alpha-2'
      "
    />
  </div>
</template>
```

- [ ] **Step 4: Rodar e ver passar.**

- [ ] **Step 5: Tokens nos 2 hardcodes dark**

`LeadNextAction.vue:91` — trocar:

```
class="rounded-xl p-3 bg-gradient-to-br from-[#332e28] to-[#2e2b27] border"
```

por:

```
class="rounded-xl p-3 bg-n-solid-1 border shadow-sm border-l-4"
:class="dueInfo.overdue ? 'border-n-amber-9/40 border-l-n-amber-9' : 'border-n-weak border-l-n-iris-9'"
```

(o `:class` existente da linha 92 é absorvido acima). Na linha 96, `text-n-slate-10` já funciona no claro — manter.

`LeadCopilot.vue:77` — trocar `bg-[#c9a97c]/[.14]` por `bg-n-iris-9/10` (manter o resto da classe).

- [ ] **Step 6: Reorganizar a aba Resumo do `LeadPanelBody.vue`**

6a. No script, adicionar computeds (perto de `valorEstimadoAuto`, linha 83):

```js
// ----- Onda B: cartões do resumo -----
const CARD = 'rounded-xl border border-n-weak bg-n-solid-1 shadow-sm p-3';
const stageName = computed(
  () => stages.value?.find(s => s.id === stageId.value)?.name || ''
);
const probability = computed(() => {
  const p = stages.value?.find(s => s.id === stageId.value)?.probability;
  return p == null ? null : Number(p);
});
// stage_entered_at porque created_at NÃO está no payload do lead (verificado
// no _lead.json.jbuilder) — e "nesta etapa há Xd" casa com a régua de parado.
const daysInStage = computed(() => {
  if (!props.lead?.stage_entered_at) return null;
  const diff = Date.now() - new Date(props.lead.stage_entered_at).getTime();
  return Number.isNaN(diff) ? null : Math.max(0, Math.floor(diff / 86400000));
});
const andamentoApoio = computed(() =>
  [
    daysInStage.value != null
      ? t('RAMON.LEAD_PANEL.ANDAMENTO.IN_STAGE', { days: daysInStage.value })
      : null,
    formattedValue.value,
    probability.value != null ? `${probability.value}%` : null,
  ]
    .filter(Boolean)
    .join(' · ')
);
const docsPct = computed(() => {
  const total = Number(props.lead?.docs_total) || 0;
  if (!total) return 0;
  return Math.round(((Number(props.lead?.docs_received) || 0) / total) * 100);
});
const contactOpen = ref(false);
```

(Campos verificados no `_lead.json.jbuilder`: `stage_entered_at`, `channel` (linha 38), `docs_received/docs_total` — nenhum campo novo no jbuilder é necessário.)

6b. No header, REMOVER o bloco `<LeadNextAction ... />` (linhas 467-469) — ele desce pro corpo do resumo.

6c. O corpo da aba resumo (`<template v-if="shownTab === 'resumo'">`, linhas 502-651) vira, nesta ordem:

```vue
      <template v-if="shownTab === 'resumo'">
        <LeadCopilot
          v-if="inConversation && conversationId"
          :conversation-id="conversationId"
        />

        <!-- Andamento -->
        <div :class="CARD" data-testid="panel-card-andamento">
          <p class="text-[10.5px] font-semibold uppercase tracking-widest text-n-slate-10">
            {{ $t('RAMON.LEAD_PANEL.ANDAMENTO.TITLE') }}
          </p>
          <p class="mt-1 text-[13px] font-semibold text-n-iris-11">
            {{ stageName || '—' }}
          </p>
          <MiniEsteira
            class="mt-2"
            :stages="stages"
            :current-id="stageId"
          />
          <p v-if="andamentoApoio" class="mt-1.5 text-xs text-n-slate-11">
            {{ andamentoApoio }}
          </p>
        </div>

        <!-- Próximo passo (era LeadNextAction do header) -->
        <LeadNextAction :lead-id="lead.id" />

        <!-- Documentos -->
        <button
          v-if="lead.thesis_id && lead.docs_total"
          :class="CARD"
          class="text-left w-full hover:border-n-iris-9/40"
          data-testid="panel-card-docs"
          @click="setTab('documentos')"
        >
          <div class="flex items-center justify-between">
            <p class="text-[10.5px] font-semibold uppercase tracking-widest text-n-slate-10">
              {{ $t('RAMON.DOCS.TITLE') }}
            </p>
            <span class="text-xs font-semibold text-n-slate-12">
              {{ $t('RAMON.DOCS.COUNT', { received: lead.docs_received || 0, total: lead.docs_total }) }}
            </span>
          </div>
          <div class="mt-2 h-1.5 rounded-full bg-n-alpha-2 overflow-hidden">
            <div
              class="h-full bg-n-iris-9"
              :style="{ width: `${docsPct}%` }"
            />
          </div>
        </button>

        <!-- Caso -->
        <div :class="CARD" data-testid="panel-card-caso">
          <p class="text-[10.5px] font-semibold uppercase tracking-widest text-n-slate-10">
            {{ $t('RAMON.LEAD_PANEL.CASE_TITLE') }}
          </p>
          <p class="mt-1 text-[13px] font-semibold text-n-slate-12">
            {{ [lead.thesis_name, lead.benefit_type_name].filter(Boolean).join(' · ') || '—' }}
          </p>
          <div class="grid grid-cols-2 gap-x-3 gap-y-2 mt-2">
            <div>
              <p class="text-[10.5px] text-n-slate-9">
                {{ $t('RAMON.LEAD_PANEL.FIELDS.DCB') }}
              </p>
              <p
                data-testid="panel-dcb"
                class="text-[13px]"
                :class="bleeding ? 'text-n-ruby-11' : 'text-n-slate-12'"
              >
                {{ dcbFormatted || '—' }}
              </p>
            </div>
            <div>
              <p class="text-[10.5px] text-n-slate-9">
                {{ $t('RAMON.LEAD_PANEL.FIELDS.CHANNEL') }}
              </p>
              <p class="text-[13px] text-n-slate-12">{{ lead.channel || '—' }}</p>
            </div>
          </div>
        </div>

        <LeadQuizResumo :lead="lead" />
        <LeadNotes :lead-id="lead.id" />

        <!-- Dados do contato (recolhido — mesmo padrão do "Mais da conversa") -->
        <div class="pt-3 border-t border-n-weak min-w-0">
          <button
            data-testid="contact-data-toggle"
            class="flex items-center w-full gap-1.5 text-[10.5px] font-semibold uppercase tracking-[.1em] text-n-slate-10 hover:text-n-slate-12"
            @click="contactOpen = !contactOpen"
          >
            {{ $t('RAMON.LEAD_PANEL.CONTACT_DATA') }}
            <span
              class="size-3.5 shrink-0"
              :class="contactOpen ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'"
            />
          </button>
          <div v-if="contactOpen" class="flex flex-col gap-2 mt-3 min-w-0">
            <div class="grid grid-cols-2 gap-x-3 gap-y-2">
              <div>
                <p class="text-[10.5px] text-n-slate-9">
                  {{ $t('RAMON.LEAD_PANEL.FIELDS.PHONE') }}
                </p>
                <p class="text-[13px] text-n-slate-12">
                  {{ lead.contact_phone || '—' }}
                </p>
              </div>
              <div>
                <p class="text-[10.5px] text-n-slate-9">
                  {{ $t('RAMON.LEAD_PANEL.FIELDS.CPF') }}
                </p>
                <p class="text-[13px] text-n-slate-12">
                  {{ formatCpf(lead.contact_cpf) || '—' }}
                </p>
              </div>
              <div>
                <p class="text-[10.5px] text-n-slate-9">
                  {{ $t('RAMON.LEAD_PANEL.FIELDS.OWNERS') }}
                </p>
                <p class="text-[13px] text-n-slate-12">{{ owners || '—' }}</p>
              </div>
            </div>
            <button
              data-testid="lead-edit-all-toggle"
              class="self-center text-[11px] text-n-slate-10 hover:text-n-slate-12"
              @click="fieldsExpanded = !fieldsExpanded"
            >
              {{
                fieldsExpanded
                  ? `${$t('RAMON.LEAD_PANEL.EDIT_ALL_FIELDS_CLOSE')} ▴`
                  : `${$t('RAMON.LEAD_PANEL.EDIT_ALL_FIELDS')} ▾`
              }}
            </button>
            <div v-if="fieldsExpanded" ref="fieldsEl" data-testid="lead-all-fields">
              <LeadFields :lead="lead" />
            </div>
          </div>
        </div>

        <!-- "Mais da conversa" e "Não é lead": blocos existentes, INTOCADOS -->
```

Manter na sequência os blocos existentes de `conversation-extras` (linhas 579-612) e descarte (linhas 614-650) exatamente como estão. Os campos BENEFIT/THESIS saem do grid antigo (agora vivem no cartão Caso); o grid antigo de 2 colunas (linhas 508-559) é REMOVIDO (phone/CPF/owners foram pro recolhido, DCB/channel pro Caso). Import novo no script: `import MiniEsteira from './MiniEsteira.vue';`

Chave `RAMON.LEAD_PANEL.FIELDS.CHANNEL` JÁ EXISTE no ramon.json (verificado) — reusar, não criar.

6d. i18n (`pt_BR/ramon.json`, dentro de `RAMON.LEAD_PANEL`):

```json
"ANDAMENTO": { "TITLE": "Andamento", "IN_STAGE": "Nesta etapa há {days} d" },
"CASE_TITLE": "Caso",
"CONTACT_DATA": "Dados do contato"
```

E o título do próximo passo: em `RAMON.LEAD_PANEL.NEXT_ACTION.TITLE`, trocar o valor atual por `"Próximo passo"` (pt_BR; en: `"Next step"`). Espelhar as chaves novas no `en/ramon.json`.

- [ ] **Step 7: Atualizar `LeadPanelBody.spec.js`**

Estender/ajustar o spec existente (390 linhas — NÃO recriar):
- testes que procuram o grid antigo de campos no resumo → apontar pros cartões novos (`panel-card-andamento`, `panel-card-caso`) e pro toggle `contact-data-toggle` (phone/CPF só aparecem após clique);
- teste novo: "Andamento mostra a etapa atual e a mini-esteira" (mount com stages no store mock, assert `[data-testid="mini-esteira"]` presente e nome da etapa);
- teste novo: "cartão Documentos leva pra aba documentos" (click em `panel-card-docs` → aba documentos ativa);
- teste existente de `lead-edit-all-toggle` → passar a abrir `contact-data-toggle` antes.

- [ ] **Step 8: Rodar a suíte do painel e ver verde**

`TZ=UTC ./node_modules/.bin/vitest --no-watch app/javascript/dashboard/routes/dashboard/ramon`

- [ ] **Step 9: eslint nos arquivos tocados + commit**

```bash
git add -A app/javascript
git commit -m "feat(ramon): aba resumo do painel em cartoes enxutos (andamento, proximo passo, docs, caso)"
```

---

## Self-Review (feito na escrita)

- **Cobertura da spec (Onda B):** painel enxuto D3 → Task 5; eventos inline → Tasks 1+2; chips SLA/cadência → Task 3 (cadência já existia — `LeadFollowUpBanner`); áudio transcrito inline → Task 4. Rascunho da IA no composer, coach, termômetro e qualificação viva = Ondas C/D (fora desta onda, spec `:80-83`).
- **"Desfazer" do mockup:** implementado como Confirmar/Dispensar (aprovação humana ANTES de marcar) — divergência deliberada do mockup registrada nas Global Constraints e a registrar no smoke doc.
- **Cartões Cálculos (n)/Reuniões (n) recolhidos do mockup:** FORA desta onda — esses dados só existem no endpoint do dossiê; no painel ficam a 1 clique via "Abrir ficha completa". Anotar no smoke doc.
- **Tipos consistentes:** `ramon_event`/`item_id`/`attachment_id` (string keys, backend) ↔ `ramonEvent`/`itemId`/`attachmentId` (camelizados no front via `useCamelCase` do MessageList) — conferido; `useDocSugestao(lead)` recebe Ref e é consumido igual nas Tasks 2 (bubble e DocChecklist).
- **Sem placeholder:** todo step tem código/comando concreto; os pontos antes condicionais foram VERIFICADOS no código (associação `Lead#conversation` existe, `created_at` NÃO está no jbuilder → `stage_entered_at`, chave CHANNEL existe, specs dos serviços e do banner existem).
