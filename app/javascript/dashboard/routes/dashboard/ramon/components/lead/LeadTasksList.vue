<script setup>
import { computed, ref, onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import TaskBellMenu from '../kanban/TaskBellMenu.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import { ACAO, SECAO, TITULO, CAMPO } from '../../helpers/ui';

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

// checkbox controlado + guard durante o voo: falha deixava marcado sem concluir
const completingId = ref(null);
const complete = async (task, event) => {
  if (completingId.value) {
    // outra conclusão em voo: desfaz o toggle nativo que o clique já pintou
    // (o vnode não repatcha porque o :checked bound não mudou)
    if (event?.target) event.target.checked = Boolean(task.completed_at);
    return;
  }
  completingId.value = task.id;
  try {
    await store.dispatch('leadTasks/complete', {
      leadId: props.leadId,
      taskId: task.id,
    });
    justCompleted.value = task;
  } catch (e) {
    useAlert(t('RAMON.FUNIL.SAVE_ERROR'));
  } finally {
    completingId.value = null;
  }
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

// Sem data → amanhã 9h local (mesmo preset do TaskBellMenu); backend exige due_at.
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
  const title = newTitle.value.trim() || t('RAMON.KANBAN.BELL.DEFAULT_TITLE');
  const due = newDate.value ? new Date(newDate.value) : tomorrowAt9();
  try {
    await store.dispatch('leadTasks/create', {
      leadId: props.leadId,
      title,
      kind: 'follow_up',
      dueAt: due.toISOString(),
    });
    newTitle.value = '';
    newDate.value = '';
    adding.value = false;
  } catch (e) {
    useAlert(t('RAMON.TASKS.CREATE_ERROR'));
  } finally {
    savingTask.value = false;
  }
};
</script>

<template>
  <div class="flex flex-col gap-2 mb-4" :class="SECAO">
    <span :class="TITULO">{{ $t('RAMON.TASKS.TITLE') }}</span>

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
        <Checkbox
          data-testid="task-complete"
          class="shrink-0"
          :title="$t('RAMON.TASKS.COMPLETE')"
          :model-value="Boolean(task.completed_at) || completingId === task.id"
          :disabled="completingId === task.id"
          @change="complete(task, $event)"
        />
        <span class="flex-1 text-sm text-n-slate-12">{{ task.title }}</span>
        <span
          v-if="task.due_at"
          data-testid="task-due"
          class="font-mono text-[11px]"
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
      <Button
        data-testid="task-schedule-dismiss"
        xs
        ghost
        slate
        icon="i-lucide-x"
        @click="justCompleted = null"
      />
    </div>

    <div v-if="adding" class="flex flex-col gap-2">
      <input
        v-model="newTitle"
        data-testid="task-new-title"
        :placeholder="$t('RAMON.TASKS.ADD_TITLE_PLACEHOLDER')"
        :class="CAMPO"
      />
      <input
        v-model="newDate"
        data-testid="task-new-date"
        type="datetime-local"
        :title="$t('RAMON.TASKS.DATE_HINT')"
        class="font-mono"
        :class="CAMPO"
      />
      <div class="flex justify-end gap-2">
        <Button
          data-testid="task-new-cancel"
          sm
          faded
          slate
          :label="$t('RAMON.FUNIL.CANCEL')"
          @click="adding = false"
        />
        <Button
          :class="ACAO"
          data-testid="task-new-save"
          sm
          :label="$t('RAMON.FUNIL.SAVE')"
          :disabled="savingTask"
          @click="addTask"
        />
      </div>
    </div>
    <Button
      v-else
      data-testid="task-add-toggle"
      sm
      faded
      slate
      class="self-start"
      :label="$t('RAMON.TASKS.ADD')"
      @click="adding = true"
    />
  </div>
</template>
