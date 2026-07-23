<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import { waMeUrl } from '../../helpers/phone';
import { formatBrl } from '../../helpers/currency';
import { prescriptionInfo } from '../../helpers/prescription';
import { DEFAULT_STAGE_COLOR } from '../../helpers/stage';
import TaskBellMenu from './TaskBellMenu.vue';

const props = defineProps({
  lead: { type: Object, required: true },
  focused: { type: Boolean, default: false },
  // No board o card já está na coluna da etapa — o chip seria redundante.
  hideStage: { type: Boolean, default: false },
});
const emit = defineEmits(['openConversation', 'openLead']);

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

const formattedValue = computed(() => {
  const v = props.lead.value;
  if (v === null || v === undefined || v === '') return null;
  return new Intl.NumberFormat('pt-BR', {
    style: 'currency',
    currency: 'BRL',
  }).format(Number(v));
});

// Badge de prescrição: sangramento (parcelas já prescritas) tem prioridade
// sobre o alerta preventivo de proximidade do prazo (soon).
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
const prescriptionBadgeClass = computed(() =>
  prescription.value?.lostInstallments > 0
    ? 'bg-n-ruby-9 text-white'
    : 'bg-n-amber-9 text-white'
);

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

// Vermelho (apodrecendo forte) tem prioridade sobre âmbar (parado).
const borderClass = computed(() => {
  const limit = stage.value?.stalled_after_days;
  if (
    limit != null &&
    daysInStage.value != null &&
    daysInStage.value > 2 * limit
  ) {
    return 'border-n-ruby-9';
  }
  if (props.lead.stalled) return 'border-n-amber-9';
  return 'border-n-weak';
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

// "Sem próxima ação": nenhuma tarefa aberta e etapa ainda ativa (nem won/lost).
const showNoNextAction = computed(
  () =>
    props.lead.open_tasks_count === 0 &&
    !stage.value?.is_won &&
    !stage.value?.is_lost
);

// wa.me só quando há telefone e ainda não existe conversa vinculada.
const showWhatsApp = computed(
  () => !!props.lead.contact_phone && !props.lead.conversation_id
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

const copyPhone = async () => {
  await copyTextToClipboard(props.lead.contact_phone);
  useAlert(t('RAMON.KANBAN.CARD.PHONE_COPIED'));
};
</script>

<template>
  <div
    ref="cardEl"
    class="p-3 mb-2 rounded-xl bg-n-solid-2 border cursor-pointer"
    :class="[
      borderClass,
      {
        // hover só sobre a borda neutra — não apaga o sinal âmbar/ruby de risco
        'hover:border-n-iris-8': borderClass === 'border-n-weak',
        'ring-2 ring-n-iris-9': focused,
      },
    ]"
    @click="emit('openLead', lead)"
  >
    <!-- Linha 1: nome + valor (o que se escaneia) e ações rápidas -->
    <div class="flex items-center gap-1.5">
      <button
        data-testid="lead-card-body"
        class="flex-1 min-w-0 text-left"
        @click.stop="emit('openLead', lead)"
      >
        <p class="text-sm font-medium truncate text-n-slate-12">
          {{ lead.name }}
        </p>
      </button>
      <span
        v-if="showNoNextAction"
        data-testid="no-next-action"
        :title="$t('RAMON.KANBAN.CARD.NO_NEXT_ACTION')"
        class="i-lucide-alert-circle size-4 shrink-0 text-n-amber-11"
      />
      <TaskBellMenu @schedule="onSchedule" />
      <span
        v-if="formattedValue"
        class="text-sm font-semibold tabular-nums shrink-0 text-n-slate-12"
      >
        {{ formattedValue }}
      </span>
    </div>

    <!-- Linha 2: só o que grita (risco) mantém cor forte -->
    <div
      v-if="
        prescriptionLabel || lead.latest_triage?.status === 'awaiting_human'
      "
      class="flex flex-wrap items-center gap-1.5 mt-2"
    >
      <span
        v-if="prescriptionLabel"
        data-testid="prescription-badge"
        class="inline-block px-2 py-0.5 text-[11px] rounded-full"
        :class="prescriptionBadgeClass"
      >
        {{ prescriptionLabel }}
      </span>
      <span
        v-if="lead.latest_triage?.status === 'awaiting_human'"
        data-testid="triage-awaiting-human-badge"
        :title="$t('RAMON.TRIAGE.AWAITING_HUMAN_HINT')"
        class="inline-flex items-center gap-1 px-2 py-0.5 text-[11px] rounded-full bg-n-amber-3 text-n-amber-11"
      >
        <span class="i-lucide-user-round size-3" />{{
          $t('RAMON.KANBAN.CARD.TRIAGE_AWAITING_HUMAN')
        }}
      </span>
    </div>

    <!-- Linha 3: metadados discretos (cor só na semântica da etapa, via borda) -->
    <div
      v-if="
        (lead.stage_name && !hideStage) ||
        daysInStage !== null ||
        lead.benefit_type_name ||
        lead.lead_priority_name ||
        lead.follow_up_count > 0
      "
      class="flex flex-wrap items-center gap-1.5 mt-2"
    >
      <span
        v-if="lead.stage_name && !hideStage"
        data-testid="stage-chip"
        class="inline-block px-2 py-0.5 text-[11px] rounded-full border bg-n-alpha-2 text-n-slate-11"
        :style="{ borderColor: lead.stage_color || DEFAULT_STAGE_COLOR }"
      >
        {{ lead.stage_name }}
      </span>
      <span
        v-if="daysInStage !== null"
        data-testid="stage-age"
        class="inline-block px-2 py-0.5 text-[11px] rounded-full bg-n-alpha-2 text-n-slate-11"
      >
        {{ $t('RAMON.KANBAN.CARD.AGE', { days: daysInStage }) }}
      </span>
      <span
        v-if="lead.benefit_type_name"
        class="inline-block px-2 py-0.5 text-[11px] rounded-full bg-n-alpha-2 text-n-slate-11"
      >
        {{ lead.benefit_type_name }}
      </span>
      <span
        v-if="lead.lead_priority_name"
        class="inline-flex items-center gap-1 px-2 py-0.5 text-[11px] rounded-full bg-n-alpha-2 text-n-slate-11"
      >
        <span class="i-lucide-flag size-3" />{{ lead.lead_priority_name }}
      </span>
      <span
        v-if="lead.follow_up_count > 0"
        data-testid="follow-up-badge"
        :title="followUpTitle"
        class="inline-flex items-center gap-1 px-2 py-0.5 text-[11px] rounded-full bg-n-alpha-2 text-n-slate-11"
      >
        <span class="i-lucide-history size-3" />{{ lead.follow_up_count }}
      </span>
    </div>

    <div
      v-if="lead.contact_phone || ownerInitials"
      class="flex items-center gap-2 mt-2 text-xs text-n-slate-11"
    >
      <button
        v-if="lead.contact_phone"
        data-testid="copy-phone"
        :title="$t('RAMON.KANBAN.CARD.COPY_PHONE')"
        class="inline-flex items-center gap-1 hover:text-n-slate-12"
        @click.stop="copyPhone"
      >
        <span class="i-lucide-phone size-3.5" />{{ lead.contact_phone }}
      </button>
      <a
        v-if="showWhatsApp"
        data-testid="wa-me"
        :href="waMeUrl(lead.contact_phone)"
        target="_blank"
        rel="noopener noreferrer"
        class="inline-flex items-center gap-1 text-n-slate-11 hover:text-n-iris-11"
        @click.stop
      >
        <span class="i-lucide-message-circle size-3.5" />{{
          $t('RAMON.KANBAN.CARD.WHATSAPP')
        }}
      </a>
      <span
        v-if="ownerInitials"
        :title="ownerName"
        class="inline-flex items-center justify-center ml-auto size-6 text-[10px] rounded-full bg-n-alpha-2 text-n-slate-11"
      >
        {{ ownerInitials }}
      </span>
    </div>

    <button
      v-if="lead.conversation_id"
      data-testid="open-conversation"
      class="flex items-center justify-center gap-1.5 w-full mt-2 px-2 py-1.5 text-xs rounded-lg border border-n-weak text-n-slate-11 hover:text-n-iris-11 hover:border-n-iris-8"
      @click.stop="emit('openConversation', lead.conversation_id)"
    >
      <span class="i-lucide-message-square size-3.5" />{{
        $t('RAMON.FUNIL.OPEN_CONVERSATION')
      }}
    </button>
  </div>
</template>
