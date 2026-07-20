<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useStore, useStoreGetters } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import RamonPageHeader from '../components/RamonPageHeader.vue';

const { t } = useI18n();
const store = useStore();
const getters = useStoreGetters();
const router = useRouter();
const { accountScopedRoute } = useAccount();

// ---- estado da visão: dia | semana | mês, ancorado numa data de referência
const VIEWS = ['day', 'week', 'month'];
const KIND_FILTERS = ['all', 'meeting', 'follow_up'];

// view e filtro persistem em localStorage; a âncora de data é volátil.
const VIEW_KEY = 'ramon_agenda_view';
const KIND_KEY = 'ramon_agenda_kind';
const loadPref = (key, valid, fallback) => {
  try {
    const value = localStorage.getItem(key);
    return valid.includes(value) ? value : fallback;
  } catch (e) {
    return fallback;
  }
};

const view = ref(loadPref(VIEW_KEY, VIEWS, 'week'));
const anchor = ref(new Date());
// Filtro por tipo: all | meeting | follow_up (follow_up = tudo que não é reunião)
const kindFilter = ref(loadPref(KIND_KEY, KIND_FILTERS, 'all'));

watch([view, kindFilter], () => {
  try {
    localStorage.setItem(VIEW_KEY, view.value);
    localStorage.setItem(KIND_KEY, kindFilter.value);
  } catch (e) {
    // localStorage indisponível: seguimos sem persistir
  }
});

// Segunda-feira 00:00 da semana da data dada.
const startOfWeek = date => {
  const d = new Date(date);
  d.setHours(0, 0, 0, 0);
  d.setDate(d.getDate() - ((d.getDay() + 6) % 7));
  return d;
};
const startOfMonth = date => new Date(date.getFullYear(), date.getMonth(), 1);

// Reusa o endpoint de tarefas da conta (scope default = todas as abertas);
// recorte de período e filtro de tipo são client-side.
const reload = () => store.dispatch('leadTasks/fetchAccountScope');
onMounted(reload);

const dayKey = d => d.toDateString();
const isToday = d => dayKey(d) === dayKey(new Date());
const isWeekend = d => d.getDay() === 0 || d.getDay() === 6;
const inAnchorMonth = d => d.getMonth() === anchor.value.getMonth();

const matchesKind = task => {
  if (kindFilter.value === 'all') return true;
  if (kindFilter.value === 'meeting') return task.kind === 'meeting';
  return task.kind !== 'meeting';
};

const tasksByDay = computed(() => {
  const map = {};
  getters['leadTasks/getAccountTasks'].value.forEach(task => {
    if (!task.due_at || task.completed_at || !matchesKind(task)) return;
    const key = dayKey(new Date(task.due_at));
    if (!map[key]) map[key] = [];
    map[key].push(task);
  });
  return map;
});

// ---- dias visíveis por visão
const addDays = (date, n) => {
  const d = new Date(date);
  d.setDate(d.getDate() + n);
  return d;
};

const days = computed(() => {
  if (view.value === 'day') return [new Date(anchor.value)];
  if (view.value === 'week') {
    const start = startOfWeek(anchor.value);
    return Array.from({ length: 7 }, (_, i) => addDays(start, i));
  }
  // mês: da segunda antes do dia 1 até completar semanas inteiras
  const first = startOfMonth(anchor.value);
  const start = startOfWeek(first);
  const last = new Date(first.getFullYear(), first.getMonth() + 1, 0);
  // round, não ceil: a transição de horário de verão desloca o span em ±1h e
  // ceil inflaria um mês exato de 5 semanas para 6.
  const weeks = Math.round(((last - start) / 86400000 + 1) / 7);
  return Array.from({ length: weeks * 7 }, (_, i) => addDays(start, i));
});

const isFetching = computed(
  () => getters['leadTasks/getUIFlags'].value.isFetching
);
const hasError = computed(() => getters['leadTasks/getUIFlags'].value.hasError);

const dayLabel = d =>
  new Intl.DateTimeFormat('pt-BR', { weekday: 'short' }).format(d);
const dateLabel = d =>
  new Intl.DateTimeFormat('pt-BR', { day: '2-digit', month: '2-digit' }).format(
    d
  );
const timeLabel = iso =>
  new Intl.DateTimeFormat('pt-BR', {
    hour: '2-digit',
    minute: '2-digit',
  }).format(new Date(iso));
const monthLabel = d =>
  new Intl.DateTimeFormat('pt-BR', { month: 'long', year: 'numeric' }).format(
    d
  );
const fullDayLabel = d =>
  new Intl.DateTimeFormat('pt-BR', {
    weekday: 'long',
    day: '2-digit',
    month: 'long',
  }).format(d);

// Cabeçalho dos dias da semana no mês (seg…dom, derivado de uma semana real).
const weekdayHeaders = computed(() => {
  const start = startOfWeek(new Date());
  return Array.from({ length: 7 }, (_, i) => dayLabel(addDays(start, i)));
});

const rangeLabel = computed(() => {
  if (view.value === 'day') return fullDayLabel(anchor.value);
  if (view.value === 'week') {
    const start = startOfWeek(anchor.value);
    return `${dateLabel(start)} – ${dateLabel(addDays(start, 6))}`;
  }
  return monthLabel(anchor.value);
});

// ---- navegação
const shift = offset => {
  const d = new Date(anchor.value);
  if (view.value === 'day') d.setDate(d.getDate() + offset);
  else if (view.value === 'week') d.setDate(d.getDate() + offset * 7);
  else d.setMonth(d.getMonth() + offset, 1);
  anchor.value = d;
};
const goToday = () => {
  anchor.value = new Date();
};

// <input type="month"> nativo: escolher o mês de qualquer visão.
const monthValue = computed(() => {
  const d = anchor.value;
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
});
const onMonthPick = event => {
  const value = event.target.value;
  // Firefox desktop renderiza type="month" como texto livre: só aceita YYYY-MM.
  if (!/^\d{4}-\d{2}$/.test(value)) return;
  const [year, month] = value.split('-').map(Number);
  anchor.value = new Date(year, month - 1, 1);
};

// Clique num dia do mês → abre a visão do dia.
const openDay = day => {
  anchor.value = new Date(day);
  view.value = 'day';
};

// Mesmo padrão do Centro de Comando: abre o Funil e seleciona o lead (drawer).
const openLead = leadId => {
  router.push(accountScopedRoute('ramon_funil'));
  store.dispatch('leads/select', leadId);
};

const hasVisibleTasks = computed(() =>
  days.value.some(day => tasksByDay.value[dayKey(day)])
);
</script>

<template>
  <div
    class="flex flex-col w-full h-full overflow-y-auto bg-n-background p-4 sm:p-8"
  >
    <RamonPageHeader :title="t('RAMON.AGENDA.TITLE')" :subtitle="rangeLabel">
      <template #actions>
        <button
          class="flex items-center justify-center h-8 px-2 rounded-lg border border-n-weak text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
          :title="t('RAMON.AGENDA.PREV')"
          @click="shift(-1)"
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
          :title="t('RAMON.AGENDA.NEXT')"
          @click="shift(1)"
        >
          <span class="i-lucide-chevron-right size-4" />
        </button>
      </template>
    </RamonPageHeader>

    <!-- Barra de controles: visão + filtro de tipo à esquerda, mês à direita -->
    <div class="flex flex-wrap items-center justify-between gap-3 mb-4">
      <div class="flex flex-wrap items-center gap-3">
        <div
          class="inline-flex rounded-lg border border-n-weak overflow-hidden"
          data-testid="agenda-view-switch"
        >
          <button
            v-for="v in VIEWS"
            :key="v"
            :data-testid="`agenda-view-${v}`"
            class="px-3 h-8 text-sm"
            :class="
              view === v
                ? 'bg-n-iris-9 text-white'
                : 'text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12'
            "
            @click="view = v"
          >
            {{ t(`RAMON.AGENDA.VIEW_${v.toUpperCase()}`) }}
          </button>
        </div>
        <div class="flex items-center gap-1">
          <button
            v-for="k in KIND_FILTERS"
            :key="k"
            :data-testid="`agenda-filter-${k}`"
            class="px-2.5 h-7 text-xs rounded-full border"
            :class="
              kindFilter === k
                ? 'border-n-iris-8 text-n-iris-11 bg-n-alpha-2'
                : 'border-transparent text-n-slate-10 hover:text-n-slate-12'
            "
            @click="kindFilter = k"
          >
            {{ t(`RAMON.AGENDA.FILTER_${k.toUpperCase()}`) }}
          </button>
        </div>
      </div>
      <label class="flex items-center gap-1.5 text-xs text-n-slate-10">
        {{ t('RAMON.AGENDA.PICK_MONTH') }}
        <input
          type="month"
          data-testid="agenda-month-pick"
          class="h-8 px-2 text-sm rounded-lg bg-n-alpha-2 border border-transparent outline-none focus:border-n-slate-8 text-n-slate-12"
          :value="monthValue"
          @change="onMonthPick"
        />
      </label>
    </div>

    <!-- Skeleton enquanto carrega sem nada em cache -->
    <div
      v-if="isFetching && !hasVisibleTasks"
      data-testid="agenda-skeleton"
      class="flex flex-col gap-3 animate-pulse"
    >
      <div class="h-24 rounded-xl bg-n-solid-2" />
      <div class="h-24 rounded-xl bg-n-solid-2" />
      <div class="h-24 rounded-xl bg-n-solid-2" />
    </div>

    <!-- Erro de carga: retry em vez de fingir agenda vazia -->
    <div
      v-else-if="hasError && !hasVisibleTasks"
      data-testid="agenda-error"
      class="text-sm"
    >
      <p class="text-n-ruby-11">{{ t('RAMON.AGENDA.LOAD_ERROR') }}</p>
      <button
        type="button"
        data-testid="agenda-retry"
        class="mt-2 text-xs text-n-iris-11 hover:underline"
        @click="reload"
      >
        {{ t('RAMON.LEAD_PANEL.RETRY') }}
      </button>
    </div>

    <!-- VISÃO DIA -->
    <div v-else-if="view === 'day'" class="max-w-xl">
      <div
        class="flex flex-col rounded-xl border bg-n-solid-1"
        :class="isToday(anchor) ? 'border-n-iris-8' : 'border-n-weak'"
      >
        <div
          class="px-4 py-3 border-b border-n-weak text-xs uppercase tracking-wide"
          :class="isToday(anchor) ? 'text-n-iris-11' : 'text-n-slate-10'"
        >
          {{ fullDayLabel(anchor) }}
        </div>
        <div class="flex flex-col gap-2 p-3">
          <button
            v-for="task in tasksByDay[dayKey(anchor)] || []"
            :key="task.id"
            class="flex flex-col items-start gap-0.5 p-3 text-left rounded-lg border border-n-weak bg-n-solid-2 hover:bg-n-alpha-2"
            @click="openLead(task.lead_id)"
          >
            <span
              class="flex items-center gap-1.5 text-xs"
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
            <span class="text-sm text-n-slate-12">{{ task.title }}</span>
            <span v-if="task.lead_name" class="text-xs text-n-slate-11">
              {{ task.lead_name }}
            </span>
          </button>
          <p
            v-if="!(tasksByDay[dayKey(anchor)] || []).length"
            class="p-3 text-sm text-n-slate-10"
          >
            {{ t('RAMON.AGENDA.EMPTY_DAY') }}
          </p>
        </div>
      </div>
    </div>

    <!-- VISÃO SEMANA (só a grade rola na horizontal; header/filtros ficam fixos) -->
    <div v-else-if="view === 'week'" class="overflow-x-auto flex-1 min-h-0">
      <div class="grid grid-cols-7 gap-2 min-w-[840px]">
        <div
          v-for="day in days"
          :key="dayKey(day)"
          class="flex flex-col rounded-xl border bg-n-solid-1 min-h-[320px]"
          :class="isToday(day) ? 'border-n-iris-8' : 'border-n-weak'"
        >
          <div
            class="px-3 py-2 border-b border-n-weak text-xs uppercase tracking-wide"
            :class="[
              isToday(day) ? 'text-n-iris-11' : 'text-n-slate-10',
              { 'opacity-60': isWeekend(day) && !isToday(day) },
            ]"
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
    </div>

    <!-- VISÃO MÊS (mesma regra: overflow-x só na grade) -->
    <div v-else class="overflow-x-auto flex-1 min-h-0">
      <div class="flex flex-col min-w-[840px]">
        <div class="grid grid-cols-7 gap-2 mb-1">
          <div
            v-for="(label, i) in weekdayHeaders"
            :key="i"
            class="px-2 text-xs uppercase tracking-wide text-n-slate-10"
          >
            {{ label }}
          </div>
        </div>
        <div class="grid grid-cols-7 gap-2">
          <button
            v-for="day in days"
            :key="dayKey(day)"
            data-testid="agenda-month-day"
            class="flex flex-col items-stretch gap-1 p-2 min-h-[96px] text-left rounded-xl border bg-n-solid-1 hover:bg-n-alpha-2"
            :class="[
              isToday(day) ? 'border-n-iris-8' : 'border-n-weak',
              { 'opacity-50': !inAnchorMonth(day) },
            ]"
            @click="openDay(day)"
          >
            <span
              class="self-end text-xs tabular-nums"
              :class="
                isToday(day)
                  ? 'flex items-center justify-center rounded-full size-5 bg-n-iris-9 text-white'
                  : 'text-n-slate-10'
              "
            >
              {{ day.getDate() }}
            </span>
            <span
              v-for="task in (tasksByDay[dayKey(day)] || []).slice(0, 3)"
              :key="task.id"
              class="flex items-center gap-1 px-1.5 py-0.5 text-[11px] rounded truncate"
              :class="
                task.kind === 'meeting'
                  ? 'bg-n-alpha-2 text-n-iris-11'
                  : 'bg-n-alpha-2 text-n-slate-11'
              "
            >
              <span
                :class="
                  task.kind === 'meeting'
                    ? 'i-lucide-calendar-clock'
                    : 'i-lucide-bell'
                "
                class="size-3 flex-shrink-0"
              />
              <span class="truncate">{{ task.title }}</span>
            </span>
            <span
              v-if="(tasksByDay[dayKey(day)] || []).length > 3"
              class="px-1.5 text-[11px] text-n-slate-10"
            >
              {{
                t('RAMON.AGENDA.MORE', {
                  count: (tasksByDay[dayKey(day)] || []).length - 3,
                })
              }}
            </span>
          </button>
        </div>
      </div>
    </div>

    <!-- Visão dia já tem o próprio EMPTY_DAY dentro do card -->
    <p
      v-if="!isFetching && !hasError && !hasVisibleTasks && view !== 'day'"
      class="mt-4 text-sm text-center text-n-slate-10"
    >
      {{
        view === 'week'
          ? t('RAMON.AGENDA.EMPTY')
          : t('RAMON.AGENDA.EMPTY_MONTH')
      }}
    </p>
  </div>
</template>
