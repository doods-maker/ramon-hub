<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import TaskBellMenu from './TaskBellMenu.vue';

const props = defineProps({
  lead: { type: Object, required: true },
});
const emit = defineEmits(['openConversation', 'openLead']);

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
    return 'border-red-500';
  }
  if (props.lead.stalled) return 'border-amber-500';
  return 'border-n-weak';
});

// "Sem próxima ação": nenhuma tarefa aberta e etapa ainda ativa (nem won/lost).
const showNoNextAction = computed(
  () =>
    props.lead.open_tasks_count === 0 &&
    !stage.value?.is_won &&
    !stage.value?.is_lost
);

// wa.me só quando há telefone e ainda não existe conversa vinculada.
const phoneDigits = computed(() =>
  (props.lead.contact_phone || '').replace(/\D/g, '')
);
const showWhatsApp = computed(
  () => !!props.lead.contact_phone && !props.lead.conversation_id
);

const onSchedule = async ({ dueAt, title }) => {
  await store.dispatch('leadTasks/create', {
    leadId: props.lead.id,
    title,
    kind: 'follow_up',
    dueAt,
  });
  useAlert(t('RAMON.KANBAN.CARD.TASK_SCHEDULED'));
};

const copyPhone = async () => {
  await copyTextToClipboard(props.lead.contact_phone);
  useAlert(t('RAMON.KANBAN.CARD.PHONE_COPIED'));
};
</script>

<template>
  <div
    class="p-3 mb-2 rounded-xl bg-n-solid-2 border cursor-pointer hover:border-n-iris-8"
    :class="borderClass"
  >
    <div class="flex items-start justify-between gap-2">
      <button
        data-testid="lead-card-body"
        class="flex-1 text-left"
        @click="emit('openLead', lead)"
      >
        <p class="text-sm font-medium text-n-slate-12">{{ lead.name }}</p>
      </button>
      <div class="flex items-center gap-1">
        <span
          v-if="showNoNextAction"
          data-testid="no-next-action"
          :title="$t('RAMON.KANBAN.CARD.NO_NEXT_ACTION')"
          class="i-lucide-alert-circle size-4 text-n-amber-11"
        />
        <TaskBellMenu @schedule="onSchedule" />
      </div>
    </div>

    <div class="flex flex-wrap items-center gap-1.5 mt-2">
      <span
        v-if="lead.stage_name"
        data-testid="stage-chip"
        class="inline-block px-2 py-0.5 text-[11px] rounded-full text-white"
        :style="{ backgroundColor: lead.stage_color || '#71717a' }"
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
    </div>

    <div class="flex items-center justify-between mt-2">
      <div class="flex items-center gap-2">
        <span
          v-if="lead.lead_priority_name"
          class="inline-flex items-center gap-1 px-2 py-0.5 text-[11px] rounded-full bg-n-iris-9 text-white"
        >
          <span class="i-lucide-flag size-3" />{{ lead.lead_priority_name }}
        </span>
        <span v-if="formattedValue" class="text-xs font-medium text-n-slate-12">
          {{ formattedValue }}
        </span>
      </div>
      <span
        v-if="ownerInitials"
        :title="ownerName"
        class="inline-flex items-center justify-center size-6 text-[10px] rounded-full bg-n-alpha-2 text-n-slate-11"
      >
        {{ ownerInitials }}
      </span>
    </div>

    <div
      v-if="lead.contact_phone"
      class="flex items-center gap-2 mt-2 text-xs text-n-slate-11"
    >
      <button
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
        :href="`https://wa.me/${phoneDigits}`"
        target="_blank"
        rel="noopener"
        class="inline-flex items-center gap-1 text-n-slate-11 hover:text-n-iris-11"
        @click.stop
      >
        <span class="i-lucide-message-circle size-3.5" />{{
          $t('RAMON.KANBAN.CARD.WHATSAPP')
        }}
      </a>
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
