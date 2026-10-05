<script setup>
import { computed, onMounted, ref } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useStore, useStoreGetters } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useAlert } from 'dashboard/composables';
import { useKeyboardEvents } from 'dashboard/composables/useKeyboardEvents';
import RamonEsteiraAPI from 'dashboard/api/ramonEsteira';
import RamonCopilotAPI from 'dashboard/api/ramonCopilot';
import { brlCompact } from '../helpers/currency';
import { reasonLabel, severityDotClass, tomMotivo } from '../helpers/esteira';
import AgendaToday from '../components/command/AgendaToday.vue';
import NightCopilot from '../components/command/NightCopilot.vue';
import FunnelConversion from '../components/command/FunnelConversion.vue';
import TeamWeek from '../components/command/TeamWeek.vue';
import LossesByThesis from '../components/command/LossesByThesis.vue';
import Sparkline from '../components/command/Sparkline.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import {
  CARTAO,
  CARTAO_STATUS,
  CHIP,
  FILETE,
  LINHA,
  TITULO,
  TOM,
} from '../helpers/ui';

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
    class: 'text-n-blue-11',
  },
]);

const slaAvgLabel = computed(() => {
  const minutes = sla.value?.avg_first_response_minutes;
  return minutes == null
    ? t('RAMON.COMMAND.SLA.AVG_EMPTY')
    : t('RAMON.COMMAND.SLA.AVG', { minutes });
});

// ---- Sua fila agora = a fila da Esteira ----------------------------------
// Mesma fonte e mesma ordem da Esteira (urgência x dinheiro): o hero é o 1º
// item, a lista são os 5 seguintes. Espaço gira (pula), Feito remove.
const queue = ref([]);
const isQueueLoading = ref(true);
const queueError = ref(false);

const fetchQueue = async () => {
  isQueueLoading.value = true;
  queueError.value = false;
  try {
    const { data: esteira } = await RamonEsteiraAPI.get();
    queue.value = esteira.items || [];
  } catch (e) {
    // Erro de API não pode virar "fila zerada" comemorativa.
    queueError.value = true;
  } finally {
    isQueueLoading.value = false;
  }
};

const reload = () => {
  store.dispatch('ramonDashboard/fetch');
  fetchQueue();
};
onMounted(reload);

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
  if (item.conversation_id) {
    router.push(accountScopedRoute('ramon_funil'));
    store.dispatch('leads/toggleDock', item.conversation_id);
  } else {
    openLead(item.lead_id);
  }
};

// Rascunho da IA: gera a resposta, deixa no campo de resposta da conversa
// (rascunho do ReplyBox, lido ao montar) e abre o dock. Nada é enviado.
const isDrafting = ref(false);
const aiDraft = async () => {
  const item = current.value;
  if (!item?.conversation_id || isDrafting.value) return;
  isDrafting.value = true;
  try {
    const { data: draft } = await RamonCopilotAPI.generate(
      item.conversation_id,
      'draft'
    );
    await store.dispatch('draftMessages/set', {
      key: `draft-${item.conversation_id}-REPLY`,
      message: draft.content,
    });
    openConversation(item);
  } catch (e) {
    useAlert(t('RAMON.COMMAND.QUEUE.AI_DRAFT_ERROR'));
  } finally {
    isDrafting.value = false;
  }
};

// Feito: o mesmo "Feito" da Esteira (conta na meta do dia e tira o lead da
// fila de hoje); o refetch do painel atualiza a meta.
const isActing = ref(false);
const markDone = async () => {
  const item = current.value;
  if (!item || isActing.value) return;
  isActing.value = true;
  try {
    await RamonEsteiraAPI.done(item.lead_id);
    queue.value.shift();
    useAlert(t('RAMON.ESTEIRA.DONE_TOAST'));
    store.dispatch('ramonDashboard/fetch');
  } catch (e) {
    useAlert(t('RAMON.ESTEIRA.ACTION_ERROR'));
  } finally {
    isActing.value = false;
  }
};

// Atalhos reais da fila (mudos com campo focado — o composable cuida disso;
// a página não tem modais próprios).
const canAct = () =>
  !isLoading.value &&
  !hasError.value &&
  !isQueueLoading.value &&
  !queueError.value &&
  !!current.value;
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
        <p :class="TITULO">{{ dateLine }}</p>
        <h1
          class="mt-1 text-[28px] font-semibold leading-tight text-n-slate-12"
        >
          {{ t(greetingKey, { name: firstName }) }}
        </h1>
      </div>
      <div class="flex flex-wrap items-center gap-4">
        <div data-testid="daily-goal" class="text-right">
          <p :class="TITULO">{{ t('RAMON.COMMAND.GOAL_LABEL') }}</p>
          <div class="flex items-center gap-2 mt-1.5">
            <span
              class="block w-40 h-1.5 overflow-hidden rounded-full bg-n-alpha-2"
            >
              <span
                class="block h-full rounded-full bg-n-blue-9 transition-all duration-200"
                :style="{ width: `${goalPct}%` }"
              />
            </span>
            <span
              class="font-mono text-[13px] font-medium tabular-nums text-n-slate-12"
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
        <Button
          data-testid="reload"
          :title="t('RAMON.COMMAND.RELOAD')"
          icon="i-lucide-refresh-cw"
          sm
          ghost
          slate
          :disabled="isFetching"
          @click="reload"
        />
        <Button
          data-testid="start-day"
          icon="i-lucide-play"
          :label="t('RAMON.COMMAND.START_DAY')"
          @click="startDay"
        />
      </div>
    </header>

    <!-- Enquanto você dormia (copiloto noturno) — some quando 0 pendentes -->
    <NightCopilot />

    <div v-if="isLoading" class="flex flex-col gap-5 animate-pulse">
      <div class="grid grid-cols-2 sm:grid-cols-3 xl:grid-cols-6 gap-2.5">
        <div v-for="n in 6" :key="n" class="h-16 rounded-xl bg-n-alpha-2" />
      </div>
      <div class="grid grid-cols-1 lg:grid-cols-[1.5fr_1fr] gap-5">
        <div class="h-64 rounded-xl bg-n-alpha-2" />
        <div class="flex flex-col gap-3">
          <div v-for="n in 2" :key="n" class="h-32 rounded-xl bg-n-alpha-2" />
        </div>
      </div>
    </div>

    <!-- Erro de carga: mostra retry em vez de fingir "tudo em dia" -->
    <div v-else-if="hasError" data-testid="command-error" class="text-sm">
      <p class="text-n-ruby-11">{{ t('RAMON.COMMAND.LOAD_ERROR') }}</p>
      <Button
        data-testid="command-retry"
        link
        xs
        class="mt-2"
        :label="t('RAMON.LEAD_PANEL.RETRY')"
        @click="reload"
      />
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
            :class="CARTAO"
          >
            <p
              class="font-mono text-xl font-medium tabular-nums"
              :class="kpi.class"
            >
              {{ kpi.value }}
            </p>
            <p class="mt-0.5 text-[11px] text-n-slate-10">{{ kpi.label }}</p>
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
        <!-- Sua fila agora (= fila da Esteira) -->
        <div class="flex flex-col gap-2.5 min-w-0">
          <div class="flex items-baseline justify-between">
            <h2 :class="TITULO">{{ t('RAMON.COMMAND.QUEUE.TITLE') }}</h2>
            <span class="text-[11px] text-n-slate-10">
              {{ t('RAMON.COMMAND.QUEUE.SORTED_BY') }}
            </span>
          </div>

          <div
            v-if="isQueueLoading"
            class="h-40 rounded-xl bg-n-alpha-2 animate-pulse"
          />

          <!-- Erro de carga: distinto da fila zerada -->
          <div
            v-else-if="queueError"
            data-testid="queue-error"
            :class="CARTAO"
            class="text-sm"
          >
            <p class="text-n-ruby-11">{{ t('RAMON.ESTEIRA.LOAD_ERROR') }}</p>
            <Button
              data-testid="queue-retry"
              link
              xs
              class="mt-2"
              :label="t('RAMON.LEAD_PANEL.RETRY')"
              @click="fetchQueue"
            />
          </div>

          <div
            v-else-if="current"
            data-testid="queue-hero"
            :class="[CARTAO_STATUS, FILETE[tomMotivo(current.reasons[0]?.key)]]"
            class="!p-5"
          >
            <div class="flex items-start justify-between gap-3">
              <div class="min-w-0">
                <div class="flex flex-wrap items-center gap-2.5">
                  <p
                    class="text-2xl font-semibold leading-tight text-n-slate-12"
                  >
                    {{ current.name }}
                  </p>
                  <span v-if="current.stage_name" :class="[CHIP, TOM.slate]">
                    {{ current.stage_name }}
                  </span>
                </div>
                <div
                  data-testid="queue-hero-chips"
                  class="flex flex-wrap gap-1.5 mt-2"
                >
                  <span
                    v-for="reason in current.reasons"
                    :key="reason.key"
                    :class="[CHIP, TOM[tomMotivo(reason.key)]]"
                  >
                    {{ reasonLabel(t, reason) }}
                  </span>
                </div>
              </div>
              <span
                v-if="current.value"
                data-testid="queue-hero-value"
                class="flex-none font-mono text-[15px] font-medium tabular-nums text-n-blue-11"
              >
                {{ money(current.value) }}
              </span>
            </div>
            <div
              class="flex flex-wrap items-center gap-2 mt-4 pt-3.5 border-t border-n-weak"
            >
              <Button
                data-testid="queue-open-conversation"
                sm
                icon="i-lucide-message-square"
                :label="t('RAMON.COMMAND.QUEUE.OPEN_CONVERSATION')"
                @click="openConversation(current)"
              />
              <Button
                v-if="current.conversation_id"
                data-testid="queue-ai-draft"
                sm
                faded
                slate
                icon="i-lucide-sparkles"
                :label="t('RAMON.COMMAND.QUEUE.AI_DRAFT')"
                :is-loading="isDrafting"
                :disabled="isDrafting"
                @click="aiDraft"
              />
              <Button
                data-testid="queue-done"
                sm
                faded
                slate
                :label="t('RAMON.COMMAND.QUEUE.DONE')"
                :disabled="isActing"
                @click="markDone"
              />
              <span class="ml-auto text-[11px] text-n-slate-10">
                {{ t('RAMON.COMMAND.QUEUE.HINT') }}
              </span>
            </div>
          </div>

          <!-- Fila zerada -->
          <div
            v-else
            data-testid="queue-empty"
            :class="CARTAO"
            class="py-8 text-center"
          >
            <span
              class="inline-flex items-center justify-center mb-2 rounded-full size-10"
              :class="TOM.teal"
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
            v-if="!isQueueLoading && !queueError && nextItems.length"
            data-testid="queue-next"
            :class="CARTAO"
            class="flex flex-col !p-1.5"
          >
            <button
              v-for="(item, index) in nextItems"
              :key="item.lead_id"
              type="button"
              data-testid="queue-next-item"
              :class="LINHA"
              class="flex items-center gap-3 !px-2.5 !py-2"
              @click="jumpTo(index)"
            >
              <span
                class="flex-none rounded-full size-1.5"
                :class="severityDotClass(item)"
              />
              <span class="text-[13.5px] font-medium truncate text-n-slate-12">
                {{ item.name }}
              </span>
              <span class="text-[11.5px] truncate text-n-slate-10">
                {{ reasonLabel(t, item.reasons[0]) }}
              </span>
              <span
                class="flex-none ml-auto font-mono text-xs tabular-nums"
                :class="item.value ? 'text-n-blue-11' : 'text-n-slate-10'"
              >
                {{ item.value ? brlCompact(item.value) : '—' }}
              </span>
            </button>
          </div>
        </div>

        <!-- Coluna direita: agenda, conversão, time -->
        <div class="flex flex-col gap-2.5 min-w-0">
          <h2 :class="TITULO">{{ t('RAMON.COMMAND.AGENDA.TITLE') }}</h2>
          <AgendaToday
            :items="agendaToday"
            @select="openLead"
            @view-week="openAgenda"
          />

          <h2 :class="TITULO" class="mt-2.5">
            {{ t('RAMON.COMMAND.FUNNEL.TITLE') }}
          </h2>
          <FunnelConversion
            :stages="funnel"
            :conversion="conversion"
            @stage-select="openStage"
          />

          <h2 :class="TITULO" class="mt-2.5">
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
        <h2 :class="TITULO" class="mb-2.5">
          {{ t('RAMON.COMMAND.HISTORY.TITLE') }}
        </h2>
        <div :class="CARTAO">
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
