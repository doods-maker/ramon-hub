<script setup>
import { computed, ref, onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import TaskBellMenu from '../kanban/TaskBellMenu.vue';

const props = defineProps({ leadId: { type: Number, required: true } });

const store = useStore();
const { t } = useI18n();
const getByLead = useMapGetter('leadTasks/getByLead');
// getByLead é um getter que devolve função; em cenários de teste isolados o
// módulo leadTasks pode não estar registrado — cai para lista vazia.
const tasks = computed(() => getByLead.value?.(props.leadId) ?? []);

// Carrega as tarefas do lead; guard de leadId para não bater sem id.
const load = id => {
  if (id) store?.dispatch('leadTasks/fetchForLead', id);
};
onMounted(() => load(props.leadId));
watch(
  () => props.leadId,
  id => load(id)
);

// due_at relativo: rótulo curto + flag de vencida (fica vermelho).
const relativeDue = dueAt => {
  if (!dueAt) return { text: '', overdue: false };
  const startOf = ts => {
    const d = new Date(ts);
    d.setHours(0, 0, 0, 0);
    return d.getTime();
  };
  const days = Math.round((startOf(dueAt) - startOf(Date.now())) / 86400000);
  if (days < 0) return { text: t('RAMON.TASKS.OVERDUE'), overdue: true };
  if (days === 0) return { text: t('RAMON.TASKS.TODAY'), overdue: false };
  return { text: t('RAMON.TASKS.IN_DAYS', { n: days }), overdue: false };
};

// Após concluir, oferece agendar a próxima (sugestão, nunca obrigatório).
// A task concluída sai do getter (completed_at preenchido) e a linha do v-for
// desmonta no mesmo tick — por isso o prompt vive FORA do v-for, ancorado
// numa cópia da task recém-concluída.
const justCompleted = ref(null);

const complete = async task => {
  await store.dispatch('leadTasks/complete', {
    leadId: props.leadId,
    taskId: task.id,
  });
  justCompleted.value = task;
};

const onScheduleNext = async ({ dueAt, title }) => {
  await store.dispatch('leadTasks/create', {
    leadId: props.leadId,
    title,
    kind: 'follow_up',
    dueAt,
  });
  justCompleted.value = null;
};

// Nova tarefa manual (título opcional → default i18n, como no TaskBellMenu).
const adding = ref(false);
const newTitle = ref('');
const newDate = ref('');

const addTask = async () => {
  const title = newTitle.value.trim() || t('RAMON.KANBAN.BELL.DEFAULT_TITLE');
  await store.dispatch('leadTasks/create', {
    leadId: props.leadId,
    title,
    kind: 'follow_up',
    dueAt: newDate.value ? new Date(newDate.value).toISOString() : null,
  });
  newTitle.value = '';
  newDate.value = '';
  adding.value = false;
};
</script>

<template>
  <div class="flex flex-col gap-2 mb-4">
    <span class="text-xs uppercase text-n-slate-10">{{
      $t('RAMON.TASKS.TITLE')
    }}</span>

    <p
      v-if="!tasks.length"
      data-testid="tasks-empty"
      class="text-xs text-n-slate-9"
    >
      {{ $t('RAMON.TASKS.EMPTY') }}
    </p>

    <div
      v-for="task in tasks"
      :key="task.id"
      data-testid="task-item"
      class="flex flex-col gap-1"
    >
      <div class="flex items-center gap-2">
        <input
          type="checkbox"
          data-testid="task-complete"
          class="shrink-0"
          @change="complete(task)"
        />
        <span class="flex-1 text-sm text-n-slate-12">{{ task.title }}</span>
        <span
          v-if="task.due_at"
          data-testid="task-due"
          class="text-[11px]"
          :class="
            relativeDue(task.due_at).overdue
              ? 'text-n-ruby-11'
              : 'text-n-slate-10'
          "
        >
          {{ relativeDue(task.due_at).text }}
        </span>
      </div>
    </div>

    <div
      v-if="justCompleted"
      data-testid="task-schedule-next"
      class="flex items-center gap-2 text-[11px] text-n-slate-10"
    >
      <span>{{ $t('RAMON.TASKS.SCHEDULE_NEXT') }}</span>
      <TaskBellMenu @schedule="onScheduleNext" />
      <button
        data-testid="task-schedule-dismiss"
        class="text-n-slate-9 hover:text-n-slate-11"
        @click="justCompleted = null"
      >
        <span class="i-lucide-x size-3.5" />
      </button>
    </div>

    <div v-if="adding" class="flex flex-col gap-2">
      <input
        v-model="newTitle"
        data-testid="task-new-title"
        :placeholder="$t('RAMON.TASKS.ADD_TITLE_PLACEHOLDER')"
        class="w-full px-2 py-1.5 text-sm rounded bg-n-alpha-1 text-n-slate-12 border border-n-weak"
      />
      <input
        v-model="newDate"
        data-testid="task-new-date"
        type="datetime-local"
        class="w-full px-2 py-1.5 text-sm rounded bg-n-alpha-1 text-n-slate-12 border border-n-weak"
      />
      <div class="flex gap-2">
        <button
          data-testid="task-new-cancel"
          class="px-3 py-1 text-xs text-n-slate-11"
          @click="adding = false"
        >
          {{ $t('RAMON.FUNIL.CANCEL') }}
        </button>
        <button
          data-testid="task-new-save"
          class="px-3 py-1 text-xs rounded-lg bg-n-iris-9 text-white"
          @click="addTask"
        >
          {{ $t('RAMON.FUNIL.SAVE') }}
        </button>
      </div>
    </div>
    <button
      v-else
      data-testid="task-add-toggle"
      class="self-start px-3 py-1.5 text-xs rounded-lg bg-n-alpha-1 text-n-slate-12 border border-n-weak"
      @click="adding = true"
    >
      {{ $t('RAMON.TASKS.ADD') }}
    </button>
  </div>
</template>
