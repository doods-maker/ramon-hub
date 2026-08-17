<script setup>
import { computed, ref, onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import TaskBellMenu from '../kanban/TaskBellMenu.vue';

const props = defineProps({ leadId: { type: Number, required: true } });

defineOptions({ name: 'LeadNextAction' });
const store = useStore();
const { t } = useI18n();

const getByLead = useMapGetter('leadTasks/getByLead');
// 1ª tarefa aberta (o getter já ordena por due_at asc).
const task = computed(() => getByLead.value?.(props.leadId)?.[0] ?? null);
const isMeeting = computed(() => task.value?.kind === 'meeting');
// "quinta, 20/08 às 14:00" — reunião mostra quando é, não "em 3 dias".
const meetingWhen = computed(() => {
  if (!isMeeting.value || !task.value?.due_at) return '';
  const d = new Date(task.value.due_at);
  if (Number.isNaN(d.getTime())) return '';
  const dia = d.toLocaleDateString('pt-BR', {
    weekday: 'long',
    day: '2-digit',
    month: '2-digit',
  });
  const hora = d.toLocaleTimeString('pt-BR', {
    hour: '2-digit',
    minute: '2-digit',
  });
  return `${dia} às ${hora}`;
});

const load = id => {
  if (id) store?.dispatch('leadTasks/fetchForLead', id);
};
onMounted(() => load(props.leadId));
watch(
  () => props.leadId,
  id => load(id)
);

// mesmo cálculo relativo do LeadTasksList: dias inteiros entre meia-noites
const dueInfo = computed(() => {
  if (!task.value?.due_at) return { text: '', overdue: false };
  const startOf = ts => {
    const d = new Date(ts);
    d.setHours(0, 0, 0, 0);
    return d.getTime();
  };
  const days = Math.round(
    (startOf(task.value.due_at) - startOf(Date.now())) / 86400000
  );
  if (days < 0) return { text: t('RAMON.TASKS.OVERDUE'), overdue: true };
  if (days === 0) return { text: t('RAMON.TASKS.TODAY'), overdue: false };
  return { text: t('RAMON.TASKS.IN_DAYS', { n: days }), overdue: false };
});

// guard único para Feito/Adiar/Reagendar: um voo por vez
const busy = ref(false);
const run = async fn => {
  if (busy.value) return;
  busy.value = true;
  try {
    await fn();
  } catch (e) {
    useAlert(t('RAMON.LEAD_PANEL.NEXT_ACTION.ERROR'));
  } finally {
    busy.value = false;
  }
};

const complete = () =>
  run(() =>
    store.dispatch('leadTasks/complete', {
      leadId: props.leadId,
      taskId: task.value.id,
    })
  );

// Adiar 1d: soma 24h ao due_at atual (sem prazo, parte de agora).
const snooze = () =>
  run(() => {
    const base = task.value.due_at ? new Date(task.value.due_at) : new Date();
    return store.dispatch('leadTasks/update', {
      leadId: props.leadId,
      taskId: task.value.id,
      payload: { due_at: new Date(base.getTime() + 86400000).toISOString() },
    });
  });

// Reagendar via TaskBellMenu: só a data muda — o título da tarefa fica.
const reschedule = ({ dueAt }) =>
  run(() =>
    store.dispatch('leadTasks/update', {
      leadId: props.leadId,
      taskId: task.value.id,
      payload: { due_at: dueAt },
    })
  );
</script>

<template>
  <div
    v-if="task"
    data-testid="lead-next-action"
    class="rounded-xl p-3 bg-n-solid-1 border shadow-sm border-l-4"
    :class="
      dueInfo.overdue
        ? 'border-n-amber-9/40 border-l-n-amber-9'
        : isMeeting
          ? 'border-n-iris-9/40 border-l-n-iris-9 bg-n-iris-9/5'
          : 'border-n-weak border-l-n-iris-9'
    "
  >
    <p
      class="text-[10.5px] font-semibold uppercase tracking-widest"
      :class="
        dueInfo.overdue
          ? 'text-n-amber-11'
          : isMeeting
            ? 'text-n-iris-11'
            : 'text-n-slate-10'
      "
    >
      <template v-if="isMeeting">
        <span
          class="i-lucide-calendar-clock inline-block size-3 align-[-2px]"
        />
        {{ $t('RAMON.LEAD_PANEL.NEXT_ACTION.MEETING_TITLE') }}
      </template>
      <template v-else>{{ $t('RAMON.LEAD_PANEL.NEXT_ACTION.TITLE') }}</template>
      <template v-if="dueInfo.text">· {{ dueInfo.text }}</template>
    </p>
    <p
      v-if="isMeeting && meetingWhen"
      data-testid="next-action-meeting-when"
      class="mt-1 text-sm font-semibold text-n-slate-12 capitalize"
    >
      {{ meetingWhen }}
    </p>
    <p
      class="text-sm text-n-slate-12"
      :class="isMeeting ? 'text-xs text-n-slate-11' : 'mt-1'"
    >
      {{ task.title }}
    </p>
    <router-link
      v-if="isMeeting"
      :to="{ name: 'ramon_agenda' }"
      class="mt-1 inline-block text-xs text-n-iris-11 hover:underline"
      data-testid="next-action-agenda-link"
    >
      {{ $t('RAMON.LEAD_PANEL.NEXT_ACTION.SEE_AGENDA') }}
    </router-link>
    <div class="flex items-center gap-1.5 mt-2.5">
      <button
        data-testid="next-action-done"
        class="px-3 py-1 text-xs font-semibold rounded-lg bg-n-iris-9 text-white hover:bg-n-iris-10 disabled:opacity-50"
        :disabled="busy"
        @click="complete"
      >
        {{ $t('RAMON.LEAD_PANEL.NEXT_ACTION.DONE') }}
      </button>
      <button
        data-testid="next-action-snooze"
        class="px-3 py-1 text-xs rounded-lg bg-n-alpha-1 text-n-slate-11 hover:bg-n-alpha-2 disabled:opacity-50"
        :disabled="busy"
        @click="snooze"
      >
        {{ $t('RAMON.LEAD_PANEL.NEXT_ACTION.SNOOZE') }}
      </button>
      <span
        class="flex items-center gap-1 text-xs text-n-slate-11"
        data-testid="next-action-reschedule"
      >
        {{ $t('RAMON.LEAD_PANEL.NEXT_ACTION.RESCHEDULE') }}
        <TaskBellMenu @schedule="reschedule" />
      </span>
    </div>
  </div>
</template>
