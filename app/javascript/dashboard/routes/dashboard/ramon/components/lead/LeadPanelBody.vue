<script setup>
import { ref, computed, watch, nextTick, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import ConversationAction from 'dashboard/routes/dashboard/conversation/ConversationAction.vue';
import MacrosList from 'dashboard/routes/dashboard/conversation/Macros/List.vue';
import ResolveAction from 'dashboard/components/buttons/ResolveAction.vue';
import LeadFields from './LeadFields.vue';
import LeadNextAction from './LeadNextAction.vue';
import MiniEsteira from './MiniEsteira.vue';
import LeadNotes from './LeadNotes.vue';
import LeadQuizResumo from './LeadQuizResumo.vue';
import LeadZapsignCard from './LeadZapsignCard.vue';
import LostReasonModal from '../kanban/LostReasonModal.vue';
import LeadCopilot from '../conversation/LeadCopilot.vue';
import LeadHistory from '../conversation/LeadHistory.vue';
import LeadPlaybook from '../conversation/LeadPlaybook.vue';
import LeadTriage from '../conversation/LeadTriage.vue';
import LeadKit from '../conversation/LeadKit.vue';
import LeadSimulador from '../conversation/LeadSimulador.vue';
import DocChecklist from './DocChecklist.vue';
import { useLeadPanelTabs } from '../../composables/useLeadPanelSections';
import { useTemperatura } from '../../composables/useTemperatura';
import { prescriptionInfo } from '../../helpers/prescription';
import { formatBrl, parseBrlInput } from '../../helpers/currency';
import { waMeUrl } from '../../helpers/phone';
import { formatCpf } from '../../helpers/cpf';

const props = defineProps({
  lead: { type: Object, required: true },
  context: {
    type: String,
    default: 'conversation',
    validator: v => ['conversation', 'drawer'].includes(v),
  },
  conversationId: { type: [Number, String], default: null },
});
const emit = defineEmits(['discarded', 'openConversation', 'navigate']);

defineOptions({ name: 'LeadPanelBody' });
const store = useStore();
const { t } = useI18n();
const stages = useMapGetter('leadConfig/getStages');
const channels = useMapGetter('leadConfig/getChannels');
const lostReasons = useMapGetter('leadConfig/getLostReasons');

// Etapas/motivos só eram buscados pelo Funil: abrir a conversa direto (F5)
// deixava o chip de etapa VAZIO e o modal de perda sem motivos.
onMounted(() => {
  if (!stages.value?.length) store.dispatch('leadConfig/get');
});

const inConversation = computed(() => props.context === 'conversation');

// ----- cabeçalho: chips -----
const prescription = computed(() => prescriptionInfo(props.lead));
const prescriptionLabel = computed(() => {
  const p = prescription.value;
  if (!p) return null;
  if (p.lostInstallments > 0 && p.monthlyValue)
    return `⏳ ${t('RAMON.KANBAN.CARD.PRESCRIPTION_BLEEDING', {
      value: formatBrl(p.monthlyValue),
    })}`;
  if (p.lostInstallments > 0)
    return `⏳ ${t('RAMON.KANBAN.CARD.PRESCRIPTION_LOST', {
      count: p.lostInstallments,
    })}`;
  if (p.monthsToCliff <= 6)
    return `⏳ ${t('RAMON.KANBAN.CARD.PRESCRIPTION_SOON', {
      months: p.monthsToCliff,
    })}`;
  return null;
});
const bleeding = computed(() => prescription.value?.lostInstallments > 0);

const formattedValue = computed(() =>
  props.lead?.value == null || props.lead?.value === ''
    ? null
    : formatBrl(props.lead.value)
);

// Badge "estimado": mesmo computed do LeadFields, dentro do chip de valor.
const valorEstimadoAuto = computed(
  () => props.lead?.custom_attributes?.valor_estimado?.origem === 'auto'
);

// ----- etapa editável no chip (mesma guarda do LeadFields: perda pede motivo,
// ganho sem valor pede valor — senão o backend recusa com 422) -----
const stageId = ref(props.lead?.lead_stage_id ?? null);
const lostModalOpen = ref(false);
const wonPrompt = ref(false);
const wonValue = ref('');

watch(
  () => props.lead,
  (l, prev) => {
    if (l?.id !== prev?.id) {
      stageId.value = l?.lead_stage_id ?? null;
      lostModalOpen.value = false;
      wonPrompt.value = false;
      return;
    }
    // broadcast no mesmo lead: não mexer com prompt aberto nem select focado
    const focused = document.activeElement?.dataset?.testid;
    if (!lostModalOpen.value && !wonPrompt.value && focused !== 'panel-stage') {
      stageId.value = l?.lead_stage_id ?? null;
    }
  }
);

// Chip de etapa colorido (mock 1f: pílula soft na cor da etapa) — :style é o
// precedente do fork p/ cor dinâmica (KanbanColumn); sem cor, fica neutro.
const stageChipStyle = computed(() => {
  const color = stages.value?.find(s => s.id === stageId.value)?.color;
  if (!color) return null;
  return {
    backgroundColor: `${color}2E`,
    borderColor: `${color}59`,
    color,
  };
});

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
// ----- Temperatura (heurística local, só na conversa) + Risco de esfriar -----
const currentChat = useMapGetter('getSelectedChat');
const chatMessages = computed(() => currentChat.value?.messages || []);
const { nivel, hesitando } = useTemperatura(chatMessages);
const risco = computed(() => Boolean(props.lead?.stalled));
const followUpPending = ref(false);
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

const docsPct = computed(() => {
  const total = Number(props.lead?.docs_total) || 0;
  if (!total) return 0;
  return Math.round(((Number(props.lead?.docs_received) || 0) / total) * 100);
});
const contactOpen = ref(false);

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
    lostModalOpen.value = false;
    wonPrompt.value = false;
  }
};

const onStageChange = targetId => {
  stageId.value = targetId;
  lostModalOpen.value = false;
  wonPrompt.value = false;
  const target = stages.value.find(s => s.id === targetId);
  if (target?.is_lost && !props.lead?.lost_reason) {
    lostModalOpen.value = true;
    return;
  }
  // Ganho: SEMPRE pede confirmação, pré-preenchida quando o lead já tem valor
  // (o automático da Onda 3 não pode virar "valor de contrato" em silêncio).
  if (target?.is_won) {
    wonValue.value = formatBrl(props.lead?.value);
    wonPrompt.value = true;
    return;
  }
  commitStage(targetId);
};

const confirmLostStage = ({ lostReason }) =>
  commitStage(stageId.value, { lost_reason: lostReason });
const cancelLostStage = () => {
  lostModalOpen.value = false;
  stageId.value = props.lead?.lead_stage_id ?? null;
};
const confirmWonStage = () => {
  const parsed = parseBrlInput(wonValue.value);
  commitStage(stageId.value, parsed == null ? {} : { value: parsed });
};
const skipWonStage = () => commitStage(stageId.value);

// ----- + Tarefa: form inline (mesmos defaults do LeadTasksList) -----
const taskFormOpen = ref(false);
const taskTitle = ref('');
const taskDate = ref('');
const tomorrowAt9 = () => {
  const d = new Date();
  d.setDate(d.getDate() + 1);
  d.setHours(9, 0, 0, 0);
  return d;
};
// guard de duplo-clique: dois cliques rápidos criavam a tarefa em dobro
const savingTask = ref(false);
const addTask = async () => {
  if (savingTask.value) return;
  savingTask.value = true;
  const title = taskTitle.value.trim() || t('RAMON.KANBAN.BELL.DEFAULT_TITLE');
  const due = taskDate.value ? new Date(taskDate.value) : tomorrowAt9();
  try {
    await store.dispatch('leadTasks/create', {
      leadId: props.lead.id,
      title,
      kind: 'follow_up',
      dueAt: due.toISOString(),
    });
    taskTitle.value = '';
    taskDate.value = '';
    taskFormOpen.value = false;
  } catch (e) {
    useAlert(t('RAMON.TASKS.CREATE_ERROR'));
  } finally {
    savingTask.value = false;
  }
};

// ----- abas -----
const { activeTab, setTab } = useLeadPanelTabs();
const iaDot = computed(() => {
  if (props.lead?.latest_triage?.status === 'awaiting_human')
    return 'bg-n-amber-9';
  if (props.lead?.latest_triage?.kit_status === 'ready') return 'bg-n-teal-9';
  return null;
});
const simuladorDot = computed(() =>
  props.lead?.custom_attributes?.ultima_simulacao ? 'bg-n-teal-9' : null
);
// Dot âmbar: existe item de documento ainda não recebido (docs_total/received
// vêm do jbuilder — Task 3; antes dela o dot fica apagado, sem erro).
const docsDot = computed(() =>
  props.lead?.docs_total > 0 &&
  props.lead?.docs_received < props.lead?.docs_total
    ? 'bg-n-amber-9'
    : null
);
// mesma elegibilidade do LeadZapsignCard: a aba Contrato só existe pra tese
// de acidente — nos demais leads ela some e a aba salva cai no Resumo
const zapsignEligible = computed(() =>
  (props.lead?.thesis_name || '').toLowerCase().includes('acidente')
);
const TABS = computed(() => [
  { id: 'resumo', label: 'SUMMARY' },
  { id: 'playbook', label: 'PLAYBOOK' },
  { id: 'ia', label: 'IA', dot: iaDot },
  { id: 'simulador', label: 'SIMULADOR', dot: simuladorDot },
  ...(props.lead?.thesis_id
    ? [{ id: 'documentos', label: 'DOCUMENTS', dot: docsDot }]
    : []),
  ...(zapsignEligible.value ? [{ id: 'contrato', label: 'CONTRACT' }] : []),
  { id: 'historico', label: 'HISTORY' },
]);
const shownTab = computed(() => {
  if (activeTab.value === 'contrato' && !zapsignEligible.value) return 'resumo';
  if (activeTab.value === 'documentos' && !props.lead?.thesis_id)
    return 'resumo';
  return activeTab.value;
});

// ----- "editar todos os campos": LeadFields completo recolhido por padrão -----
const fieldsExpanded = ref(false);
const fieldsEl = ref(null);
const onCompleteData = async () => {
  setTab('resumo');
  contactOpen.value = true;
  fieldsExpanded.value = true;
  await nextTick();
  fieldsEl.value?.scrollIntoView({ behavior: 'smooth', block: 'start' });
};

// ----- campos derivados dos cartões -----
const dcbFormatted = computed(() => {
  if (!props.lead?.dcb_em) return null;
  const d = new Date(`${props.lead.dcb_em}T00:00:00`);
  return Number.isNaN(d.getTime()) ? null : d.toLocaleDateString('pt-BR');
});
const owners = computed(() => {
  const sdr = props.lead?.sdr_name;
  const closer = props.lead?.closer_name;
  if (!sdr && !closer) return null;
  return `${sdr || '—'} / ${closer || '—'}`;
});
const channelLabel = computed(
  () =>
    channels.value?.find(c => c.key === props.lead?.channel)?.label ??
    props.lead?.channel
);

// ----- seções nativas do Chatwoot (agente/time/prioridade/etiquetas/macros)
// recolhidas: não existem no mock 1f e "sujavam" o fim do Resumo -----
const conversationExtrasOpen = ref(false);

// ----- "Não é lead" (destrutivo: confirmação inline, só na conversa) -----
const discardPrompt = ref(false);
const discarding = ref(false);
const discard = async () => {
  if (!props.lead || discarding.value) return;
  discarding.value = true;
  try {
    await store.dispatch('leads/delete', props.lead.id);
    emit('discarded');
  } catch (e) {
    useAlert(t('RAMON.LEAD_PANEL.DISCARD_ERROR'));
  } finally {
    discarding.value = false;
    discardPrompt.value = false;
  }
};
</script>

<template>
  <div class="flex flex-col flex-1 h-full min-w-0 overflow-hidden">
    <!-- cabeçalho fixo: quem e quanto sem rolar -->
    <div class="shrink-0 px-3 pt-3 border-b border-n-weak">
      <router-link
        v-if="lead?.id"
        data-testid="lead-abrir-ficha"
        :to="{ name: 'ramon_lead_dossie', params: { leadId: lead.id } }"
        class="mb-2 flex w-full items-center justify-center gap-1.5 rounded-lg bg-n-iris-9 px-3 py-2 text-sm font-semibold text-white hover:bg-n-iris-10"
        @click="emit('navigate')"
      >
        <span class="i-lucide-contact size-4" />{{
          $t('RAMON.FICHA.OPEN_FULL')
        }}
      </router-link>

      <h2
        class="font-cormorant text-[21px] font-semibold leading-tight text-n-slate-12 truncate"
      >
        {{ lead.name }}
      </h2>

      <div class="flex flex-wrap items-center gap-1.5 mt-1.5 min-w-0">
        <!-- h-auto + bg-none: o CSS global de <select> (_base.scss) impõe h-10
             e seta de fundo — sem isso o chip vira caixa de formulário -->
        <select
          data-testid="panel-stage"
          :value="stageId"
          class="max-w-40 appearance-none truncate rounded-full border border-n-weak bg-n-alpha-1 h-auto bg-none px-2.5 py-0.5 text-[11px] text-n-slate-11 outline-none focus:border-n-slate-8"
          :style="stageChipStyle"
          @change="e => onStageChange(Number(e.target.value))"
        >
          <option v-for="s in stages" :key="s.id" :value="s.id">
            {{ s.name }}
          </option>
        </select>
        <span
          v-if="prescriptionLabel"
          data-testid="panel-prescription-chip"
          class="rounded-full px-2.5 py-0.5 text-[11px] text-white"
          :class="bleeding ? 'bg-n-ruby-9' : 'bg-n-amber-9'"
        >
          {{ prescriptionLabel }}
        </span>
        <span
          v-if="formattedValue"
          data-testid="panel-value-chip"
          class="inline-flex items-center gap-1 rounded-full bg-n-alpha-2 px-2.5 py-0.5 text-[11px] text-n-slate-11"
        >
          {{ formattedValue }}
          <span
            v-if="valorEstimadoAuto"
            data-testid="value-auto-badge"
            :title="$t('RAMON.DRAWER.VALUE_AUTO_TIP')"
            class="inline-flex items-center gap-0.5 rounded bg-n-iris-9/10 px-1 text-[10px] text-n-iris-11"
          >
            <span class="i-lucide-sparkles size-2.5" />{{
              $t('RAMON.DRAWER.VALUE_AUTO')
            }}
          </span>
        </span>
      </div>

      <LostReasonModal
        v-if="lostModalOpen"
        :lost-reasons="lostReasons"
        @confirm-move="confirmLostStage"
        @cancel-move="cancelLostStage"
      />

      <div
        v-if="wonPrompt"
        data-testid="stage-won-prompt"
        class="flex flex-col gap-2 p-2 mt-2 rounded-lg bg-n-alpha-1 border border-n-weak"
      >
        <label class="text-xs text-n-slate-10">{{
          $t('RAMON.FUNIL.WON.VALUE_LABEL')
        }}</label>
        <input
          v-model="wonValue"
          data-testid="stage-won-value"
          type="text"
          inputmode="decimal"
          class="w-full px-2 py-1.5 text-sm rounded-lg bg-n-alpha-1 text-n-slate-12 border border-n-weak outline-none focus:border-n-slate-8"
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

      <!-- 4 ações fixas. WhatsApp abre a conversa (gaveta) ou o wa.me (sem
           conversa); no painel da conversa ela já está aberta — botão sai. -->
      <div class="flex gap-1.5 mt-3">
        <button
          v-if="lead.conversation_id && !inConversation"
          data-testid="panel-whatsapp"
          class="flex flex-1 items-center justify-center gap-1 rounded-lg bg-n-iris-9 px-1 py-1.5 text-xs font-semibold text-white hover:bg-n-iris-10"
          @click="emit('openConversation', lead.conversation_id)"
        >
          <span class="i-lucide-message-square size-3.5 shrink-0" />{{
            $t('RAMON.KANBAN.CARD.WHATSAPP')
          }}
        </button>
        <a
          v-else-if="!lead.conversation_id && lead.contact_phone"
          data-testid="panel-whatsapp-wa-me"
          :href="waMeUrl(lead.contact_phone)"
          target="_blank"
          rel="noopener noreferrer"
          class="flex flex-1 items-center justify-center gap-1 rounded-lg bg-n-iris-9 px-1 py-1.5 text-xs font-semibold text-white hover:bg-n-iris-10"
        >
          <span class="i-lucide-message-square size-3.5 shrink-0" />{{
            $t('RAMON.KANBAN.CARD.WHATSAPP')
          }}
        </a>
        <button
          data-testid="panel-add-task"
          class="flex-1 rounded-lg bg-n-alpha-1 px-1 py-1.5 text-xs text-n-slate-11 hover:bg-n-alpha-2"
          @click="taskFormOpen = !taskFormOpen"
        >
          {{ $t('RAMON.TASKS.ADD') }}
        </button>
        <div v-if="inConversation" class="flex flex-1 min-w-0 [&>*]:w-full">
          <ResolveAction color="teal" variant="faded" />
        </div>
      </div>

      <div
        v-if="taskFormOpen"
        data-testid="panel-task-form"
        class="flex flex-col gap-2 p-2 mt-2 rounded-lg bg-n-alpha-1 border border-n-weak"
      >
        <input
          v-model="taskTitle"
          data-testid="panel-task-title"
          :placeholder="$t('RAMON.TASKS.ADD_TITLE_PLACEHOLDER')"
          class="w-full px-2 py-1.5 text-sm rounded-lg bg-n-alpha-1 text-n-slate-12 border border-n-weak outline-none focus:border-n-slate-8"
        />
        <input
          v-model="taskDate"
          data-testid="panel-task-date"
          type="datetime-local"
          :title="$t('RAMON.TASKS.DATE_HINT')"
          class="w-full px-2 py-1.5 text-sm rounded-lg bg-n-alpha-1 text-n-slate-12 border border-n-weak outline-none focus:border-n-slate-8"
        />
        <div class="flex justify-end gap-2">
          <button
            data-testid="panel-task-cancel"
            class="px-3 py-1 text-xs text-n-slate-11"
            @click="taskFormOpen = false"
          >
            {{ $t('RAMON.FUNIL.CANCEL') }}
          </button>
          <button
            data-testid="panel-task-save"
            class="px-3 py-1 text-xs rounded-lg bg-n-iris-9 text-white disabled:opacity-50"
            :disabled="savingTask"
            @click="addTask"
          >
            {{ $t('RAMON.FUNIL.SAVE') }}
          </button>
        </div>
      </div>

      <!-- abas segmentadas com dot de status -->
      <div class="flex mt-2 -mb-px overflow-x-auto" role="tablist">
        <button
          v-for="tab in TABS"
          :key="tab.id"
          role="tab"
          :aria-selected="shownTab === tab.id"
          :data-testid="`lead-tab-${tab.id}`"
          class="flex items-center gap-1.5 whitespace-nowrap border-b-2 px-3 py-2 text-[12.5px]"
          :class="
            shownTab === tab.id
              ? 'border-n-iris-11 font-semibold text-n-iris-11'
              : 'border-transparent text-n-slate-10 hover:text-n-slate-11'
          "
          @click="setTab(tab.id)"
        >
          {{ $t(`RAMON.LEAD_PANEL.TABS.${tab.label}`) }}
          <span
            v-if="tab.dot?.value"
            :data-testid="`lead-tab-dot-${tab.id}`"
            class="size-1.5 rounded-full"
            :class="tab.dot.value"
          />
        </button>
      </div>
    </div>

    <!-- corpo da aba ativa -->
    <div
      class="flex flex-col flex-1 gap-3 min-w-0 overflow-y-auto overflow-x-hidden p-3"
    >
      <template v-if="shownTab === 'resumo'">
        <LeadCopilot
          v-if="inConversation && conversationId"
          :conversation-id="conversationId"
        />

        <!-- Andamento -->
        <div :class="CARD" data-testid="panel-card-andamento">
          <p
            class="text-[10.5px] font-semibold uppercase tracking-widest text-n-slate-10"
          >
            {{ $t('RAMON.LEAD_PANEL.ANDAMENTO.TITLE') }}
          </p>
          <p class="mt-1 text-[13px] font-semibold text-n-iris-11">
            {{ stageName || '—' }}
          </p>
          <MiniEsteira class="mt-2" :stages="stages" :current-id="stageId" />
          <p v-if="andamentoApoio" class="mt-1.5 text-xs text-n-slate-11">
            {{ andamentoApoio }}
          </p>
        </div>

        <!-- Próximo passo (era LeadNextAction do header) -->
        <LeadNextAction :lead-id="lead.id" />

        <!-- Temperatura (só na conversa; heurística local) -->
        <div
          v-if="inConversation && nivel"
          :class="CARD"
          data-testid="panel-card-termometro"
        >
          <p
            class="text-[10.5px] font-semibold uppercase tracking-widest text-n-slate-10"
          >
            {{ $t('RAMON.TERMOMETRO.TITLE') }}
          </p>
          <div class="mt-2 flex items-center gap-2">
            <div
              class="relative h-1.5 flex-1 rounded-full bg-gradient-to-r from-n-ruby-9 via-n-amber-9 to-n-teal-9 opacity-80"
            >
              <span
                class="absolute -top-1 h-3.5 w-1 rounded bg-n-slate-12"
                :style="{
                  left:
                    nivel === 'quente'
                      ? '85%'
                      : nivel === 'morna'
                        ? '48%'
                        : '10%',
                }"
              />
            </div>
            <span
              class="text-[11px] font-bold uppercase"
              :class="
                nivel === 'quente'
                  ? 'text-n-teal-11'
                  : nivel === 'morna'
                    ? 'text-n-amber-11'
                    : 'text-n-ruby-11'
              "
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
          <p class="text-[12.5px] font-bold text-n-ruby-11">
            {{ $t('RAMON.RISCO.TITLE') }}
          </p>
          <p class="mt-0.5 text-xs text-n-slate-11">
            {{
              $t('RAMON.RISCO.APOIO', {
                days: daysInStage ?? 0,
                count: Number(lead.follow_up_count) || 0,
              })
            }}
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

        <!-- Documentos -->
        <button
          v-if="lead.thesis_id && lead.docs_total"
          :class="CARD"
          class="text-left w-full hover:border-n-iris-9/40"
          data-testid="panel-card-docs"
          @click="setTab('documentos')"
        >
          <div class="flex items-center justify-between">
            <p
              class="text-[10.5px] font-semibold uppercase tracking-widest text-n-slate-10"
            >
              {{ $t('RAMON.DOCS.TITLE') }}
            </p>
            <span class="text-xs font-semibold text-n-slate-12">
              {{
                $t('RAMON.DOCS.COUNT', {
                  received: lead.docs_received || 0,
                  total: lead.docs_total,
                })
              }}
            </span>
          </div>
          <div class="mt-2 h-1.5 rounded-full bg-n-alpha-2 overflow-hidden">
            <div class="h-full bg-n-iris-9" :style="{ width: `${docsPct}%` }" />
          </div>
        </button>

        <!-- Caso -->
        <div :class="CARD" data-testid="panel-card-caso">
          <p
            class="text-[10.5px] font-semibold uppercase tracking-widest text-n-slate-10"
          >
            {{ $t('RAMON.LEAD_PANEL.CASE_TITLE') }}
          </p>
          <p class="mt-1 text-[13px] font-semibold text-n-slate-12">
            {{
              [lead.thesis_name, lead.benefit_type_name]
                .filter(Boolean)
                .join(' · ') || '—'
            }}
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
              <p class="text-[13px] text-n-slate-12">
                {{ channelLabel || '—' }}
              </p>
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
              :class="
                contactOpen ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'
              "
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
            <div
              v-if="fieldsExpanded"
              ref="fieldsEl"
              data-testid="lead-all-fields"
            >
              <LeadFields :lead="lead" />
            </div>
          </div>
        </div>

        <div
          v-if="inConversation && conversationId"
          class="pt-3 border-t border-n-weak min-w-0"
        >
          <button
            data-testid="conversation-extras-toggle"
            class="flex items-center w-full gap-1.5 text-[10.5px] font-semibold uppercase tracking-[.1em] text-n-slate-10 hover:text-n-slate-12"
            @click="conversationExtrasOpen = !conversationExtrasOpen"
          >
            {{ $t('RAMON.LEAD_PANEL.CONVERSATION_EXTRAS') }}
            <span
              class="size-3.5 shrink-0"
              :class="
                conversationExtrasOpen
                  ? 'i-lucide-chevron-up'
                  : 'i-lucide-chevron-down'
              "
            />
          </button>
          <div
            v-if="conversationExtrasOpen"
            class="flex flex-col gap-2 mt-3 min-w-0"
          >
            <ConversationAction :conversation-id="conversationId" />
            <div class="pt-3 border-t border-n-weak">
              <p
                class="mb-2 text-[10.5px] font-semibold uppercase tracking-[.1em] text-n-slate-10"
              >
                {{ $t('RAMON.LEAD_PANEL.MACROS_TITLE') }}
              </p>
              <MacrosList :conversation-id="conversationId" />
            </div>
          </div>
        </div>

        <div v-if="inConversation" class="pt-3 border-t border-n-weak">
          <button
            v-if="!discardPrompt"
            class="inline-flex items-center gap-1 rounded-full bg-n-ruby-9/10 px-2.5 py-1 text-[11px] text-n-ruby-11 hover:bg-n-ruby-9/20"
            data-testid="lead-discard"
            @click="discardPrompt = true"
          >
            <span class="i-lucide-user-x size-3 shrink-0" />
            {{ $t('RAMON.LEAD_PANEL.DISCARD') }}
          </button>
          <div
            v-else
            data-testid="lead-discard-prompt"
            class="flex flex-col gap-2 p-2 rounded-lg bg-n-alpha-1 border border-n-weak"
          >
            <p class="text-xs text-n-slate-11">
              {{ $t('RAMON.LEAD_PANEL.DISCARD_CONFIRM') }}
            </p>
            <div class="flex justify-end gap-2">
              <button
                data-testid="lead-discard-cancel"
                class="px-3 py-1 text-xs text-n-slate-11"
                @click="discardPrompt = false"
              >
                {{ $t('RAMON.FUNIL.CANCEL') }}
              </button>
              <button
                data-testid="lead-discard-confirm"
                class="px-3 py-1 text-xs rounded-lg bg-n-ruby-9 text-white disabled:opacity-50"
                :disabled="discarding"
                @click="discard"
              >
                {{ $t('RAMON.LEAD_PANEL.DISCARD') }}
              </button>
            </div>
          </div>
        </div>
      </template>

      <LeadPlaybook v-else-if="shownTab === 'playbook'" :lead="lead" />

      <template v-else-if="shownTab === 'ia'">
        <div>
          <p
            class="mb-2 text-xs font-semibold uppercase tracking-widest text-n-slate-9"
          >
            {{ $t('RAMON.TRIAGE.TAB') }}
          </p>
          <LeadTriage :lead="lead" />
        </div>
        <div class="pt-3 border-t border-n-weak">
          <p
            class="mb-2 text-xs font-semibold uppercase tracking-widest text-n-slate-9"
          >
            {{ $t('RAMON.KIT.TAB') }}
          </p>
          <LeadKit :lead="lead" />
        </div>
        <LeadCopilot
          v-if="inConversation && conversationId"
          :conversation-id="conversationId"
          class="pt-3 border-t border-n-weak"
        />
      </template>

      <LeadSimulador v-else-if="shownTab === 'simulador'" :lead="lead" />

      <div v-else-if="shownTab === 'documentos'" class="flex flex-col gap-3">
        <DocChecklist :lead="lead" :context="context" />
      </div>

      <LeadZapsignCard
        v-else-if="shownTab === 'contrato'"
        :lead="lead"
        @complete-data="onCompleteData"
      />

      <LeadHistory v-else-if="shownTab === 'historico'" :lead-id="lead.id" />
    </div>
  </div>
</template>
