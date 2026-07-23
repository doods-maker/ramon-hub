<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useStore, useStoreGetters } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useAlert } from 'dashboard/composables';
import { useKeyboardEvents } from 'dashboard/composables/useKeyboardEvents';
import { prescriptionInfo } from '../helpers/prescription';
import { brlCompact } from '../helpers/currency';
import AgendaToday from '../components/command/AgendaToday.vue';
import NightCopilot from '../components/command/NightCopilot.vue';
import FunnelConversion from '../components/command/FunnelConversion.vue';
import TeamWeek from '../components/command/TeamWeek.vue';
import LossesByThesis from '../components/command/LossesByThesis.vue';
import Sparkline from '../components/command/Sparkline.vue';

const { t } = useI18n();
const store = useStore();
const getters = useStoreGetters();
const router = useRouter();
const { accountScopedRoute } = useAccount();
const { isAdmin } = useAdmin();

const data = computed(() => getters['ramonDashboard/getData'].value);
const uiFlags = computed(() => getters['ramonDashboard/getUIFlags'].value);
const isFetching = computed(() => uiFlags.value.isFetching);
const isLoading = computed(() => isFetching.value && !data.value);
const hasError = computed(() => uiFlags.value.hasError);

const reload = () => store.dispatch('ramonDashboard/fetch');
onMounted(reload);

const money = value =>
  new Intl.NumberFormat('pt-BR', {
    style: 'currency',
    currency: 'BRL',
    maximumFractionDigits: 0,
  }).format(Number(value) || 0);

// ---- Header: saudação + data + meta do dia -------------------------------
const currentUser = computed(() => getters.getCurrentUser.value || {});
const firstName = computed(
  () => (currentUser.value.name || '').split(' ')[0] || ''
);
const greetingKey = computed(() => {
  const hour = new Date().getHours();
  if (hour < 12) return 'RAMON.COMMAND.GREETING_MORNING';
  if (hour < 18) return 'RAMON.COMMAND.GREETING_AFTERNOON';
  return 'RAMON.COMMAND.GREETING_EVENING';
});
const dateLine = new Intl.DateTimeFormat('pt-BR', {
  weekday: 'long',
  day: 'numeric',
  month: 'long',
}).format(new Date());

const goal = computed(() => data.value?.goal || { target: 0, done: 0 });
const goalPct = computed(() => {
  const { target, done } = goal.value;
  if (!target) return 0;
  return Math.min(100, Math.round((done / target) * 100));
});

const startDay = () => router.push(accountScopedRoute('ramon_esteira'));

// ---- Blocos do payload ----------------------------------------------------
const today = computed(() => data.value?.today || {});
const section = key => today.value[key] || { count: 0, items: [] };
const week = computed(() => data.value?.week || {});
const nps = computed(() => week.value.nps || null);
const funnel = computed(() => data.value?.funnel || []);
const conversion = computed(() => data.value?.conversion || []);
const teamWeek = computed(() => data.value?.team_week || []);
const agendaToday = computed(() => data.value?.agenda_today || []);
const losses = computed(() => data.value?.losses_by_thesis || null);
const sla = computed(() => data.value?.sla_today || null);
const history = computed(() => data.value?.history || []);
const historyPoints = computed(() =>
  history.value.map(h => Number(h.value_sum) || 0)
);
const historyLatest = computed(
  () => history.value[history.value.length - 1] || null
);

// ---- KPI strip ------------------------------------------------------------
const kpis = computed(() => [
  {
    key: 'overdue',
    value: section('tasks_overdue').count,
    label: t('RAMON.COMMAND.KPI.OVERDUE'),
    class:
      section('tasks_overdue').count > 0 ? 'text-n-ruby-11' : 'text-n-slate-12',
  },
  {
    key: 'today',
    value: section('tasks_today').count,
    label: t('RAMON.COMMAND.KPI.TODAY'),
    class: 'text-n-slate-12',
  },
  {
    key: 'stalled',
    value: section('stalled').count,
    label: t('RAMON.COMMAND.KPI.STALLED'),
    class: section('stalled').count > 0 ? 'text-n-amber-11' : 'text-n-slate-12',
  },
  {
    key: 'new_from_lp',
    value: section('new_from_lp').count,
    label: t('RAMON.COMMAND.KPI.NEW_FROM_LP'),
    class: 'text-n-slate-12',
  },
  {
    key: 'won_week',
    value: week.value.won || 0,
    label: t('RAMON.COMMAND.KPI.WON_WEEK'),
    class: 'text-n-teal-11',
  },
  {
    key: 'forecast',
    value: brlCompact(data.value?.forecast_total),
    label: t('RAMON.COMMAND.KPI.FORECAST'),
    class: 'text-n-iris-11',
  },
]);

const slaAvgLabel = computed(() => {
  const minutes = sla.value?.avg_first_response_minutes;
  return minutes == null
    ? t('RAMON.COMMAND.SLA.AVG_EMPTY')
    : t('RAMON.COMMAND.SLA.AVG', { minutes });
});

// ---- Fila de retomada -----------------------------------------------------
// União client-side de tarefas vencidas + parados, deduplicada por lead.
// A tarefa vence o desempate (entra primeiro e mantém título/prazo); o item
// "parado" enriquece etapa/telefone/conversa quando o mesmo lead aparece nos
// dois blocos. Ordenada por dinheiro prescrevendo desc.
const followUpQueue = computed(() => {
  const byLead = new Map();
  const order = [];

  section('tasks_overdue').items.forEach(task => {
    const leadId = task.lead_id;
    // itens vêm em due_at asc: a primeira task do lead é a mais atrasada
    if (byLead.has(leadId)) return;
    order.push(leadId);
    byLead.set(leadId, {
      leadId,
      leadName: task.lead_name,
      stageName: null,
      daysInStage: null,
      taskId: task.id,
      taskTitle: task.title,
      dueAt: task.due_at,
      conversationId: null,
      contactPhone: null,
      dcbEm: task.dcb_em,
      benefitMonthlyValue: task.benefit_monthly_value,
    });
  });

  section('stalled').items.forEach(lead => {
    const leadId = lead.id;
    const existing = byLead.get(leadId);
    if (existing) {
      // Enriquecimento: nunca sobrescreve os campos de tarefa (task ganha).
      existing.stageName = lead.stage_name;
      existing.daysInStage = lead.days_in_stage;
      existing.conversationId = lead.conversation_id;
      existing.contactPhone = lead.contact_phone;
      existing.dcbEm = lead.dcb_em;
      existing.benefitMonthlyValue = lead.benefit_monthly_value;
      return;
    }
    order.push(leadId);
    byLead.set(leadId, {
      leadId,
      leadName: lead.name,
      stageName: lead.stage_name,
      daysInStage: lead.days_in_stage,
      taskId: null,
      taskTitle: null,
      dueAt: null,
      conversationId: lead.conversation_id,
      contactPhone: lead.contact_phone,
      dcbEm: lead.dcb_em,
      benefitMonthlyValue: lead.benefit_monthly_value,
    });
  });

  const bleedRate = item => {
    const p = prescriptionInfo({
      dcb_em: item.dcbEm,
      benefit_monthly_value: item.benefitMonthlyValue,
    });
    return p && p.lostInstallments > 0 && p.monthlyValue ? p.monthlyValue : 0;
  };

  return order
    .map(leadId => byLead.get(leadId))
    .sort((a, b) => bleedRate(b) - bleedRate(a));
});

// Fila local: Espaço gira (pula), Feito remove; refetch re-hidrata via watch.
const queue = ref([]);
watch(
  followUpQueue,
  value => {
    queue.value = [...value];
  },
  { immediate: true }
);

const current = computed(() => queue.value[0] || null);
const nextItems = computed(() => queue.value.slice(1, 6));

const skip = () => {
  if (queue.value.length > 1) queue.value.push(queue.value.shift());
};

// Clique num item da lista traz ele pra frente da fila (hero).
const jumpTo = index => {
  const [item] = queue.value.splice(index + 1, 1);
  queue.value.unshift(item);
};

const bleeding = item =>
  prescriptionInfo({
    dcb_em: item.dcbEm,
    benefit_monthly_value: item.benefitMonthlyValue,
  });

const heroChips = computed(() => {
  const item = current.value;
  if (!item) return [];
  const chips = [];
  const p = bleeding(item);
  if (p && p.lostInstallments > 0 && p.monthlyValue) {
    chips.push({
      key: 'bleeding',
      class: 'bg-n-ruby-9 text-white font-medium',
      label: t('RAMON.COMMAND.QUEUE.CHIP_BLEEDING', {
        value: money(p.monthlyValue),
      }),
    });
  }
  if (item.taskTitle) {
    chips.push({
      key: 'overdue',
      class: 'bg-n-alpha-2 text-n-slate-11',
      label: t('RAMON.COMMAND.QUEUE.CHIP_OVERDUE', { title: item.taskTitle }),
    });
  } else if (item.daysInStage != null) {
    chips.push({
      key: 'stalled',
      class: 'bg-n-alpha-2 text-n-slate-11',
      label: t('RAMON.COMMAND.QUEUE.CHIP_STALLED', {
        days: item.daysInStage,
      }),
    });
  }
  return chips;
});

const stageAge = item =>
  item.daysInStage != null
    ? t('RAMON.COMMAND.QUEUE.STAGE_AGE', {
        stage: item.stageName,
        days: item.daysInStage,
      })
    : item.stageName;

const itemValue = item =>
  item.benefitMonthlyValue
    ? t('RAMON.COMMAND.QUEUE.MONTHLY', {
        value: money(item.benefitMonthlyValue),
      })
    : '—';

const rowMotive = item =>
  item.taskTitle
    ? t('RAMON.COMMAND.QUEUE.ROW_OVERDUE', { title: item.taskTitle })
    : t('RAMON.COMMAND.QUEUE.ROW_STALLED', {
        days: item.daysInStage ?? 0,
        stage: item.stageName || '',
      });

// Dot de severidade: prescrevendo/vencida = ruby, parado = âmbar.
const severityDotClass = item => {
  const p = bleeding(item);
  if ((p && p.lostInstallments > 0 && p.monthlyValue) || item.taskId)
    return 'bg-n-ruby-9';
  return 'bg-n-amber-9';
};

// ---- Ações ----------------------------------------------------------------
// Clique num lead → abre o Funil e seleciona o lead (drawer).
const openLead = id => {
  router.push(accountScopedRoute('ramon_funil'));
  store.dispatch('leads/select', id);
};

// Clique numa etapa do funil → abre o Funil filtrado por essa etapa.
const openStage = stageId => {
  router.push(accountScopedRoute('ramon_funil'));
  store.dispatch('leads/setFilters', { leadStageId: String(stageId) });
  store.dispatch('leads/get');
};

const openAgenda = () => router.push(accountScopedRoute('ramon_agenda'));

// Abrir conversa (padrão do fork: funil + dock); sem conversa → painel do lead.
const openConversation = item => {
  if (!item) return;
  if (item.conversationId) {
    router.push(accountScopedRoute('ramon_funil'));
    store.dispatch('leads/toggleDock', item.conversationId);
  } else {
    openLead(item.leadId);
  }
};

// Feito: conclui a task se houver; senão navega ao lead pra resolver lá.
const isActing = ref(false);
const markDone = async () => {
  const item = current.value;
  if (!item || isActing.value) return;
  if (!item.taskId) {
    openLead(item.leadId);
    return;
  }
  isActing.value = true;
  try {
    await store.dispatch('leadTasks/complete', {
      leadId: item.leadId,
      taskId: item.taskId,
    });
    useAlert(t('RAMON.COMMAND.QUEUE.TASK_COMPLETED'));
    queue.value.shift();
    // Re-hidrata os KPIs; o watch re-copia a fila quando o payload voltar.
    store.dispatch('ramonDashboard/fetch');
  } catch (e) {
    useAlert(t('RAMON.COMMAND.QUEUE.COMPLETE_ERROR'));
  } finally {
    isActing.value = false;
  }
};

// Atalhos reais da fila (mudos com campo focado — o composable cuida disso;
// a página não tem modais próprios).
const canAct = () => !isLoading.value && !hasError.value && !!current.value;
useKeyboardEvents({
  Space: {
    action: e => {
      if (!canAct()) return;
      e.preventDefault();
      skip();
    },
  },
  KeyF: {
    action: () => {
      if (canAct()) markDone();
    },
  },
});
</script>

<template>
  <div
    class="flex flex-col w-full h-full gap-5 overflow-auto bg-n-background p-4 sm:p-8"
  >
    <!-- Header: saudação + data + meta do dia + CTA -->
    <header class="flex flex-wrap items-center justify-between gap-4">
      <div>
        <p class="text-[11px] tracking-[.2em] uppercase text-n-slate-10">
          {{ dateLine }}
        </p>
        <h1
          class="font-cormorant text-[32px] font-semibold leading-tight text-n-slate-12"
        >
          {{ t(greetingKey, { name: firstName }) }}
        </h1>
      </div>
      <div class="flex flex-wrap items-center gap-5">
        <div data-testid="daily-goal" class="text-right">
          <p class="text-[11px] uppercase tracking-[.08em] text-n-slate-10">
            {{ t('RAMON.COMMAND.GOAL_LABEL') }}
          </p>
          <div class="flex items-center gap-2 mt-1">
            <span
              class="block w-40 h-1.5 overflow-hidden rounded-full bg-[#c9a97c]/[.15]"
            >
              <span
                class="block h-full rounded-full bg-gradient-to-r from-[#8a5c33] to-[#c9a97c] transition-all duration-200"
                :style="{ width: `${goalPct}%` }"
              />
            </span>
            <span
              class="text-[13px] font-semibold tabular-nums text-n-slate-12"
            >
              {{
                t('RAMON.COMMAND.GOAL_PROGRESS', {
                  done: goal.done,
                  target: goal.target,
                })
              }}
            </span>
          </div>
        </div>
        <button
          type="button"
          data-testid="reload"
          :title="t('RAMON.COMMAND.RELOAD')"
          class="flex items-center justify-center rounded-full size-8 text-n-slate-10 hover:bg-n-alpha-2 hover:text-n-slate-12 disabled:opacity-50 disabled:pointer-events-none"
          :disabled="isFetching"
          @click="reload"
        >
          <span class="i-lucide-refresh-cw size-4" />
        </button>
        <button
          type="button"
          data-testid="start-day"
          class="inline-flex items-center h-[38px] gap-2 px-[18px] text-sm font-semibold rounded-[10px] bg-n-iris-9 text-white hover:bg-n-iris-10 shadow-md"
          @click="startDay"
        >
          <span class="i-lucide-play size-4" />
          {{ t('RAMON.COMMAND.START_DAY') }}
        </button>
      </div>
    </header>

    <!-- Enquanto você dormia (copiloto noturno) — some quando 0 pendentes -->
    <NightCopilot />

    <div v-if="isLoading" class="flex flex-col gap-5 animate-pulse">
      <div class="grid grid-cols-2 sm:grid-cols-3 xl:grid-cols-6 gap-2.5">
        <div v-for="n in 6" :key="n" class="h-16 rounded-[10px] bg-n-solid-2" />
      </div>
      <div class="grid grid-cols-1 lg:grid-cols-[1.5fr_1fr] gap-5">
        <div class="h-64 rounded-[14px] bg-n-solid-2" />
        <div class="flex flex-col gap-3">
          <div
            v-for="n in 2"
            :key="n"
            class="h-32 rounded-[14px] bg-n-solid-2"
          />
        </div>
      </div>
    </div>

    <!-- Erro de carga: mostra retry em vez de fingir "tudo em dia" -->
    <div v-else-if="hasError" data-testid="command-error" class="text-sm">
      <p class="text-n-ruby-11">{{ t('RAMON.COMMAND.LOAD_ERROR') }}</p>
      <button
        type="button"
        data-testid="command-retry"
        class="mt-2 text-xs text-n-iris-11 hover:underline"
        @click="reload"
      >
        {{ t('RAMON.LEAD_PANEL.RETRY') }}
      </button>
    </div>

    <div v-else class="flex flex-col gap-5">
      <!-- KPI strip -->
      <div>
        <div
          data-testid="kpi-strip"
          class="grid grid-cols-2 sm:grid-cols-3 xl:grid-cols-6 gap-2.5"
        >
          <div
            v-for="kpi in kpis"
            :key="kpi.key"
            :data-testid="`kpi-${kpi.key}`"
            class="p-3 rounded-[10px] border border-n-weak bg-n-solid-2"
          >
            <p class="text-xl font-semibold tabular-nums" :class="kpi.class">
              {{ kpi.value }}
            </p>
            <p class="mt-0.5 text-[10.5px] text-n-slate-10">{{ kpi.label }}</p>
          </div>
        </div>
        <!-- SLA de 1ª resposta: sub-linha discreta (não cabe no grid de 6) -->
        <p
          v-if="sla"
          data-testid="sla-line"
          class="mt-1.5 text-[11px] text-n-slate-10"
        >
          <span :class="{ 'text-n-ruby-11': sla.breached > 0 }">
            {{ t('RAMON.COMMAND.SLA.BREACHED', { count: sla.breached }) }}
          </span>
          {{ ` · ${slaAvgLabel}` }}
        </p>
      </div>

      <!-- Grid principal: fila (1.5fr) + coluna direita (1fr) -->
      <div class="grid items-start grid-cols-1 lg:grid-cols-[1.5fr_1fr] gap-5">
        <!-- Sua fila agora -->
        <div class="flex flex-col gap-2.5 min-w-0">
          <div class="flex items-baseline justify-between">
            <h2
              class="text-xs font-semibold tracking-[.12em] uppercase text-n-slate-10"
            >
              {{ t('RAMON.COMMAND.QUEUE.TITLE') }}
            </h2>
            <span class="text-[11px] text-n-slate-9">
              {{ t('RAMON.COMMAND.QUEUE.SORTED_BY') }}
            </span>
          </div>

          <div
            v-if="current"
            data-testid="queue-hero"
            class="p-5 rounded-[14px] border border-[#c9a97c]/[.28] bg-gradient-to-br from-[#33302c] to-[#2e2b27] shadow-[0_4px_16px_rgba(0,0,0,0.3)]"
          >
            <div class="flex items-start justify-between gap-3">
              <div class="min-w-0">
                <div class="flex flex-wrap items-center gap-2.5">
                  <p
                    class="font-cormorant text-[26px] font-semibold leading-tight text-n-slate-12"
                  >
                    {{ current.leadName }}
                  </p>
                  <span
                    v-if="current.stageName"
                    class="px-2 py-0.5 text-[10.5px] rounded-full bg-[#c9a97c]/[.14] text-n-iris-11 border border-[#c9a97c]/[.25]"
                  >
                    {{ stageAge(current) }}
                  </span>
                </div>
                <div
                  data-testid="queue-hero-chips"
                  class="flex flex-wrap gap-1.5 mt-2"
                >
                  <span
                    v-for="chip in heroChips"
                    :key="chip.key"
                    class="px-2.5 py-0.5 text-[11px] rounded-full"
                    :class="chip.class"
                  >
                    {{ chip.label }}
                  </span>
                </div>
              </div>
              <span
                class="flex-none text-[15px] font-semibold tabular-nums text-n-iris-11"
              >
                {{ itemValue(current) }}
              </span>
            </div>
            <div
              class="flex flex-wrap items-center gap-2 mt-4 pt-3.5 border-t border-[#c9a97c]/[.12]"
            >
              <button
                type="button"
                data-testid="queue-open-conversation"
                class="inline-flex items-center h-[34px] gap-1.5 px-3.5 text-[13px] font-semibold rounded-[9px] bg-n-iris-9 text-white hover:bg-n-iris-10"
                @click="openConversation(current)"
              >
                <span class="i-lucide-message-square size-4" />
                {{ t('RAMON.COMMAND.QUEUE.OPEN_CONVERSATION') }}
              </button>
              <button
                type="button"
                data-testid="queue-ai-draft"
                class="inline-flex items-center h-[34px] gap-1.5 px-3.5 text-[13px] rounded-[9px] border border-[#c9a97c]/[.2] text-n-slate-11 hover:text-n-slate-12 hover:bg-n-alpha-2"
                @click="openConversation(current)"
              >
                {{ t('RAMON.COMMAND.QUEUE.AI_DRAFT') }}
              </button>
              <button
                type="button"
                data-testid="queue-done"
                class="inline-flex items-center h-[34px] gap-1.5 px-3.5 text-[13px] rounded-[9px] border border-[#c9a97c]/[.2] text-n-slate-11 hover:text-n-slate-12 hover:bg-n-alpha-2 disabled:opacity-50"
                :disabled="isActing"
                @click="markDone"
              >
                {{ t('RAMON.COMMAND.QUEUE.DONE') }}
              </button>
              <span class="ml-auto text-[11px] text-n-slate-9">
                {{ t('RAMON.COMMAND.QUEUE.HINT') }}
              </span>
            </div>
          </div>

          <!-- Fila zerada -->
          <div
            v-else
            data-testid="queue-empty"
            class="py-8 text-center rounded-[14px] border border-n-weak bg-n-solid-2"
          >
            <span
              class="inline-flex items-center justify-center mb-2 rounded-full size-10 bg-n-teal-3 text-n-teal-11"
            >
              <span class="i-lucide-check-check size-5" />
            </span>
            <p class="text-sm font-medium text-n-slate-12">
              {{ t('RAMON.COMMAND.QUEUE.EMPTY_TITLE') }}
            </p>
            <p class="mt-0.5 text-xs text-n-slate-10">
              {{ t('RAMON.COMMAND.QUEUE.EMPTY_BODY') }}
            </p>
          </div>

          <!-- Próximos da fila -->
          <div
            v-if="nextItems.length"
            data-testid="queue-next"
            class="flex flex-col gap-1.5"
          >
            <button
              v-for="(item, index) in nextItems"
              :key="item.leadId"
              type="button"
              data-testid="queue-next-item"
              class="flex items-center w-full gap-3 px-3.5 py-2.5 text-left rounded-[10px] border border-n-weak bg-n-solid-2 hover:bg-n-alpha-2"
              @click="jumpTo(index)"
            >
              <span
                class="flex-none rounded-full size-1.5"
                :class="severityDotClass(item)"
              />
              <span class="text-[13.5px] font-medium truncate text-n-slate-12">
                {{ item.leadName }}
              </span>
              <span class="text-[11.5px] truncate text-n-slate-10">
                {{ rowMotive(item) }}
              </span>
              <span
                class="flex-none ml-auto text-xs tabular-nums"
                :class="
                  item.benefitMonthlyValue ? 'text-n-iris-11' : 'text-n-slate-9'
                "
              >
                {{ itemValue(item) }}
              </span>
            </button>
          </div>
        </div>

        <!-- Coluna direita: agenda, conversão, time -->
        <div class="flex flex-col gap-3.5 min-w-0">
          <h2
            class="text-xs font-semibold tracking-[.12em] uppercase text-n-slate-10"
          >
            {{ t('RAMON.COMMAND.AGENDA.TITLE') }}
          </h2>
          <AgendaToday
            :items="agendaToday"
            @select="openLead"
            @view-week="openAgenda"
          />

          <h2
            class="text-xs font-semibold tracking-[.12em] uppercase text-n-slate-10"
          >
            {{ t('RAMON.COMMAND.FUNNEL.TITLE') }}
          </h2>
          <FunnelConversion
            :stages="funnel"
            :conversion="conversion"
            @stage-select="openStage"
          />

          <h2
            class="text-xs font-semibold tracking-[.12em] uppercase text-n-slate-10"
          >
            {{ t('RAMON.COMMAND.TEAM.TITLE') }}
          </h2>
          <TeamWeek :team="teamWeek" :nps="nps" />
        </div>
      </div>

      <!-- Perdas por tese (gestão) -->
      <LossesByThesis
        v-if="isAdmin && losses && losses.theses && losses.theses.length"
        :losses="losses"
      />

      <!-- Histórico compacto -->
      <section v-if="history.length">
        <h2
          class="mb-2.5 text-xs font-semibold tracking-[.12em] uppercase text-n-slate-10"
        >
          {{ t('RAMON.COMMAND.HISTORY.TITLE') }}
        </h2>
        <div class="p-4 rounded-[14px] border border-n-weak bg-n-solid-2">
          <Sparkline
            v-if="historyPoints.length > 1"
            :points="historyPoints"
            :width="560"
            :height="48"
          />
          <p
            v-if="historyLatest"
            data-testid="history-latest"
            class="mt-2 text-[11px] text-n-slate-10"
          >
            {{
              t('RAMON.COMMAND.HISTORY.LATEST', {
                leads: historyLatest.leads_count,
                value: brlCompact(historyLatest.value_sum),
              })
            }}
          </p>
        </div>
      </section>
    </div>
  </div>
</template>
