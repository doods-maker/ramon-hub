<script setup>
// Redesign v2 (mockup .painel): blocos Etapa / Próximo passo / Risco no topo e
// o resto em linhas recolhíveis — as antigas abas viraram seções, nada sumiu.
import { ref, computed, watch, nextTick, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import ConversationAction from 'dashboard/routes/dashboard/conversation/ConversationAction.vue';
import MacrosList from 'dashboard/routes/dashboard/conversation/Macros/List.vue';
import LeadFields from './LeadFields.vue';
import LeadNextAction from './LeadNextAction.vue';
import MiniEsteira from './MiniEsteira.vue';
import { DEFAULT_STAGE_COLOR } from '../../helpers/stage';
import LeadNotes from './LeadNotes.vue';
import LeadQuizResumo from './LeadQuizResumo.vue';
import LeadZapsignCard from './LeadZapsignCard.vue';
import LostReasonModal from '../kanban/LostReasonModal.vue';
import LeadCopilot from '../conversation/LeadCopilot.vue';
import LeadHistory from '../conversation/LeadHistory.vue';
import LeadPlaybook from '../conversation/LeadPlaybook.vue';
import LeadSimulador from '../conversation/LeadSimulador.vue';
import DocChecklist from './DocChecklist.vue';
import QualificacaoViva from './QualificacaoViva.vue';
import SecaoRecolhivel from './SecaoRecolhivel.vue';
import { useLeadPanelSecoes } from '../../composables/useLeadPanelSections';
import { BTN_CHEIO, BTN_LINHA } from '../hoje/hoje';
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
    return t('RAMON.KANBAN.CARD.PRESCRIPTION_BLEEDING', {
      value: formatBrl(p.monthlyValue),
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

// Pílula de etapa na cor da etapa (classe .ramon-stage-pill lê --stage);
// sem cor configurada, cinza neutro.
const stageChipStyle = computed(() => ({
  '--stage':
    stages.value?.find(s => s.id === stageId.value)?.color ||
    DEFAULT_STAGE_COLOR,
}));

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
// Apoio do bloco Etapa: a reunião marcada ("Quinta, 10:00 · com Camila") ou a tese.
const tarefasDoLead = useMapGetter('leadTasks/getByLead');
const temTarefa = computed(
  () => (tarefasDoLead.value?.(props.lead?.id) || []).length > 0
);
const reuniao = computed(() =>
  (tarefasDoLead.value?.(props.lead?.id) || []).find(
    tarefa => tarefa.kind === 'meeting' && tarefa.due_at
  )
);
const etapaApoio = computed(() => {
  if (!reuniao.value) return props.lead?.thesis_name || null;
  const d = new Date(reuniao.value.due_at);
  const dia = d
    .toLocaleDateString('pt-BR', { weekday: 'long' })
    .replace('-feira', '');
  const hora = d.toLocaleTimeString('pt-BR', {
    hour: '2-digit',
    minute: '2-digit',
  });
  const com = props.lead?.closer_name
    ? t('RAMON.HOJE.COM', { nome: props.lead.closer_name })
    : t('RAMON.HOJE.COM_O_CLOSER');
  return `${dia.charAt(0).toUpperCase()}${dia.slice(1)}, ${hora} · ${com}`;
});
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

// ----- seções recolhíveis (eram abas) -----
const { abertas, alternar, abrir } = useLeadPanelSecoes();
const aberta = id => abertas.value.includes(id);
const DADO = 'flex justify-between gap-3 py-1 text-[13px]';
const simuladorDot = computed(() =>
  props.lead?.custom_attributes?.ultima_simulacao ? 'bg-n-teal-9' : null
);
const docsContagem = computed(() =>
  props.lead?.docs_total
    ? `${props.lead.docs_received || 0}/${props.lead.docs_total}`
    : null
);
// Qualificação N/M: mesmos critérios do QualificacaoViva (itens da tese).
const theses = useMapGetter('theses/getTheses');
const qualificacaoContagem = computed(() => {
  const criterios = (
    theses.value?.find(x => x.id === props.lead?.thesis_id)?.items || []
  ).filter(item => item.section === 'qualificacao');
  if (!criterios.length) return null;
  const status = props.lead?.custom_attributes?.qualificacao_status || {};
  const ok = criterios.filter(item => status[item.id] === 'ok').length;
  return `${ok}/${criterios.length}`;
});

// ----- "editar todos os campos": LeadFields completo recolhido por padrão -----
const fieldsExpanded = ref(false);
const fieldsEl = ref(null);
const onCompleteData = async () => {
  abrir('contato');
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
  <div
    class="flex h-full min-w-0 flex-1 flex-col overflow-y-auto overflow-x-hidden"
  >
    <!-- gaveta do Kanban: o nome (na conversa ele já está no cabeçalho) -->
    <div v-if="!inConversation" class="px-[18px] pt-4">
      <h2
        class="truncate text-[21px] font-semibold leading-tight text-n-slate-12"
      >
        {{ lead.name }}
      </h2>
    </div>

    <!-- Etapa: pílula grande (é o seletor), mini-esteira na cor da etapa -->
    <section
      class="border-b border-n-weak px-[18px] py-4"
      :style="stageChipStyle"
      data-testid="panel-card-andamento"
    >
      <h3 class="mb-2 flex justify-between text-xs font-medium text-n-slate-9">
        {{ $t('RAMON.LEAD_PANEL.ETAPA') }}
        <span v-if="daysInStage != null" class="font-mono text-xs">
          {{ $t('RAMON.LEAD_PANEL.HA_DIAS', { n: daysInStage }, daysInStage) }}
        </span>
      </h3>
      <label
        class="ramon-stage-pill relative inline-flex max-w-full cursor-pointer items-center gap-1.5 rounded-full px-3 py-1.5 text-[13px] font-medium leading-none"
      >
        <span class="size-1.5 flex-shrink-0 rounded-full bg-current" />
        <span class="truncate">{{ stageName || '—' }}</span>
        <!-- select transparente por cima: abre o seletor nativo -->
        <select
          data-testid="panel-stage"
          :value="stageId"
          :aria-label="$t('RAMON.LEAD_PANEL.ETAPA')"
          class="absolute inset-0 !m-0 h-full w-full cursor-pointer opacity-0"
          @change="e => onStageChange(Number(e.target.value))"
        >
          <option v-for="s in stages" :key="s.id" :value="s.id">
            {{ s.name }}
          </option>
        </select>
      </label>
      <MiniEsteira :stages="stages" :current-id="stageId" />
      <p v-if="etapaApoio" class="text-[12.5px] text-n-slate-11">
        {{ etapaApoio }}
      </p>
      <div
        v-if="prescriptionLabel || formattedValue || probability != null"
        class="mt-2 flex flex-wrap items-center gap-1.5"
      >
        <span
          v-if="prescriptionLabel"
          data-testid="panel-prescription-chip"
          class="inline-flex items-center gap-1 rounded-full px-2 py-1 text-[11.5px] font-medium leading-none"
          :class="
            bleeding
              ? 'bg-n-ruby-9/10 text-n-ruby-11'
              : 'bg-n-amber-9/15 text-n-amber-11'
          "
        >
          <span class="i-lucide-hourglass size-3" />
          {{ prescriptionLabel }}
        </span>
        <span
          v-if="formattedValue"
          data-testid="panel-value-chip"
          class="inline-flex items-center gap-1 rounded-full bg-n-slate-3 px-2 py-1 font-mono text-[11.5px] leading-none text-n-slate-11"
        >
          {{ formattedValue }}
          <span
            v-if="valorEstimadoAuto"
            data-testid="value-auto-badge"
            :title="$t('RAMON.DRAWER.VALUE_AUTO_TIP')"
            class="inline-flex items-center gap-0.5 rounded bg-n-blue-9/[0.08] px-1 font-sans text-[10px] text-n-blue-11 dark:bg-n-blue-9/[0.16]"
          >
            <span class="i-lucide-sparkles size-2.5" />{{
              $t('RAMON.DRAWER.VALUE_AUTO')
            }}
          </span>
        </span>
        <span
          v-if="probability != null"
          class="font-mono text-[11.5px] text-n-slate-9"
        >
          {{ `${probability}%` }}
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
        class="mt-3 flex flex-col gap-2 rounded-[10px] border border-n-weak p-3"
      >
        <label class="text-xs text-n-slate-11">{{
          $t('RAMON.FUNIL.WON.VALUE_LABEL')
        }}</label>
        <input
          v-model="wonValue"
          data-testid="stage-won-value"
          type="text"
          inputmode="decimal"
          class="!mb-0 w-full rounded-[7px] border border-n-strong bg-transparent px-2 py-1.5 font-mono text-sm text-n-slate-12 outline-none focus:border-n-blue-9"
          @keyup.enter="confirmWonStage"
        />
        <div class="flex justify-end gap-2">
          <button
            data-testid="stage-won-skip"
            :class="BTN_LINHA"
            @click="skipWonStage"
          >
            {{ $t('RAMON.FUNIL.WON.SKIP') }}
          </button>
          <button
            data-testid="stage-won-save"
            :class="BTN_CHEIO"
            @click="confirmWonStage"
          >
            {{ $t('RAMON.FUNIL.WON.SAVE') }}
          </button>
        </div>
      </div>
    </section>

    <!-- Próximo passo: tarefa aberta + Abrir ficha / Follow-up -->
    <section
      class="border-b border-n-weak bg-n-blue-9/[0.08] px-[18px] py-4 dark:bg-n-blue-9/[0.16]"
      data-testid="panel-proximo-passo"
    >
      <h3 class="mb-2 text-xs font-semibold text-n-blue-11">
        {{ $t('RAMON.LEAD_PANEL.NEXT_ACTION.TITLE') }}
      </h3>
      <LeadNextAction :lead-id="lead.id" />
      <p v-if="!temTarefa" class="text-[12.5px] text-n-slate-11">
        {{ $t('RAMON.FICHA.NEXT_EMPTY') }}
      </p>
      <div class="mt-3 flex flex-wrap gap-2">
        <router-link
          v-if="lead?.id"
          data-testid="lead-abrir-ficha"
          :to="{ name: 'ramon_lead_dossie', params: { leadId: lead.id } }"
          :class="BTN_CHEIO"
          @click="emit('navigate')"
        >
          {{ $t('RAMON.LEAD_PANEL.ABRIR_FICHA') }}
        </router-link>
        <button
          data-testid="panel-add-task"
          :class="BTN_LINHA"
          @click="taskFormOpen = !taskFormOpen"
        >
          {{ $t('RAMON.LEAD_PANEL.FOLLOW_UP') }}
        </button>
        <!-- WhatsApp: abre a conversa (gaveta) ou o wa.me (sem conversa); na
             conversa ela já está aberta — botão sai. -->
        <button
          v-if="lead.conversation_id && !inConversation"
          data-testid="panel-whatsapp"
          :class="BTN_LINHA"
          @click="emit('openConversation', lead.conversation_id)"
        >
          <span class="i-lucide-message-square size-4" />{{
            $t('RAMON.KANBAN.CARD.WHATSAPP')
          }}
        </button>
        <a
          v-else-if="!lead.conversation_id && lead.contact_phone"
          data-testid="panel-whatsapp-wa-me"
          :href="waMeUrl(lead.contact_phone)"
          target="_blank"
          rel="noopener noreferrer"
          :class="BTN_LINHA"
        >
          <span class="i-lucide-message-square size-4" />{{
            $t('RAMON.KANBAN.CARD.WHATSAPP')
          }}
        </a>
      </div>
      <div
        v-if="taskFormOpen"
        data-testid="panel-task-form"
        class="mt-3 flex flex-col gap-2"
      >
        <input
          v-model="taskTitle"
          data-testid="panel-task-title"
          :placeholder="$t('RAMON.TASKS.ADD_TITLE_PLACEHOLDER')"
          class="!mb-0 w-full rounded-[7px] border border-n-strong bg-n-background px-2 py-1.5 text-sm text-n-slate-12 outline-none focus:border-n-blue-9"
        />
        <input
          v-model="taskDate"
          data-testid="panel-task-date"
          type="datetime-local"
          :title="$t('RAMON.TASKS.DATE_HINT')"
          class="!mb-0 w-full rounded-[7px] border border-n-strong bg-n-background px-2 py-1.5 font-mono text-sm text-n-slate-12 outline-none focus:border-n-blue-9"
        />
        <div class="flex justify-end gap-2">
          <button
            data-testid="panel-task-cancel"
            :class="BTN_LINHA"
            @click="taskFormOpen = false"
          >
            {{ $t('RAMON.FUNIL.CANCEL') }}
          </button>
          <button
            data-testid="panel-task-save"
            :class="BTN_CHEIO"
            class="disabled:opacity-50"
            :disabled="savingTask"
            @click="addTask"
          >
            {{ $t('RAMON.FUNIL.SAVE') }}
          </button>
        </div>
      </div>
    </section>

    <!-- Risco de esfriar (stalled) -->
    <section
      v-if="risco"
      class="border-b border-n-weak bg-n-ruby-9/10 px-[18px] py-4 shadow-[inset_4px_0_0_rgb(var(--ruby-9))]"
      data-testid="panel-card-risco"
    >
      <p
        class="flex items-center gap-1.5 text-[13px] font-semibold text-n-ruby-11"
      >
        <span class="i-lucide-triangle-alert size-4" />
        {{ $t('RAMON.RISCO.TITLE') }}
      </p>
      <p class="mt-0.5 text-[12.5px] text-n-slate-12">
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
        class="mt-2 text-xs font-medium text-n-blue-11 underline underline-offset-2 disabled:opacity-50"
        :disabled="followUpPending"
        @click="prepararRetomada"
      >
        {{ $t('RAMON.RISCO.PREPARAR') }}
      </button>
    </section>

    <!-- linhas recolhíveis (eram as abas Resumo/Playbook/Simulador/…) -->
    <SecaoRecolhivel
      v-if="lead.thesis_id"
      data-testid="secao-qualificacao"
      :titulo="$t('RAMON.LEAD_PANEL.QUALIFICACAO')"
      :contagem="qualificacaoContagem"
      :aberta="aberta('qualificacao')"
      @alternar="alternar('qualificacao')"
    >
      <div class="flex flex-col gap-3">
        <QualificacaoViva :lead="lead" :context="context" />
        <LeadQuizResumo :lead="lead" />
      </div>
    </SecaoRecolhivel>
    <LeadQuizResumo v-else :lead="lead" class="px-[18px] py-3" />

    <SecaoRecolhivel
      v-if="lead.thesis_id"
      data-testid="secao-documentos"
      :titulo="$t('RAMON.DOCS.TITLE')"
      :contagem="docsContagem"
      :aberta="aberta('documentos')"
      @alternar="alternar('documentos')"
    >
      <DocChecklist :lead="lead" :context="context" />
    </SecaoRecolhivel>

    <SecaoRecolhivel
      data-testid="secao-calculos"
      :titulo="$t('RAMON.FICHA.CALCULOS_TITLE')"
      :ponto="simuladorDot"
      :aberta="aberta('calculos')"
      @alternar="alternar('calculos')"
    >
      <LeadSimulador :lead="lead" />
    </SecaoRecolhivel>

    <SecaoRecolhivel
      v-if="inConversation && conversationId"
      data-testid="secao-copiloto"
      :titulo="$t('RAMON.LEAD_PANEL.COPILOTO')"
      :aberta="aberta('copiloto')"
      @alternar="alternar('copiloto')"
    >
      <LeadCopilot :conversation-id="conversationId" />
    </SecaoRecolhivel>

    <SecaoRecolhivel
      data-testid="secao-playbook"
      :titulo="$t('RAMON.LEAD_PANEL.TABS.PLAYBOOK')"
      :aberta="aberta('playbook')"
      @alternar="alternar('playbook')"
    >
      <LeadPlaybook :lead="lead" />
    </SecaoRecolhivel>

    <SecaoRecolhivel
      data-testid="secao-contrato"
      :titulo="$t('RAMON.LEAD_PANEL.TABS.CONTRACT')"
      :aberta="aberta('contrato')"
      @alternar="alternar('contrato')"
    >
      <LeadZapsignCard :lead="lead" @complete-data="onCompleteData" />
    </SecaoRecolhivel>

    <SecaoRecolhivel
      data-testid="secao-notas"
      :titulo="$t('RAMON.LEAD_PANEL.NOTES.TITLE')"
      :aberta="aberta('notas')"
      @alternar="alternar('notas')"
    >
      <LeadNotes :lead-id="lead.id" />
    </SecaoRecolhivel>

    <SecaoRecolhivel
      data-testid="secao-historico"
      :titulo="$t('RAMON.LEAD_PANEL.TABS.HISTORY')"
      :aberta="aberta('historico')"
      @alternar="alternar('historico')"
    >
      <LeadHistory :lead-id="lead.id" />
    </SecaoRecolhivel>

    <!-- Temperatura (só na conversa; heurística local) -->
    <SecaoRecolhivel
      v-if="inConversation && nivel"
      data-testid="panel-card-termometro"
      :titulo="$t('RAMON.TERMOMETRO.TITLE')"
      :contagem="$t(`RAMON.TERMOMETRO.${nivel.toUpperCase()}`)"
      :aberta="aberta('temperatura')"
      @alternar="alternar('temperatura')"
    >
      <div
        class="relative h-1.5 rounded-full bg-gradient-to-r from-n-ruby-9 via-n-amber-9 to-n-teal-9 opacity-80"
      >
        <span
          class="absolute -top-1 h-3.5 w-1 rounded bg-n-slate-12"
          :class="{
            'left-[85%]': nivel === 'quente',
            'left-[48%]': nivel === 'morna',
            'left-[10%]': nivel === 'fria',
          }"
        />
      </div>
      <p v-if="hesitando" class="mt-1.5 text-xs text-n-slate-11">
        {{ $t('RAMON.TERMOMETRO.HESITANDO') }}
      </p>
    </SecaoRecolhivel>

    <!-- Dados do contato: caso, telefone/CPF/donos e todos os campos -->
    <SecaoRecolhivel
      data-testid="contact-data-toggle"
      :titulo="$t('RAMON.LEAD_PANEL.CONTACT_DATA')"
      :aberta="aberta('contato')"
      @alternar="alternar('contato')"
    >
      <div class="flex min-w-0 flex-col">
        <div :class="DADO">
          <span class="text-n-slate-9">
            {{ $t('RAMON.LEAD_PANEL.CASE_TITLE') }}
          </span>
          <span class="text-right text-n-slate-12">
            {{
              [lead.thesis_name, lead.benefit_type_name]
                .filter(Boolean)
                .join(' · ') || '—'
            }}
          </span>
        </div>
        <div :class="DADO">
          <span class="text-n-slate-9">
            {{ $t('RAMON.LEAD_PANEL.FIELDS.DCB') }}
          </span>
          <span
            data-testid="panel-dcb"
            class="font-mono"
            :class="bleeding ? 'text-n-ruby-11' : 'text-n-slate-12'"
          >
            {{ dcbFormatted || '—' }}
          </span>
        </div>
        <div :class="DADO">
          <span class="text-n-slate-9">
            {{ $t('RAMON.LEAD_PANEL.FIELDS.CHANNEL') }}
          </span>
          <span class="text-n-slate-12">{{ channelLabel || '—' }}</span>
        </div>
        <div :class="DADO">
          <span class="text-n-slate-9">
            {{ $t('RAMON.LEAD_PANEL.FIELDS.PHONE') }}
          </span>
          <span class="font-mono text-n-slate-12">
            {{ lead.contact_phone || '—' }}
          </span>
        </div>
        <div :class="DADO">
          <span class="text-n-slate-9">
            {{ $t('RAMON.LEAD_PANEL.FIELDS.CPF') }}
          </span>
          <span class="font-mono text-n-slate-12">
            {{ formatCpf(lead.contact_cpf) || '—' }}
          </span>
        </div>
        <div :class="DADO">
          <span class="text-n-slate-9">
            {{ $t('RAMON.LEAD_PANEL.FIELDS.OWNERS') }}
          </span>
          <span class="text-n-slate-12">{{ owners || '—' }}</span>
        </div>
        <button
          data-testid="lead-edit-all-toggle"
          class="mt-2 self-start text-xs text-n-blue-11 hover:underline"
          @click="fieldsExpanded = !fieldsExpanded"
        >
          {{
            fieldsExpanded
              ? $t('RAMON.LEAD_PANEL.EDIT_ALL_FIELDS_CLOSE')
              : $t('RAMON.LEAD_PANEL.EDIT_ALL_FIELDS')
          }}
        </button>
        <div v-if="fieldsExpanded" ref="fieldsEl" data-testid="lead-all-fields">
          <LeadFields :lead="lead" />
        </div>
      </div>
    </SecaoRecolhivel>

    <!-- seções nativas do Chatwoot (agente/time/prioridade/etiquetas/macros) -->
    <SecaoRecolhivel
      v-if="inConversation && conversationId"
      data-testid="conversation-extras-toggle"
      :titulo="$t('RAMON.LEAD_PANEL.CONVERSATION_EXTRAS')"
      :aberta="aberta('conversa')"
      @alternar="alternar('conversa')"
    >
      <div class="flex min-w-0 flex-col gap-2">
        <ConversationAction :conversation-id="conversationId" />
        <div class="border-t border-n-weak pt-3">
          <p class="mb-2 text-xs font-medium text-n-slate-9">
            {{ $t('RAMON.LEAD_PANEL.MACROS_TITLE') }}
          </p>
          <MacrosList :conversation-id="conversationId" />
        </div>
      </div>
    </SecaoRecolhivel>

    <!-- "Não é lead" (destrutivo: confirmação inline, só na conversa) -->
    <div v-if="inConversation" class="px-[18px] py-4">
      <button
        v-if="!discardPrompt"
        class="inline-flex items-center gap-1 text-xs text-n-ruby-11 hover:underline"
        data-testid="lead-discard"
        @click="discardPrompt = true"
      >
        <span class="i-lucide-user-x size-3.5 shrink-0" />
        {{ $t('RAMON.LEAD_PANEL.DISCARD') }}
      </button>
      <div
        v-else
        data-testid="lead-discard-prompt"
        class="flex flex-col gap-2 rounded-[10px] bg-n-ruby-9/10 p-3"
      >
        <p class="text-xs text-n-slate-12">
          {{ $t('RAMON.LEAD_PANEL.DISCARD_CONFIRM') }}
        </p>
        <div class="flex justify-end gap-2">
          <button
            data-testid="lead-discard-cancel"
            :class="BTN_LINHA"
            @click="discardPrompt = false"
          >
            {{ $t('RAMON.FUNIL.CANCEL') }}
          </button>
          <button
            data-testid="lead-discard-confirm"
            class="rounded-[7px] bg-n-ruby-9 px-2.5 py-[5px] text-[12.5px] font-medium text-white disabled:opacity-50"
            :disabled="discarding"
            @click="discard"
          >
            {{ $t('RAMON.LEAD_PANEL.DISCARD') }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
