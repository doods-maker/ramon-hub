<script setup>
import { ref, computed } from 'vue';
import { onKeyStroke } from '@vueuse/core';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import TaskBellMenu from '../kanban/TaskBellMenu.vue';

const props = defineProps({
  // Fila unificada já montada no CommandCenter (ver buildQueue lá).
  queue: { type: Array, default: () => [] },
});
const emit = defineEmits(['close']);

const { t } = useI18n();
const store = useStore();
const router = useRouter();
const { accountScopedRoute } = useAccount();

// Índice do item atual na esteira; `completedLeadId` marca o lead cuja tarefa
// já foi concluída nesta passada, revelando o agendamento da próxima.
const index = ref(0);
const completedLeadId = ref(null);

const total = computed(() => props.queue.length);
const isDone = computed(() => index.value >= total.value);
const current = computed(() => props.queue[index.value] || null);

// due formatado curto (dd/mm hh:mm) na locale do usuário; null quando sem prazo.
const dueLabel = computed(() => {
  const due = current.value?.dueAt;
  if (!due) return null;
  const d = new Date(due);
  if (Number.isNaN(d.getTime())) return null;
  return new Intl.DateTimeFormat('pt-BR', {
    day: '2-digit',
    month: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  }).format(d);
});

const phoneDigits = computed(() =>
  (current.value?.contactPhone || '').replace(/\D/g, '')
);
const showTaskDone = computed(
  () =>
    !!current.value?.taskId && completedLeadId.value !== current.value?.leadId
);
const showSchedule = computed(
  () =>
    !current.value?.taskId || completedLeadId.value === current.value?.leadId
);

// Fecha a esteira e reidrata o dashboard para refletir o que foi feito.
const finishAndClose = () => {
  store.dispatch('ramonDashboard/fetch');
  emit('close');
};

// Esc fecha o modal — mas se o menu do sino (teleportado pro body) estiver
// aberto, o listener próprio dele fecha só o menu e a esteira fica.
onKeyStroke('Escape', () => {
  if (document.querySelector('[data-testid="task-bell-menu"]')) return;
  finishAndClose();
});

// Avança para o próximo item, limpando o marcador de conclusão local.
const advance = () => {
  completedLeadId.value = null;
  index.value += 1;
};

const copyPhone = async () => {
  if (!current.value?.contactPhone) return;
  await copyTextToClipboard(current.value.contactPhone);
  useAlert(t('RAMON.KANBAN.CARD.PHONE_COPIED'));
};

// Guarda compartilhada: evita duplo-clique/duplo-agendamento durante o await.
const isActing = ref(false);

const completeTask = async () => {
  const item = current.value;
  if (!item?.taskId || isActing.value) return;
  isActing.value = true;
  try {
    await store.dispatch('leadTasks/complete', {
      leadId: item.leadId,
      taskId: item.taskId,
    });
    useAlert(t('RAMON.COMMAND.QUEUE.TASK_COMPLETED'));
    // Não avança: revela o agendamento da próxima tarefa para o mesmo lead.
    completedLeadId.value = item.leadId;
  } catch (e) {
    useAlert(t('RAMON.COMMAND.QUEUE.COMPLETE_ERROR'));
  } finally {
    isActing.value = false;
  }
};

// TaskBellMenu → cria a próxima tarefa e segue a esteira.
const onSchedule = async ({ dueAt, title }) => {
  const item = current.value;
  if (!item || isActing.value) return;
  isActing.value = true;
  try {
    await store.dispatch('leadTasks/create', {
      leadId: item.leadId,
      title,
      kind: 'follow_up',
      dueAt,
    });
    useAlert(t('RAMON.COMMAND.QUEUE.SCHEDULED'));
    advance();
  } catch (e) {
    useAlert(t('RAMON.TASKS.CREATE_ERROR'));
  } finally {
    isActing.value = false;
  }
};

// Abrir conversa: sai do Centro de Comando, então fecha a esteira antes de
// navegar para o Funil e acionar o dock da conversa (padrão do fork).
const openConversation = () => {
  const item = current.value;
  if (!item?.conversationId) return;
  emit('close');
  router.push(accountScopedRoute('ramon_funil'));
  store.dispatch('leads/toggleDock', item.conversationId);
};
</script>

<template>
  <div
    data-testid="follow-up-queue"
    class="fixed inset-0 z-50 flex items-center justify-center bg-black/50"
    @click.self="finishAndClose"
  >
    <div
      class="w-[26rem] max-w-[92vw] p-5 rounded-xl bg-n-solid-2 border border-n-weak"
    >
      <!-- Cabeçalho: progresso + encerrar -->
      <div class="flex items-center justify-between mb-4">
        <span
          data-testid="queue-progress"
          class="text-xs tracking-widest uppercase text-n-slate-10"
        >
          <template v-if="!isDone">
            {{
              t('RAMON.COMMAND.QUEUE.PROGRESS', {
                current: index + 1,
                total,
              })
            }}
          </template>
          <template v-else>{{ t('RAMON.COMMAND.QUEUE.TITLE') }}</template>
        </span>
        <button
          type="button"
          data-testid="queue-close"
          :title="t('RAMON.COMMAND.QUEUE.CLOSE')"
          class="flex items-center justify-center rounded-full size-6 text-n-slate-10 hover:text-n-slate-12 hover:bg-n-alpha-2"
          @click="finishAndClose"
        >
          <span class="i-lucide-x size-4" />
        </button>
      </div>

      <!-- Barra de progresso -->
      <div v-if="total" class="w-full h-1 mb-5 rounded-full bg-n-alpha-2">
        <div
          class="h-1 rounded-full bg-n-iris-9 transition-all"
          :style="{ width: `${(Math.min(index, total) / total) * 100}%` }"
        />
      </div>

      <!-- Item atual -->
      <div v-if="!isDone && current" data-testid="queue-item">
        <p class="font-cormorant text-3xl font-semibold text-n-slate-12">
          {{ current.leadName }}
        </p>
        <div class="flex flex-wrap items-center gap-1.5 mt-2">
          <span
            v-if="current.stageName"
            class="inline-block px-2 py-0.5 text-[11px] rounded-full bg-n-alpha-2 text-n-slate-11"
          >
            {{ current.stageName }}
          </span>
          <span
            v-if="current.daysInStage != null"
            class="inline-block px-2 py-0.5 text-[11px] rounded-full bg-n-alpha-2 text-n-slate-11"
          >
            {{ t('RAMON.KANBAN.CARD.AGE', { days: current.daysInStage }) }}
          </span>
        </div>

        <!-- Tarefa vencida (quando o item veio de tasks_overdue) -->
        <div
          v-if="current.taskId"
          data-testid="queue-task"
          class="flex items-start gap-2 p-3 mt-4 rounded-lg bg-n-alpha-2"
        >
          <span class="mt-0.5 i-lucide-alarm-clock size-4 text-n-ruby-11" />
          <div class="min-w-0">
            <p class="text-sm text-n-slate-12">{{ current.taskTitle }}</p>
            <p v-if="dueLabel" class="text-xs text-n-slate-10">
              {{ t('RAMON.COMMAND.QUEUE.DUE', { at: dueLabel }) }}
            </p>
          </div>
        </div>

        <!-- Telefone: copiar + wa.me -->
        <div
          v-if="current.contactPhone"
          class="flex items-center gap-3 mt-4 text-xs text-n-slate-11"
        >
          <button
            type="button"
            data-testid="queue-copy-phone"
            :title="t('RAMON.KANBAN.CARD.COPY_PHONE')"
            class="inline-flex items-center gap-1 hover:text-n-slate-12"
            @click="copyPhone"
          >
            <span class="i-lucide-phone size-3.5" />{{ current.contactPhone }}
          </button>
          <a
            data-testid="queue-wa-me"
            :href="`https://wa.me/${phoneDigits}`"
            target="_blank"
            rel="noopener noreferrer"
            class="inline-flex items-center gap-1 text-n-slate-11 hover:text-n-iris-11"
          >
            <span class="i-lucide-message-circle size-3.5" />{{
              t('RAMON.KANBAN.CARD.WHATSAPP')
            }}
          </a>
        </div>

        <!-- Ações -->
        <div
          class="flex flex-wrap items-center gap-2 pt-4 mt-4 border-t border-n-weak"
        >
          <button
            v-if="showTaskDone"
            type="button"
            data-testid="queue-complete"
            class="inline-flex items-center h-8 gap-1.5 px-3 text-sm rounded-lg bg-n-teal-9 text-white hover:bg-n-teal-10 disabled:opacity-50"
            :disabled="isActing"
            @click="completeTask"
          >
            <span class="i-lucide-check size-4" />{{
              t('RAMON.COMMAND.QUEUE.COMPLETE')
            }}
          </button>

          <div v-if="showSchedule" class="inline-flex items-center gap-1.5">
            <span class="text-xs text-n-slate-10">
              {{ t('RAMON.COMMAND.QUEUE.SCHEDULE') }}
            </span>
            <TaskBellMenu @schedule="onSchedule" />
          </div>

          <button
            v-if="current.conversationId"
            type="button"
            data-testid="queue-open-conversation"
            class="inline-flex items-center h-8 gap-1.5 px-3 text-sm rounded-lg border border-n-weak text-n-slate-11 hover:text-n-iris-11 hover:border-n-iris-8"
            @click="openConversation"
          >
            <span class="i-lucide-message-square size-4" />{{
              t('RAMON.COMMAND.QUEUE.OPEN_CONVERSATION')
            }}
          </button>

          <button
            type="button"
            data-testid="queue-skip"
            class="inline-flex items-center h-8 gap-1.5 px-3 ml-auto text-sm rounded-lg text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
            @click="advance"
          >
            {{ t('RAMON.COMMAND.QUEUE.SKIP') }}
            <span class="i-lucide-chevron-right size-4" />
          </button>
        </div>
      </div>

      <!-- Conclusão -->
      <div v-else data-testid="queue-done" class="py-4 text-center">
        <span
          class="inline-flex items-center justify-center mb-3 rounded-full size-12 bg-n-teal-3 text-n-teal-11"
        >
          <span class="i-lucide-check-check size-6" />
        </span>
        <p class="text-lg font-medium text-n-slate-12">
          {{ t('RAMON.COMMAND.QUEUE.DONE_TITLE') }}
        </p>
        <p class="mt-1 text-sm text-n-slate-10">
          {{ t('RAMON.COMMAND.QUEUE.DONE_BODY') }}
        </p>
        <button
          type="button"
          data-testid="queue-done-close"
          class="inline-flex items-center h-9 gap-2 px-4 mt-5 text-sm rounded-lg bg-n-iris-9 text-white hover:bg-n-iris-10"
          @click="finishAndClose"
        >
          {{ t('RAMON.COMMAND.QUEUE.CLOSE') }}
        </button>
      </div>
    </div>
  </div>
</template>
