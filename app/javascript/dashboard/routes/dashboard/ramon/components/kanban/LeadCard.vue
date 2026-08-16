<script setup>
import { computed, onMounted, onUnmounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { formatBrl, brlCompact } from '../../helpers/currency';
import { prescriptionInfo } from '../../helpers/prescription';
import TaskBellMenu from './TaskBellMenu.vue';

const props = defineProps({
  lead: { type: Object, required: true },
  focused: { type: Boolean, default: false },
  // Seleção em lote (visual por ora — a store de seleção chega em outra fase).
  selectable: { type: Boolean, default: false },
  selected: { type: Boolean, default: false },
});
const emit = defineEmits([
  'openConversation',
  'openLead',
  'openDossie',
  'toggleSelect',
]);

const cardEl = ref(null);
watch(
  () => props.focused,
  isFocused => {
    if (isFocused)
      cardEl.value?.scrollIntoView({ block: 'nearest', inline: 'nearest' });
  }
);

const { t } = useI18n();
// useStore não lança fora de um app com store (retorna undefined); leituras de
// getters/dispatch ficam defensivas para o card renderizar em testes sem store.
const store = useStore();

// Valor compacto dourado ("R$ 38 mil") — traço quando não há valor.
const compactValue = computed(() => {
  const v = props.lead.value;
  if (v === null || v === undefined || v === '') return null;
  return brlCompact(v);
});

// Prescrição: sangramento (parcelas já prescritas) vira texto ruby na linha 2.
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

const ownerName = computed(
  () => props.lead.closer_name || props.lead.sdr_name || null
);
const ownerInitials = computed(() => {
  if (!ownerName.value) return null;
  return ownerName.value
    .trim()
    .split(/\s+/)
    .map(word => word[0])
    .slice(0, 2)
    .join('')
    .toUpperCase();
});

// Etapa do lead a partir do leadConfig (para stalled_after_days e won/lost).
const stage = computed(() => {
  const stages = store?.getters?.['leadConfig/getStages'] || [];
  return stages.find(s => s.id === props.lead.lead_stage_id) || null;
});

// Idade na etapa em dias inteiros; "hoje" = 0d. null quando não há data.
const daysInStage = computed(() => {
  const entered = props.lead.stage_entered_at;
  if (!entered) return null;
  const diff = Date.now() - new Date(entered).getTime();
  if (Number.isNaN(diff)) return null;
  return Math.max(0, Math.floor(diff / 86400000));
});

// SLA de 1º contato (mock 3a): relógio de 30s para o timer regressivo andar
// sem re-fetch. Cleanup no unmounted (regra do fork para timers).
const now = ref(Date.now());
let slaTimer = null;
onMounted(() => {
  slaTimer = setInterval(() => {
    now.value = Date.now();
  }, 30000);
});
onUnmounted(() => clearInterval(slaTimer));

// "41min" / "2h 47min" — mesmo formato do mock.
const formatDuration = ms => {
  const minutes = Math.max(0, Math.round(ms / 60000));
  const hours = Math.floor(minutes / 60);
  return hours ? `${hours}h ${minutes % 60}min` : `${minutes}min`;
};

// 1ª etapa do funil (menor position): depois de respondido, o pill teal só
// faz sentido enquanto o lead ainda está na coluna de entrada.
const firstStageId = computed(() => {
  const stages = store?.getters?.['leadConfig/getStages'] || [];
  if (!stages.length) return null;
  return [...stages].sort((a, b) => (a.position ?? 0) - (b.position ?? 0))[0]
    .id;
});

// Estado do SLA a partir de lead.sla { due_at, replied_at, minutes }.
const slaState = computed(() => {
  const sla = props.lead.sla;
  if (!sla?.due_at) return null;
  const due = new Date(sla.due_at).getTime();
  if (Number.isNaN(due)) return null;
  if (sla.replied_at) {
    // fora da 1ª etapa, respondido = história antiga; some do card
    if (
      firstStageId.value !== null &&
      props.lead.lead_stage_id !== firstStageId.value
    )
      return null;
    const startedAt = due - (Number(sla.minutes) || 0) * 60000;
    return {
      kind: 'replied',
      time: formatDuration(new Date(sla.replied_at).getTime() - startedAt),
    };
  }
  if (now.value < due)
    return { kind: 'within', time: formatDuration(due - now.value) };
  return { kind: 'overdue', time: formatDuration(now.value - due) };
});
const slaOverdue = computed(() => slaState.value?.kind === 'overdue');

// Pill: âmbar regressivo dentro do SLA, ruby sólido estourado, teal respondido.
const slaPill = computed(() => {
  const state = slaState.value;
  if (!state) return null;
  if (state.kind === 'replied')
    return {
      class: 'bg-n-teal-9/20 text-n-teal-11',
      label: t('RAMON.KANBAN.SLA.REPLIED_IN', { time: state.time }),
      title: null,
    };
  if (state.kind === 'within')
    return {
      class: 'bg-n-amber-9/20 text-n-amber-11',
      label: state.time,
      title: t('RAMON.KANBAN.SLA.REMAINING', { time: state.time }),
    };
  return {
    class: 'bg-n-ruby-9 text-white',
    label: state.time,
    title: t('RAMON.KANBAN.SLA.OVERDUE_SINCE', { time: state.time }),
  };
});

// Risco = borda ESQUERDA 3px: ruby (prescrevendo / apodrecendo forte / SLA
// estourado) tem prioridade sobre âmbar (parado). O hover bronze re-afirma a
// cor da esquerda para nunca apagar o sinal de risco.
const riskClass = computed(() => {
  const limit = stage.value?.stalled_after_days;
  const rotten =
    limit != null && daysInStage.value != null && daysInStage.value > 2 * limit;
  if (prescription.value?.lostInstallments > 0 || rotten || slaOverdue.value)
    return 'border-l-[3px] border-l-n-ruby-9 hover:border-l-n-ruby-9';
  if (props.lead.stalled)
    return 'border-l-[3px] border-l-n-amber-9 hover:border-l-n-amber-9';
  return '';
});

// Badge de retomadas (cadência de follow-up): tooltip com a data da última.
const followUpTitle = computed(() => {
  const count = Number(props.lead.follow_up_count) || 0;
  if (!count) return null;
  const last = props.lead.follow_up_last_at
    ? new Date(props.lead.follow_up_last_at)
    : null;
  if (!last || Number.isNaN(last.getTime()))
    return t('RAMON.FOLLOW_UP.CARD_TITLE_NO_DATE', { count });
  return t('RAMON.FOLLOW_UP.CARD_TITLE', {
    count,
    date: last.toLocaleDateString('pt-BR', {
      day: '2-digit',
      month: '2-digit',
    }),
  });
});

// Próxima ação com dot semântico: vencida = ruby, hoje = âmbar, futura = teal.
const nextAction = computed(() => {
  const raw = props.lead.next_task_due_at;
  if (!raw) return null;
  const due = new Date(raw);
  if (Number.isNaN(due.getTime())) return null;
  const title = props.lead.next_task_title || '';
  if (due.getTime() < Date.now())
    return {
      dot: 'bg-n-ruby-9',
      text: 'text-n-ruby-11',
      label: t('RAMON.KANBAN.CARD.NEXT_OVERDUE', { title }),
    };
  const startOfToday = new Date();
  startOfToday.setHours(0, 0, 0, 0);
  const days = Math.floor((due.getTime() - startOfToday.getTime()) / 86400000);
  if (days === 0)
    return {
      dot: 'bg-n-amber-9',
      text: 'text-n-amber-11',
      label: t('RAMON.KANBAN.CARD.NEXT_TODAY', { title }),
    };
  if (days === 1)
    return {
      dot: 'bg-n-teal-9',
      text: 'text-n-teal-11',
      label: t('RAMON.KANBAN.CARD.NEXT_TOMORROW', { title }),
    };
  return {
    dot: 'bg-n-teal-9',
    text: 'text-n-teal-11',
    label: t('RAMON.KANBAN.CARD.NEXT_IN_DAYS', { days, title }),
  };
});

// "Sem próxima ação": nenhuma tarefa aberta e etapa ainda ativa (nem won/lost).
const showNoNextAction = computed(
  () =>
    props.lead.open_tasks_count === 0 &&
    !stage.value?.is_won &&
    !stage.value?.is_lost
);

const onSchedule = async ({ dueAt, title }) => {
  try {
    await store.dispatch('leadTasks/create', {
      leadId: props.lead.id,
      title,
      kind: 'follow_up',
      dueAt,
    });
    useAlert(t('RAMON.KANBAN.CARD.TASK_SCHEDULED'));
  } catch (e) {
    useAlert(t('RAMON.TASKS.CREATE_ERROR'));
  }
};
</script>

<template>
  <div
    ref="cardEl"
    class="group px-3 py-2.5 mb-1.5 rounded-xl bg-n-solid-1 shadow-sm border border-n-weak cursor-pointer transition duration-150 hover:border-n-iris-8 active:scale-[0.97]"
    :class="[riskClass, { 'ring-2 ring-n-iris-9': focused }]"
    @click="emit('openLead', lead)"
  >
    <!-- Linha 1: checkbox de lote + nome + valor compacto dourado -->
    <div class="flex items-center gap-2">
      <button
        v-if="selectable"
        data-testid="select-toggle"
        class="flex items-center justify-center size-3.5 rounded shrink-0 border-[1.5px] transition duration-150"
        :class="selected ? 'bg-n-iris-9 border-n-iris-9' : 'border-n-slate-9'"
        @click.stop="emit('toggleSelect', lead)"
      >
        <span v-if="selected" class="i-lucide-check size-2.5 text-white" />
      </button>
      <button
        data-testid="lead-card-body"
        class="flex-1 min-w-0 text-left"
        @click.stop="emit('openLead', lead)"
      >
        <p class="text-sm font-medium truncate text-n-slate-12">
          {{ lead.name }}
        </p>
      </button>
      <!-- Timer do SLA de 1º contato (mock 3a), à direita do nome -->
      <span
        v-if="slaPill"
        data-testid="sla-pill"
        :title="slaPill.title || undefined"
        class="px-2 py-0.5 rounded-full text-[10.5px] font-semibold tabular-nums shrink-0"
        :class="slaPill.class"
      >
        {{ slaPill.label }}
      </span>
      <span
        data-testid="lead-value"
        class="text-xs tabular-nums shrink-0"
        :class="compactValue ? 'font-medium text-n-iris-11' : 'text-n-slate-10'"
      >
        {{ compactValue || '—' }}
      </span>
    </div>

    <!-- Linha 2: próxima ação com dot semântico + metadados discretos -->
    <div
      class="flex flex-wrap items-center gap-x-2 gap-y-1 mt-1.5 text-[11px] leading-4"
      :class="selectable ? 'pl-[22px]' : 'pl-0'"
    >
      <span
        v-if="nextAction"
        data-testid="next-action"
        class="inline-flex items-center gap-1"
        :class="nextAction.text"
      >
        <span class="rounded-full size-1.5" :class="nextAction.dot" />
        {{ nextAction.label }}
      </span>
      <span
        v-else-if="showNoNextAction"
        data-testid="no-next-action"
        class="inline-flex items-center gap-1 text-n-ruby-11"
      >
        <span class="rounded-full size-1.5 bg-n-ruby-9" />
        {{ $t('RAMON.KANBAN.CARD.NEXT_NONE') }}
      </span>
      <span
        v-if="prescriptionLabel"
        data-testid="prescription-badge"
        :class="
          prescription?.lostInstallments > 0
            ? 'text-n-ruby-11'
            : 'text-n-amber-11'
        "
      >
        {{ prescriptionLabel }}
      </span>
      <span
        v-if="lead.latest_triage?.status === 'awaiting_human'"
        data-testid="triage-awaiting-human-badge"
        :title="$t('RAMON.TRIAGE.AWAITING_HUMAN_HINT')"
        class="text-n-amber-11"
      >
        {{ $t('RAMON.KANBAN.CARD.TRIAGE_AWAITING_HUMAN') }}
      </span>
      <span
        v-if="daysInStage !== null"
        data-testid="stage-age"
        class="text-n-slate-10"
      >
        {{ $t('RAMON.KANBAN.CARD.AGE', { days: daysInStage }) }}
      </span>
      <span
        v-if="lead.follow_up_count > 0"
        data-testid="follow-up-badge"
        :title="followUpTitle"
        class="inline-flex items-center gap-0.5 text-n-slate-10"
      >
        <span class="i-lucide-history size-3" />{{ lead.follow_up_count }}
      </span>
      <span
        v-if="lead.docs_total > 0"
        data-testid="docs-badge"
        :title="
          $t('RAMON.DOCS.CARD_TITLE', {
            received: lead.docs_received,
            total: lead.docs_total,
          })
        "
        class="inline-flex items-center gap-0.5"
        :class="
          lead.docs_received >= lead.docs_total
            ? 'text-n-teal-11'
            : 'text-n-slate-10'
        "
      >
        <span class="i-lucide-file-check size-3" />{{ lead.docs_received }}/{{
          lead.docs_total
        }}
      </span>
      <span v-if="lead.benefit_type_name" class="text-n-slate-10">
        {{ lead.benefit_type_name }}
      </span>
      <span
        v-if="ownerInitials"
        :title="ownerName"
        class="text-n-slate-10 ms-auto"
      >
        {{ ownerInitials }}
      </span>
    </div>

    <!-- Ações rápidas: só no hover (o card fica denso no scan) -->
    <div
      class="hidden group-hover:flex items-center gap-1 mt-1.5"
      :class="selectable ? 'pl-[22px]' : 'pl-0'"
    >
      <!-- SLA estourado: CTA explícito de resposta (reusa a ação de conversa) -->
      <button
        v-if="slaOverdue && lead.conversation_id"
        data-testid="sla-respond-now"
        class="px-2 py-0.5 rounded-md text-[10.5px] font-semibold text-white bg-n-iris-9 hover:bg-n-iris-10"
        @click.stop="emit('openConversation', lead.conversation_id)"
      >
        {{ $t('RAMON.KANBAN.SLA.RESPOND_NOW') }}
      </button>
      <button
        v-if="lead.conversation_id"
        data-testid="open-conversation"
        :title="$t('RAMON.FUNIL.OPEN_CONVERSATION')"
        class="flex items-center justify-center size-6 rounded-md text-n-slate-10 hover:text-n-iris-11 hover:bg-n-alpha-2"
        @click.stop="emit('openConversation', lead.conversation_id)"
      >
        <span class="i-lucide-message-circle size-4" />
      </button>
      <TaskBellMenu @schedule="onSchedule" />
      <button
        data-testid="open-dossie"
        :title="$t('RAMON.KANBAN.CARD.DOSSIE')"
        class="flex items-center justify-center size-6 rounded-md text-n-slate-10 hover:text-n-iris-11 hover:bg-n-alpha-2"
        @click.stop="emit('openDossie', lead)"
      >
        <span class="i-lucide-file-text size-4" />
      </button>
    </div>
  </div>
</template>
