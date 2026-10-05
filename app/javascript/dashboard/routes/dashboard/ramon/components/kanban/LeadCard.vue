<script setup>
import { computed, onMounted, onUnmounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { formatBrl, brlCompact } from '../../helpers/currency';
import { prescriptionInfo } from '../../helpers/prescription';
import { contratoLimpoStatus } from '../../helpers/contratoLimpo';
import { slaApplies } from '../../helpers/stage';
import { nextActionInfo } from '../../helpers/nextAction';
import Button from 'dashboard/components-next/button/Button.vue';
import { CARTAO, CHIP, TOM, FILETE, BOTAO_COMPACTO } from '../../helpers/ui';
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

// Valor compacto azul ("R$ 38 mil") — traço quando não há valor.
const compactValue = computed(() => {
  const v = props.lead.value;
  if (v === null || v === undefined || v === '') return null;
  return brlCompact(v);
});

// Prescrição: sangramento (parcelas já prescritas) vira texto ruby na linha 2.
const prescription = computed(() => prescriptionInfo(props.lead));
// Selo do contrato limpo (só lead assinado): verde = carimbado.
const contrato = computed(() => contratoLimpoStatus(props.lead));
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
    return t(
      'RAMON.KANBAN.CARD.PRESCRIPTION_SOON',
      { months: p.monthsToCliff },
      p.monthsToCliff
    );
  return null;
});

// SDR e Closer explícitos: uma sigla por papel preenchido, nome no title.
const initials = name =>
  name
    .trim()
    .split(/\s+/)
    .map(word => word[0])
    .slice(0, 2)
    .join('')
    .toUpperCase();
const owners = computed(() =>
  [
    {
      role: 'sdr',
      name: props.lead.sdr_name,
      tone: TOM.slate,
      title: name => t('RAMON.KANBAN.CARD.OWNER_SDR', { name }),
    },
    {
      role: 'closer',
      name: props.lead.closer_name,
      tone: TOM.blue,
      title: name => t('RAMON.KANBAN.CARD.OWNER_CLOSER', { name }),
    },
  ]
    .filter(owner => owner.name)
    .map(owner => ({
      ...owner,
      initials: initials(owner.name),
      title: owner.title(owner.name),
    }))
);

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

// Estado do SLA a partir de lead.sla { due_at, replied_at, minutes }. Fora da
// etapa de entrada o SLA é história antiga (lead já foi trabalhado): some.
const slaState = computed(() => {
  const sla = props.lead.sla;
  if (!sla?.due_at) return null;
  const stages = store?.getters?.['leadConfig/getStages'];
  if (!slaApplies(props.lead.lead_stage_id, stages)) return null;
  const due = new Date(sla.due_at).getTime();
  if (Number.isNaN(due)) return null;
  if (sla.replied_at) {
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

// Pill: âmbar regressivo dentro do SLA, ruby estourado, teal respondido (com ✓).
const slaPill = computed(() => {
  const state = slaState.value;
  if (!state) return null;
  if (state.kind === 'replied')
    return {
      class: TOM.teal,
      icon: 'i-lucide-check',
      label: state.time,
      title: null,
    };
  if (state.kind === 'within')
    return {
      class: TOM.amber,
      label: state.time,
      title: t('RAMON.KANBAN.SLA.REMAINING', { time: state.time }),
    };
  return {
    class: TOM.ruby,
    label: state.time,
    title: t('RAMON.KANBAN.SLA.OVERDUE_SINCE', { time: state.time }),
  };
});

// Risco = filete à ESQUERDA (CARTAO_STATUS): ruby (prescrevendo / apodrecendo forte / SLA
// estourado) tem prioridade sobre âmbar (parado). O hover azul re-afirma a
// cor da esquerda para nunca apagar o sinal de risco.
const riskClass = computed(() => {
  const limit = stage.value?.stalled_after_days;
  const rotten =
    limit != null && daysInStage.value != null && daysInStage.value > 2 * limit;
  if (prescription.value?.lostInstallments > 0 || rotten || slaOverdue.value)
    return `border-l-4 ${FILETE.ruby} hover:border-l-n-ruby-9`;
  if (props.lead.stalled)
    return `border-l-4 ${FILETE.amber} hover:border-l-n-amber-9`;
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

// Próxima ação: mesma formatação da Lista (helpers/nextAction).
const nextAction = computed(() => nextActionInfo(props.lead, t));

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
    class="group mb-1.5 cursor-pointer transition duration-150 hover:border-n-blue-8 active:scale-[0.97]"
    :class="[CARTAO, riskClass, { 'ring-2 ring-n-blue-9': focused }]"
    @click="emit('openLead', lead)"
  >
    <!-- Linha 1: checkbox de lote + nome + valor compacto -->
    <div class="flex items-center gap-2">
      <button
        v-if="selectable"
        data-testid="select-toggle"
        class="flex items-center justify-center size-3.5 p-0 rounded shrink-0 border-[1.5px] border-solid transition duration-150"
        :class="selected ? 'bg-n-brand border-n-brand' : 'border-n-slate-8'"
        @click.stop="emit('toggleSelect', lead)"
      >
        <span v-if="selected" class="i-lucide-check size-2.5 text-white" />
      </button>
      <button
        data-testid="lead-card-body"
        class="flex-1 min-w-0 p-0 text-left"
        @click.stop="emit('openLead', lead)"
      >
        <p class="mb-0 text-sm font-medium truncate text-n-slate-12">
          {{ lead.name }}
        </p>
      </button>
      <!-- Timer do SLA de 1º contato (mock 3a), à direita do nome -->
      <span
        v-if="slaPill"
        data-testid="sla-pill"
        :title="slaPill.title || undefined"
        class="shrink-0 font-mono font-semibold"
        :class="[CHIP, slaPill.class]"
      >
        <span v-if="slaPill.icon" class="size-3" :class="slaPill.icon" />
        {{ slaPill.label }}
      </span>
      <span
        data-testid="lead-value"
        class="text-xs font-mono shrink-0"
        :class="compactValue ? 'font-medium text-n-blue-11' : 'text-n-slate-10'"
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
        class="inline-flex items-center gap-1"
        :class="
          prescription?.lostInstallments > 0
            ? 'text-n-ruby-11'
            : 'text-n-amber-11'
        "
      >
        <span class="i-lucide-hourglass size-3 shrink-0" />
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
        class="font-mono text-n-slate-10"
      >
        {{ $t('RAMON.KANBAN.CARD.AGE', { days: daysInStage }) }}
      </span>
      <span
        v-if="lead.follow_up_count > 0"
        data-testid="follow-up-badge"
        :title="followUpTitle"
        class="inline-flex items-center gap-0.5 font-mono text-n-slate-10"
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
        class="font-mono !px-1.5"
        :class="[
          CHIP,
          lead.docs_received >= lead.docs_total ? TOM.teal : TOM.amber,
        ]"
      >
        <span class="i-lucide-file-check size-3" />{{ lead.docs_received }}/{{
          lead.docs_total
        }}
      </span>
      <span
        v-if="contrato"
        data-testid="contrato-limpo-badge"
        :title="$t(`RAMON.CONTRATO.${contrato.key}`, { count: contrato.count })"
        class="inline-flex items-center"
        :class="contrato.key === 'LIMPO' ? 'text-n-teal-11' : 'text-n-amber-11'"
      >
        <span class="i-lucide-badge-check size-3" />
      </span>
      <span v-if="lead.benefit_type_name" class="text-n-slate-10">
        {{ lead.benefit_type_name }}
      </span>
      <span v-if="owners.length" class="inline-flex gap-1 ms-auto">
        <span
          v-for="owner in owners"
          :key="owner.role"
          :data-testid="`owner-${owner.role}`"
          :title="owner.title"
          class="!px-1.5 font-mono"
          :class="[CHIP, owner.tone]"
        >
          {{ owner.initials }}
        </span>
      </span>
    </div>

    <!-- Ações rápidas: sempre visíveis (pedido do Eduardo 17/08) -->
    <div
      class="flex flex-wrap items-center gap-1 mt-2"
      :class="selectable ? 'pl-[22px]' : 'pl-0'"
    >
      <!-- SLA estourado: CTA explícito de resposta (reusa a ação de conversa) -->
      <Button
        v-if="slaOverdue && lead.conversation_id"
        data-testid="sla-respond-now"
        :class="BOTAO_COMPACTO"
        xs
        :label="$t('RAMON.KANBAN.SLA.RESPOND_NOW')"
        @click.stop="emit('openConversation', lead.conversation_id)"
      />
      <!-- com SLA estourado o "Responder agora" já abre a conversa -->
      <Button
        v-if="lead.conversation_id && !slaOverdue"
        data-testid="open-conversation"
        :class="BOTAO_COMPACTO"
        :title="$t('RAMON.FUNIL.OPEN_CONVERSATION')"
        xs
        faded
        slate
        icon="i-lucide-message-circle"
        :label="$t('RAMON.KANBAN.CARD.CONVERSATION')"
        @click.stop="emit('openConversation', lead.conversation_id)"
      />
      <TaskBellMenu
        :label="$t('RAMON.KANBAN.BELL.DEFAULT_TITLE')"
        @schedule="onSchedule"
      />
      <Button
        data-testid="open-dossie"
        :class="BOTAO_COMPACTO"
        :title="$t('RAMON.KANBAN.CARD.DOSSIE')"
        xs
        faded
        slate
        icon="i-lucide-file-text"
        :label="$t('RAMON.KANBAN.CARD.DOSSIE')"
        @click.stop="emit('openDossie', lead)"
      />
    </div>
  </div>
</template>
