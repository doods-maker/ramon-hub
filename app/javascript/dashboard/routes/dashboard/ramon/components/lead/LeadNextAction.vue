<script setup>
import { computed, ref, onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import TaskBellMenu from '../kanban/TaskBellMenu.vue';
import { CARTAO_STATUS, FILETE, SOBRESCRITO } from '../../helpers/ui';

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
    :class="[CARTAO_STATUS, dueInfo.overdue ? FILETE.amber : FILETE.blue]"
  >
    <p
      :class="[
        SOBRESCRITO,
        dueInfo.overdue
          ? 'text-n-amber-11'
          : isMeeting
            ? 'text-n-blue-11'
            : 'text-n-slate-10',
      ]"
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
      class="mt-1 font-mono text-sm font-semibold text-n-slate-12 capitalize"
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
      v-slot="{ navigate }"
      custom
      :to="{ name: 'ramon_agenda' }"
    >
      <Button
        data-testid="next-action-agenda-link"
        link
        xs
        class="mt-1"
        :label="$t('RAMON.LEAD_PANEL.NEXT_ACTION.SEE_AGENDA')"
        @click="navigate"
      />
    </router-link>
    <div class="flex items-center gap-1.5 mt-2.5">
      <Button
        data-testid="next-action-done"
        sm
        :label="$t('RAMON.LEAD_PANEL.NEXT_ACTION.DONE')"
        :disabled="busy"
        @click="complete"
      />
      <Button
        data-testid="next-action-snooze"
        sm
        faded
        slate
        :label="$t('RAMON.LEAD_PANEL.NEXT_ACTION.SNOOZE')"
        :disabled="busy"
        @click="snooze"
      />
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
