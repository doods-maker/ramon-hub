<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useStore, useStoreGetters } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';
import ramonAgendaAPI from 'dashboard/api/ramonAgenda';
import ramonGoogleAgendaAPI from 'dashboard/api/ramonGoogleAgenda';
import Button from 'dashboard/components-next/button/Button.vue';
import RamonPageHeader from '../components/RamonPageHeader.vue';
import {
  ABA,
  ABA_ATIVA,
  ABA_INATIVA,
  CAMPO,
  CARTAO,
  CHIP,
  LINHA,
  ROTULO,
  TITULO,
  TOM,
} from '../helpers/ui';

const { t } = useI18n();
const store = useStore();
const getters = useStoreGetters();
const router = useRouter();
const route = useRoute();
const { accountScopedRoute } = useAccount();

// ---- estado da visão: dia | semana | mês, ancorado numa data de referência
const VIEWS = ['day', 'week', 'month'];
const KIND_FILTERS = ['all', 'meeting', 'follow_up'];

// view e filtro persistem em localStorage; a âncora de data é volátil.
const VIEW_KEY = 'ramon_agenda_view';
const KIND_KEY = 'ramon_agenda_kind';
const PESSOAS_KEY = 'ramon_agenda_pessoas';
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
// Pessoas: ids selecionados (vazio = todas). Padrão: gestor vê todas, agente vê
// as suas. "Minhas" é o atalho que seleciona só o usuário atual.
const me = computed(() => getters.getCurrentUserID?.value);
const loadPessoas = () => {
  try {
    const saved = JSON.parse(localStorage.getItem(PESSOAS_KEY));
    if (Array.isArray(saved)) return saved.filter(Number.isInteger);
  } catch (e) {
    // localStorage indisponível ou valor inválido: cai no padrão
  }
  return getters.getCurrentRole?.value === 'administrator'
    ? []
    : [getters.getCurrentUserID?.value];
};
const pessoas = ref(loadPessoas());
const membros = ref([]);
const googleItems = ref([]);
const googleErro = ref(false);
const googleConectado = ref(true);

watch([view, kindFilter], () => {
  try {
    localStorage.setItem(VIEW_KEY, view.value);
    localStorage.setItem(KIND_KEY, kindFilter.value);
  } catch (e) {
    // localStorage indisponível: seguimos sem persistir
  }
});
watch(pessoas, () => {
  try {
    localStorage.setItem(PESSOAS_KEY, JSON.stringify(pessoas.value));
  } catch (e) {
    // localStorage indisponível: seguimos sem persistir
  }
});

// Cor estável por pessoa: índice na lista ordenada de ids dos membros.
const TONS_PESSOA = [TOM.blue, TOM.teal, TOM.amber, TOM.iris, TOM.ruby];
const tomDe = userId => {
  const ids = membros.value.map(m => m.id).sort((a, b) => a - b);
  const i = ids.indexOf(userId);
  return i < 0 ? TOM.slate : TONS_PESSOA[i % TONS_PESSOA.length];
};
const nomeDe = userId => membros.value.find(m => m.id === userId)?.name;
const primeiroNome = name => (name || '').split(' ')[0];

const togglePessoa = id => {
  pessoas.value = pessoas.value.includes(id)
    ? pessoas.value.filter(x => x !== id)
    : [...pessoas.value, id];
};
const soMinhas = () => {
  pessoas.value = [me.value];
};
const apenasMinhas = computed(
  () => pessoas.value.length === 1 && pessoas.value[0] === me.value
);

// Segunda-feira 00:00 da semana da data dada.
const startOfWeek = date => {
  const d = new Date(date);
  d.setHours(0, 0, 0, 0);
  d.setDate(d.getDate() - ((d.getDay() + 6) % 7));
  return d;
};
const startOfMonth = date => new Date(date.getFullYear(), date.getMonth(), 1);

const dayKey = d => d.toDateString();
const isToday = d => dayKey(d) === dayKey(new Date());
const isWeekend = d => d.getDay() === 0 || d.getDay() === 6;
const inAnchorMonth = d => d.getMonth() === anchor.value.getMonth();

const matchesKind = task => {
  if (task.google) return kindFilter.value !== 'follow_up';
  if (kindFilter.value === 'all') return true;
  if (kindFilter.value === 'meeting') return task.kind === 'meeting';
  return task.kind !== 'meeting';
};

// Pessoa da tarefa: dono da agenda da reunião; senão SDR/Closer do lead ou quem criou.
const pessoasDaTarefa = task => {
  if (task.agenda_user_id) return [task.agenda_user_id];
  return [task.sdr_id, task.closer_id, task.user_id].filter(Boolean);
};
const matchesPessoa = task => {
  if (task.google) return true; // já filtrado no servidor
  if (!pessoas.value.length) return true;
  return pessoasDaTarefa(task).some(id => pessoas.value.includes(id));
};

const startOfToday = () => {
  const d = new Date();
  d.setHours(0, 0, 0, 0);
  return d;
};
// vencida = aberta de um dia que já passou (a de hoje fica no horário dela)
const isOverdue = task =>
  !task.google && !task.completed_at && new Date(task.due_at) < startOfToday();
const isDoneToday = task =>
  Boolean(task.completed_at) &&
  dayKey(new Date(task.completed_at)) === dayKey(new Date());

// Concluída só aparece no dia em que foi feita (apagada, com check); vencida
// sai do dia dela e fica fixada no topo de Hoje.
const tasksByDay = computed(() => {
  const map = {};
  const vencidas = [];
  [...getters['leadTasks/getAccountTasks'].value, ...googleItems.value].forEach(
    task => {
      if (!task.due_at || (task.completed_at && !isDoneToday(task))) return;
      if (!matchesKind(task) || !matchesPessoa(task)) return;
      if (isOverdue(task)) {
        vencidas.push(task);
        return;
      }
      const key = dayKey(new Date(task.due_at));
      if (!map[key]) map[key] = [];
      map[key].push(task);
    }
  );
  // dentro do dia, por horário
  Object.values(map).forEach(list =>
    list.sort((a, b) => new Date(a.due_at) - new Date(b.due_at))
  );
  if (vencidas.length) {
    const hoje = dayKey(new Date());
    map[hoje] = [...vencidas, ...(map[hoje] || [])];
  }
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

// Compromissos do Google do comercial (cinza, só leitura). Falha aqui não
// derruba a agenda: some o Google e avisa; 403 = fora do comercial (sem Google).
let googleSeq = 0;
const loadGoogle = async (ini, fim) => {
  googleSeq += 1;
  const seq = googleSeq;
  try {
    const { data } = await ramonAgendaAPI.google({
      from: ini.toISOString(),
      to: fim.toISOString(),
      user_ids: pessoas.value,
    });
    if (seq !== googleSeq) return;
    membros.value = data.membros || [];
    googleErro.value = Boolean(data.erros?.length);
    googleItems.value = (data.payload || []).map((e, i) => ({
      id: `g-${e.user_id}-${i}`,
      google: true,
      kind: 'google',
      user_id: e.user_id,
      title: `${t('RAMON.AGENDA.GOOGLE')} · ${e.titulo}`,
      due_at: e.inicio,
    }));
  } catch (e) {
    if (seq !== googleSeq) return;
    googleItems.value = [];
    googleErro.value = e?.response?.status !== 403;
  }
};

// Período visível inteiro (abertas + feitas hoje + vencidas); o store troca
// as tarefas do período pelas do servidor — o que foi concluído ou cancelado
// em outra tela some sem F5. Filtros de tipo e dono são client-side.
const reload = () => {
  const ini = new Date(days.value[0]);
  const fim = new Date(days.value[days.value.length - 1]);
  fim.setHours(23, 59, 59, 999);
  loadGoogle(ini, fim);
  return store.dispatch('leadTasks/fetchAccountScope', {
    scope: 'agenda',
    from: ini.toISOString(),
    to: fim.toISOString(),
  });
};

const carregarStatusGoogle = async () => {
  try {
    const { data } = await ramonGoogleAgendaAPI.status();
    googleConectado.value = Boolean(data.conectada);
  } catch (e) {
    googleConectado.value = true; // sem status, não oferece conectar
  }
};
const conectarGoogle = async () => {
  try {
    const { data } = await ramonGoogleAgendaAPI.autorizacao();
    window.location.href = data.url;
  } catch (e) {
    useAlert(t('RAMON.AGENDA.GOOGLE_ERRO'));
  }
};

onMounted(() => {
  // volta do OAuth: ?google=ok|erro
  const retorno = route.query?.google;
  if (retorno === 'ok') useAlert(t('RAMON.AGENDA.GOOGLE_CONECTADO'));
  else if (retorno === 'erro') useAlert(t('RAMON.AGENDA.GOOGLE_ERRO'));
  if (retorno) router.replace({ query: {} });
  carregarStatusGoogle();
  reload();
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

// chip de horário: feita = cinza com check; reunião = azul; follow-up = cinza
const chipTom = task => {
  if (task.google || task.completed_at) return TOM.slate;
  return task.kind === 'meeting' ? TOM.blue : TOM.slate;
};
// vencida mostra o dia de origem junto da hora
const horaDe = task =>
  isOverdue(task)
    ? `${dateLabel(new Date(task.due_at))} ${timeLabel(task.due_at)}`
    : timeLabel(task.due_at);
const chipIcone = task => {
  if (task.google) return 'i-lucide-calendar';
  if (task.completed_at) return 'i-lucide-check';
  return task.kind === 'meeting' ? 'i-lucide-calendar-clock' : 'i-lucide-bell';
};

// Reunião: chip da pessoa (cor estável) e formato (Meet com link × ligação).
const pessoaDaReuniao = task =>
  task.kind === 'meeting' && task.agenda_user_id
    ? primeiroNome(task.agenda_user_name || nomeDe(task.agenda_user_id))
    : null;
const abrirMeet = task => window.open(task.meet_url, '_blank', 'noopener');

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
  if (!leadId) return; // compromisso do Google não tem lead
  router.push(accountScopedRoute('ramon_funil'));
  store.dispatch('leads/select', leadId);
};

const hasVisibleTasks = computed(() =>
  days.value.some(day => tasksByDay.value[dayKey(day)])
);

// trocou a seleção de pessoas → refaz só o Google (as tarefas filtram no cliente)
watch(pessoas, () => reload());

// trocou o período (navegação, visão, mês) → busca o período novo
watch(
  () => `${dayKey(days.value[0])}|${days.value.length}`,
  () => reload()
);
</script>

<template>
  <div class="w-full h-full overflow-y-auto bg-n-background p-4 sm:p-8">
    <div class="flex flex-col w-full max-w-6xl mx-auto">
      <RamonPageHeader :title="t('RAMON.AGENDA.TITLE')" :subtitle="rangeLabel">
        <template #actions>
          <Button
            sm
            faded
            slate
            icon="i-lucide-chevron-left"
            :title="t('RAMON.AGENDA.PREV')"
            @click="shift(-1)"
          />
          <Button
            sm
            faded
            slate
            :label="t('RAMON.AGENDA.TODAY')"
            @click="goToday"
          />
          <Button
            sm
            faded
            slate
            icon="i-lucide-chevron-right"
            :title="t('RAMON.AGENDA.NEXT')"
            @click="shift(1)"
          />
          <Button
            v-if="!googleConectado"
            sm
            faded
            blue
            icon="i-lucide-calendar-plus"
            data-testid="agenda-conectar-google"
            :label="t('RAMON.AGENDA.CONECTAR_GOOGLE')"
            @click="conectarGoogle"
          />
        </template>
      </RamonPageHeader>

      <!-- Barra de controles: visão + filtro de tipo à esquerda, mês à direita -->
      <div
        class="flex flex-wrap items-end justify-between gap-3 mb-4 border-b border-n-weak"
      >
        <div class="flex flex-wrap items-center gap-4">
          <div class="flex" data-testid="agenda-view-switch">
            <button
              v-for="v in VIEWS"
              :key="v"
              type="button"
              :data-testid="`agenda-view-${v}`"
              :class="[ABA, view === v ? ABA_ATIVA : ABA_INATIVA]"
              class="border-solid"
              @click="view = v"
            >
              {{ t(`RAMON.AGENDA.VIEW_${v.toUpperCase()}`) }}
            </button>
          </div>
          <div class="flex items-center gap-1 pb-1.5">
            <button
              v-for="k in KIND_FILTERS"
              :key="k"
              type="button"
              :data-testid="`agenda-filter-${k}`"
              :class="[
                CHIP,
                kindFilter === k
                  ? TOM.blue
                  : 'text-n-slate-10 hover:bg-n-alpha-2 hover:text-n-slate-12',
              ]"
              @click="kindFilter = k"
            >
              {{ t(`RAMON.AGENDA.FILTER_${k.toUpperCase()}`) }}
            </button>
          </div>
          <div
            class="flex flex-wrap items-center gap-1 pb-1.5"
            data-testid="agenda-pessoas"
          >
            <button
              type="button"
              data-testid="agenda-pessoas-minhas"
              :class="[
                CHIP,
                apenasMinhas
                  ? TOM.blue
                  : 'text-n-slate-10 hover:bg-n-alpha-2 hover:text-n-slate-12',
              ]"
              @click="soMinhas"
            >
              {{ t('RAMON.AGENDA.OWNER_MINE') }}
            </button>
            <button
              type="button"
              data-testid="agenda-pessoas-todas"
              :class="[
                CHIP,
                !pessoas.length
                  ? TOM.blue
                  : 'text-n-slate-10 hover:bg-n-alpha-2 hover:text-n-slate-12',
              ]"
              @click="pessoas = []"
            >
              {{ t('RAMON.AGENDA.TODAS_PESSOAS') }}
            </button>
            <button
              v-for="m in membros"
              :key="m.id"
              type="button"
              data-testid="agenda-pessoa"
              :title="t('RAMON.AGENDA.PESSOAS')"
              :class="[
                CHIP,
                pessoas.includes(m.id)
                  ? tomDe(m.id)
                  : 'text-n-slate-10 hover:bg-n-alpha-2 hover:text-n-slate-12',
              ]"
              @click="togglePessoa(m.id)"
            >
              {{ primeiroNome(m.name) }}
            </button>
          </div>
        </div>
        <label :class="ROTULO" class="!flex-row items-center pb-1.5">
          {{ t('RAMON.AGENDA.PICK_MONTH') }}
          <input
            type="month"
            data-testid="agenda-month-pick"
            :class="CAMPO"
            class="!w-44"
            :value="monthValue"
            @change="onMonthPick"
          />
        </label>
      </div>

      <p
        v-if="googleErro"
        data-testid="agenda-google-erro"
        class="mb-3 text-xs text-n-amber-11"
      >
        {{ t('RAMON.AGENDA.GOOGLE_ERRO') }}
      </p>

      <!-- Skeleton enquanto carrega sem nada em cache -->
      <div
        v-if="isFetching && !hasVisibleTasks"
        data-testid="agenda-skeleton"
        class="flex flex-col gap-3 animate-pulse"
      >
        <div class="h-24 rounded-xl bg-n-alpha-2" />
        <div class="h-24 rounded-xl bg-n-alpha-2" />
        <div class="h-24 rounded-xl bg-n-alpha-2" />
      </div>

      <!-- Erro de carga: retry em vez de fingir agenda vazia -->
      <div
        v-else-if="hasError && !hasVisibleTasks"
        data-testid="agenda-error"
        class="text-sm"
      >
        <p class="text-n-ruby-11">{{ t('RAMON.AGENDA.LOAD_ERROR') }}</p>
        <Button
          data-testid="agenda-retry"
          link
          xs
          class="mt-2"
          :label="t('RAMON.LEAD_PANEL.RETRY')"
          @click="reload"
        />
      </div>

      <!-- VISÃO DIA -->
      <div v-else-if="view === 'day'" class="w-full max-w-2xl mx-auto">
        <div
          :class="[CARTAO, isToday(anchor) ? '!border-n-blue-8' : '']"
          class="flex flex-col !p-0"
        >
          <div
            :class="[TITULO, isToday(anchor) ? '!text-n-blue-11' : '']"
            class="px-4 py-3 border-b border-n-weak"
          >
            {{ fullDayLabel(anchor) }}
          </div>
          <div class="flex flex-col p-2">
            <button
              v-for="(task, index) in tasksByDay[dayKey(anchor)] || []"
              :key="task.id"
              type="button"
              :class="[
                LINHA,
                index > 0
                  ? 'border-t border-solid border-n-weak !rounded-none'
                  : '',
                { 'opacity-60': task.completed_at },
              ]"
              class="flex items-start gap-3 !py-2.5"
              data-testid="agenda-task"
              @click="openLead(task.lead_id)"
            >
              <span
                :class="[CHIP, chipTom(task)]"
                class="flex-none mt-0.5 font-mono tabular-nums"
              >
                <span :class="chipIcone(task)" class="size-3 flex-shrink-0" />
                {{ horaDe(task) }}
              </span>
              <span
                v-if="isOverdue(task)"
                :class="[CHIP, TOM.ruby]"
                class="flex-none mt-0.5"
                data-testid="agenda-overdue"
              >
                {{ t('RAMON.AGENDA.OVERDUE') }}
              </span>
              <span class="flex flex-col flex-1 min-w-0">
                <span class="text-sm font-medium text-n-slate-12">
                  {{ task.title }}
                </span>
                <span
                  v-if="task.lead_name"
                  class="text-xs truncate text-n-slate-10"
                >
                  {{ task.lead_name }}
                </span>
              </span>
              <span class="flex flex-wrap items-center flex-none gap-1 mt-0.5">
                <span
                  v-if="pessoaDaReuniao(task)"
                  :class="[CHIP, tomDe(task.agenda_user_id)]"
                  data-testid="agenda-pessoa-chip"
                >
                  {{ pessoaDaReuniao(task) }}
                </span>
                <span
                  v-if="task.google && nomeDe(task.user_id)"
                  :class="[CHIP, tomDe(task.user_id)]"
                >
                  {{ primeiroNome(nomeDe(task.user_id)) }}
                </span>
                <span
                  v-if="task.kind === 'meeting' && task.formato === 'whatsapp'"
                  :class="[CHIP, TOM.teal]"
                >
                  {{ t('RAMON.AGENDA.WHATSAPP') }}
                </span>
                <span
                  v-else-if="task.kind === 'meeting' && task.meet_url"
                  :class="[CHIP, TOM.blue]"
                  class="cursor-pointer"
                  data-testid="agenda-meet"
                  @click.stop="abrirMeet(task)"
                >
                  {{ t('RAMON.AGENDA.MEET') }}
                </span>
              </span>
            </button>
            <p
              v-if="!(tasksByDay[dayKey(anchor)] || []).length"
              class="p-2 text-sm text-n-slate-10"
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
            :class="[CARTAO, isToday(day) ? '!border-n-blue-8' : '']"
            class="flex flex-col !p-0 min-h-[320px]"
          >
            <div
              class="flex items-center justify-between gap-1 px-3 py-2 border-b border-n-weak"
              :class="{ 'opacity-60': isWeekend(day) && !isToday(day) }"
            >
              <span :class="[TITULO, isToday(day) ? '!text-n-blue-11' : '']">
                {{ dayLabel(day) }}
              </span>
              <span
                class="font-mono text-[13px] font-medium tabular-nums"
                :class="
                  isToday(day)
                    ? [CHIP, TOM.blue, '!px-2 !text-[13px]']
                    : 'text-n-slate-12'
                "
              >
                {{ dateLabel(day) }}
              </span>
            </div>
            <div class="flex flex-col p-1.5">
              <button
                v-for="(task, index) in tasksByDay[dayKey(day)] || []"
                :key="task.id"
                type="button"
                :class="[
                  LINHA,
                  index > 0
                    ? 'border-t border-solid border-n-weak !rounded-none'
                    : '',
                  { 'opacity-60': task.completed_at },
                ]"
                class="flex flex-col items-start gap-1 !py-2"
                data-testid="agenda-task"
                @click="openLead(task.lead_id)"
              >
                <span class="flex flex-wrap items-center gap-1">
                  <span
                    :class="[CHIP, chipTom(task)]"
                    class="font-mono tabular-nums"
                  >
                    <span
                      :class="chipIcone(task)"
                      class="size-3 flex-shrink-0"
                    />
                    {{ horaDe(task) }}
                  </span>
                  <span
                    v-if="isOverdue(task)"
                    :class="[CHIP, TOM.ruby]"
                    data-testid="agenda-overdue"
                  >
                    {{ t('RAMON.AGENDA.OVERDUE') }}
                  </span>
                </span>
                <span
                  class="text-[13px] font-medium leading-snug text-n-slate-12 line-clamp-2"
                >
                  {{ task.title }}
                </span>
                <span
                  v-if="task.lead_name"
                  class="w-full text-[11px] truncate text-n-slate-10"
                >
                  {{ task.lead_name }}
                </span>
                <span class="flex flex-wrap items-center gap-1">
                  <span
                    v-if="pessoaDaReuniao(task)"
                    :class="[CHIP, tomDe(task.agenda_user_id)]"
                    data-testid="agenda-pessoa-chip"
                  >
                    {{ pessoaDaReuniao(task) }}
                  </span>
                  <span
                    v-if="task.google && nomeDe(task.user_id)"
                    :class="[CHIP, tomDe(task.user_id)]"
                  >
                    {{ primeiroNome(nomeDe(task.user_id)) }}
                  </span>
                  <span
                    v-if="
                      task.kind === 'meeting' && task.formato === 'whatsapp'
                    "
                    :class="[CHIP, TOM.teal]"
                  >
                    {{ t('RAMON.AGENDA.WHATSAPP') }}
                  </span>
                  <span
                    v-else-if="task.kind === 'meeting' && task.meet_url"
                    :class="[CHIP, TOM.blue]"
                    class="cursor-pointer"
                    data-testid="agenda-meet"
                    @click.stop="abrirMeet(task)"
                  >
                    {{ t('RAMON.AGENDA.MEET') }}
                  </span>
                </span>
              </button>
            </div>
          </div>
        </div>
      </div>

      <!-- VISÃO MÊS (mesma regra: overflow-x só na grade) -->
      <div v-else class="overflow-x-auto flex-1 min-h-0">
        <div class="flex flex-col min-w-[840px]">
          <div class="grid grid-cols-7 gap-2 mb-1.5">
            <div
              v-for="(label, i) in weekdayHeaders"
              :key="i"
              :class="TITULO"
              class="px-2"
            >
              {{ label }}
            </div>
          </div>
          <div class="grid grid-cols-7 gap-2">
            <button
              v-for="day in days"
              :key="dayKey(day)"
              type="button"
              data-testid="agenda-month-day"
              :class="[
                CARTAO,
                isToday(day) ? '!border-n-blue-8' : '',
                { 'opacity-50': !inAnchorMonth(day) },
              ]"
              class="flex flex-col items-stretch gap-1 !p-2 min-h-[96px] text-left border-solid hover:bg-n-alpha-2"
              @click="openDay(day)"
            >
              <span
                class="self-end font-mono text-xs tabular-nums"
                :class="
                  isToday(day)
                    ? [CHIP, TOM.blue, '!px-1.5 font-semibold']
                    : 'text-n-slate-10'
                "
              >
                {{ day.getDate() }}
              </span>
              <span
                v-for="task in (tasksByDay[dayKey(day)] || []).slice(0, 3)"
                :key="task.id"
                class="flex items-center gap-1 px-1.5 py-0.5 text-[11px] rounded-md truncate"
                :class="[
                  isOverdue(task) ? TOM.ruby : chipTom(task),
                  { 'opacity-60': task.completed_at },
                ]"
              >
                <span :class="chipIcone(task)" class="size-3 flex-shrink-0" />
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
  </div>
</template>
