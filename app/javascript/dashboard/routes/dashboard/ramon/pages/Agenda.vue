<script setup>
import { computed, onMounted, ref } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useStore, useStoreGetters } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';

const { t } = useI18n();
const store = useStore();
const getters = useStoreGetters();
const router = useRouter();
const { accountScopedRoute } = useAccount();

// Segunda-feira 00:00 da semana da data dada.
const startOfWeek = date => {
  const d = new Date(date);
  d.setHours(0, 0, 0, 0);
  d.setDate(d.getDate() - ((d.getDay() + 6) % 7));
  return d;
};

const weekStart = ref(startOfWeek(new Date()));

// Reusa o endpoint de tarefas da conta (scope default = todas as abertas);
// o recorte da semana é feito client-side.
onMounted(() => store.dispatch('leadTasks/fetchAccountScope'));

const days = computed(() =>
  Array.from({ length: 7 }, (_, i) => {
    const d = new Date(weekStart.value);
    d.setDate(d.getDate() + i);
    return d;
  })
);

const dayKey = d => d.toDateString();
const isToday = d => dayKey(d) === dayKey(new Date());

const tasksByDay = computed(() => {
  const map = {};
  getters['leadTasks/getAccountTasks'].value.forEach(task => {
    if (!task.due_at || task.completed_at) return;
    const key = dayKey(new Date(task.due_at));
    if (!map[key]) map[key] = [];
    map[key].push(task);
  });
  return map;
});

const isFetching = computed(
  () => getters['leadTasks/getUIFlags'].value.isFetching
);

const dayLabel = d =>
  new Intl.DateTimeFormat(undefined, { weekday: 'short' }).format(d);
const dateLabel = d =>
  new Intl.DateTimeFormat(undefined, {
    day: '2-digit',
    month: '2-digit',
  }).format(d);
const timeLabel = iso =>
  new Intl.DateTimeFormat(undefined, {
    hour: '2-digit',
    minute: '2-digit',
  }).format(new Date(iso));

const rangeLabel = computed(
  () => `${dateLabel(days.value[0])} – ${dateLabel(days.value[6])}`
);

const shiftWeek = offset => {
  const d = new Date(weekStart.value);
  d.setDate(d.getDate() + offset * 7);
  weekStart.value = d;
};
const goToday = () => {
  weekStart.value = startOfWeek(new Date());
};

// Mesmo padrão do Centro de Comando: abre o Funil e seleciona o lead (drawer).
const openLead = leadId => {
  router.push(accountScopedRoute('ramon_funil'));
  store.dispatch('leads/select', leadId);
};
</script>

<template>
  <div class="flex flex-col w-full h-full overflow-auto bg-n-background p-8">
    <div class="flex items-center justify-between mb-6">
      <div>
        <h1 class="text-2xl font-cormorant text-n-slate-12">
          {{ t('RAMON.AGENDA.TITLE') }}
        </h1>
        <p class="text-sm text-n-slate-11">{{ rangeLabel }}</p>
      </div>
      <div class="flex items-center gap-2">
        <button
          class="flex items-center justify-center h-8 px-2 rounded-lg border border-n-weak text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
          :title="t('RAMON.AGENDA.PREV_WEEK')"
          @click="shiftWeek(-1)"
        >
          <span class="i-lucide-chevron-left size-4" />
        </button>
        <button
          class="h-8 px-3 text-sm rounded-lg border border-n-weak text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
          @click="goToday"
        >
          {{ t('RAMON.AGENDA.TODAY') }}
        </button>
        <button
          class="flex items-center justify-center h-8 px-2 rounded-lg border border-n-weak text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
          :title="t('RAMON.AGENDA.NEXT_WEEK')"
          @click="shiftWeek(1)"
        >
          <span class="i-lucide-chevron-right size-4" />
        </button>
      </div>
    </div>

    <div class="grid grid-cols-7 gap-2 flex-1 min-w-[840px]">
      <div
        v-for="day in days"
        :key="dayKey(day)"
        class="flex flex-col rounded-xl border border-n-weak bg-n-solid-1 min-h-[320px]"
        :class="{ 'border-n-iris-8': isToday(day) }"
      >
        <div
          class="px-3 py-2 border-b border-n-weak text-xs uppercase tracking-wide"
          :class="isToday(day) ? 'text-n-iris-11' : 'text-n-slate-10'"
        >
          {{ dayLabel(day) }}
          <span class="block text-sm normal-case text-n-slate-12">
            {{ dateLabel(day) }}
          </span>
        </div>
        <div class="flex flex-col gap-1.5 p-2">
          <button
            v-for="task in tasksByDay[dayKey(day)] || []"
            :key="task.id"
            class="flex flex-col items-start gap-0.5 p-2 text-left rounded-lg border border-n-weak bg-n-solid-2 hover:bg-n-alpha-2"
            @click="openLead(task.lead_id)"
          >
            <span
              class="flex items-center gap-1 text-xs"
              :class="
                task.kind === 'meeting' ? 'text-n-iris-11' : 'text-n-slate-10'
              "
            >
              <span
                :class="
                  task.kind === 'meeting'
                    ? 'i-lucide-calendar-clock'
                    : 'i-lucide-bell'
                "
                class="size-3.5 flex-shrink-0"
              />
              {{ timeLabel(task.due_at) }}
            </span>
            <span class="text-sm text-n-slate-12 line-clamp-2">
              {{ task.title }}
            </span>
            <span v-if="task.lead_name" class="text-xs text-n-slate-11">
              {{ task.lead_name }}
            </span>
          </button>
        </div>
      </div>
    </div>

    <p
      v-if="!isFetching && !days.some(day => tasksByDay[dayKey(day)])"
      class="mt-4 text-sm text-center text-n-slate-10"
    >
      {{ t('RAMON.AGENDA.EMPTY') }}
    </p>
  </div>
</template>
