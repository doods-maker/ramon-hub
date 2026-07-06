<script setup>
import { computed, onMounted, ref } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useStore, useStoreGetters } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { prescriptionInfo } from '../helpers/prescription';
import StatBlock from '../components/command/StatBlock.vue';
import LeadList from '../components/command/LeadList.vue';
import FollowUpQueue from '../components/command/FollowUpQueue.vue';
import Sparkline from '../components/command/Sparkline.vue';

const { t } = useI18n();
const store = useStore();
const getters = useStoreGetters();
const router = useRouter();
const { accountScopedRoute } = useAccount();

const data = computed(() => getters['ramonDashboard/getData'].value);
const uiFlags = computed(() => getters['ramonDashboard/getUIFlags'].value);
const isFetching = computed(() => uiFlags.value.isFetching);
const isLoading = computed(() => isFetching.value && !data.value);

const reload = () => store.dispatch('ramonDashboard/fetch');
onMounted(reload);

const brl = value =>
  new Intl.NumberFormat('pt-BR', {
    style: 'currency',
    currency: 'BRL',
    notation: 'compact',
    maximumFractionDigits: 1,
  }).format(Number(value) || 0);

const today = computed(() => data.value?.today || {});
const funnel = computed(() => data.value?.funnel || []);
const week = computed(() => data.value?.week || {});
const history = computed(() => data.value?.history || []);
const historyPoints = computed(() =>
  history.value.map(h => Number(h.value_sum) || 0)
);

const section = key => today.value[key] || { count: 0, items: [] };

// Fila de retomada (esteira): união client-side de tarefas vencidas + parados,
// deduplicada por lead. A tarefa vence o desempate (entra primeiro e mantém
// título/prazo); o item "parado" enriquece etapa/telefone/conversa quando o
// mesmo lead aparece nos dois blocos. Shape interno unificado.
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

  // Dinheiro prescrevendo desc; sort é estável (V8), empates preservam a
  // ordem atual (tasks vencidas antes de stalled).
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

const isQueueOpen = ref(false);
const openQueue = () => {
  isQueueOpen.value = true;
};

const todayBlocks = computed(() => [
  {
    key: 'tasks_overdue',
    type: 'task',
    danger: true,
    label: t('RAMON.COMMAND.TODAY.TASKS_OVERDUE'),
    empty: t('RAMON.COMMAND.TODAY.EMPTY_TASKS_OVERDUE'),
  },
  {
    key: 'tasks_today',
    type: 'task',
    danger: false,
    label: t('RAMON.COMMAND.TODAY.TASKS_TODAY'),
    empty: t('RAMON.COMMAND.TODAY.EMPTY_TASKS_TODAY'),
  },
  {
    key: 'stalled',
    type: 'lead',
    danger: false,
    label: t('RAMON.COMMAND.TODAY.STALLED'),
    empty: t('RAMON.COMMAND.TODAY.EMPTY_STALLED'),
  },
  {
    key: 'no_next_action',
    type: 'lead',
    danger: false,
    label: t('RAMON.COMMAND.TODAY.NO_NEXT_ACTION'),
    empty: t('RAMON.COMMAND.TODAY.EMPTY_NO_NEXT_ACTION'),
  },
  {
    key: 'new_from_lp',
    type: 'lead',
    danger: false,
    label: t('RAMON.COMMAND.TODAY.NEW_FROM_LP'),
    empty: t('RAMON.COMMAND.TODAY.EMPTY_NEW_FROM_LP'),
  },
]);

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
</script>

<template>
  <div class="flex flex-col w-full h-full overflow-auto bg-n-background p-8">
    <header class="flex items-center justify-between mb-8">
      <div>
        <p class="text-xs tracking-[0.2em] uppercase text-n-slate-11">
          {{ t('RAMON.COMMAND.EYEBROW') }}
        </p>
        <h1 class="font-cormorant text-4xl font-semibold text-n-slate-12">
          {{ t('RAMON.COMMAND.TITLE') }}
        </h1>
      </div>
      <button
        type="button"
        data-testid="reload"
        class="flex items-center h-8 gap-2 px-3 text-sm rounded-lg text-n-slate-11 border border-n-weak hover:bg-n-alpha-2 hover:text-n-slate-12"
        :disabled="isFetching"
        @click="reload"
      >
        <span class="i-lucide-refresh-cw size-4" />
        {{ t('RAMON.COMMAND.RELOAD') }}
      </button>
    </header>

    <div v-if="isLoading" class="flex flex-col gap-8 animate-pulse">
      <div class="grid grid-cols-2 gap-4 md:grid-cols-5">
        <div
          v-for="n in 5"
          :key="n"
          class="h-[120px] rounded-xl bg-n-solid-2"
        />
      </div>
      <div class="h-24 rounded-xl bg-n-solid-2" />
      <div class="h-24 rounded-xl bg-n-solid-2" />
    </div>

    <div v-else class="flex flex-col gap-10">
      <!-- Bloco Hoje -->
      <section>
        <div class="flex items-center justify-between mb-3">
          <h2 class="text-sm tracking-widest uppercase text-n-slate-9">
            {{ t('RAMON.COMMAND.TODAY.TITLE') }}
          </h2>
          <button
            v-if="followUpQueue.length"
            type="button"
            data-testid="run-follow-ups"
            class="inline-flex items-center h-8 gap-2 px-3 text-sm rounded-lg bg-n-iris-9 text-white hover:bg-n-iris-10"
            @click="openQueue"
          >
            <span class="i-lucide-play size-4" />
            {{ t('RAMON.COMMAND.QUEUE.RUN', { count: followUpQueue.length }) }}
          </button>
        </div>
        <div class="grid grid-cols-2 gap-4 md:grid-cols-5">
          <StatBlock
            v-for="block in todayBlocks"
            :key="block.key"
            :label="block.label"
            :value="section(block.key).count"
            :danger="block.danger && section(block.key).count > 0"
          >
            <LeadList
              v-if="section(block.key).count > 0"
              :items="section(block.key).items"
              :type="block.type"
              @select="openLead"
            />
            <p v-else class="px-1 text-xs text-n-slate-10">
              {{ block.empty }}
            </p>
          </StatBlock>
        </div>
      </section>

      <!-- Bloco Funil -->
      <section>
        <h2 class="mb-3 text-sm tracking-widest uppercase text-n-slate-9">
          {{ t('RAMON.COMMAND.FUNNEL.TITLE') }}
        </h2>
        <div v-if="funnel.length" class="flex flex-wrap gap-3">
          <button
            v-for="stage in funnel"
            :key="stage.stage_id"
            type="button"
            class="flex flex-col items-start px-4 py-3 border rounded-xl border-n-weak bg-n-solid-2 hover:bg-n-alpha-2 min-w-[140px]"
            @click="openStage(stage.stage_id)"
          >
            <span class="flex items-center gap-2">
              <span
                class="inline-block rounded-full size-2"
                :style="{ backgroundColor: stage.color }"
              />
              <span class="text-xs uppercase tracking-wide text-n-slate-11">
                {{ stage.name }}
              </span>
            </span>
            <span class="mt-1 text-2xl font-cormorant text-n-slate-12">
              {{ stage.count }}
            </span>
            <span class="text-xs text-n-slate-10">
              {{ brl(stage.weighted_value) }}
            </span>
          </button>
        </div>
        <p v-else class="text-sm text-n-slate-10">
          {{ t('RAMON.COMMAND.FUNNEL.EMPTY') }}
        </p>
      </section>

      <!-- Bloco Semana -->
      <section>
        <h2 class="mb-3 text-sm tracking-widest uppercase text-n-slate-9">
          {{ t('RAMON.COMMAND.WEEK.TITLE') }}
        </h2>
        <div class="grid grid-cols-1 gap-4 md:grid-cols-3">
          <div
            class="grid grid-cols-3 gap-3 p-4 border rounded-xl border-n-weak bg-n-solid-2 md:col-span-1"
          >
            <div class="flex flex-col">
              <span class="text-3xl font-cormorant text-n-slate-12">
                {{ week.created || 0 }}
              </span>
              <span class="text-xs uppercase text-n-slate-11">
                {{ t('RAMON.COMMAND.WEEK.CREATED') }}
              </span>
            </div>
            <div class="flex flex-col">
              <span class="text-3xl font-cormorant text-n-teal-11">
                {{ week.won || 0 }}
              </span>
              <span class="text-xs uppercase text-n-slate-11">
                {{ t('RAMON.COMMAND.WEEK.WON') }}
              </span>
            </div>
            <div class="flex flex-col">
              <span class="text-3xl font-cormorant text-n-ruby-11">
                {{ week.lost || 0 }}
              </span>
              <span class="text-xs uppercase text-n-slate-11">
                {{ t('RAMON.COMMAND.WEEK.LOST') }}
              </span>
            </div>
          </div>

          <div class="p-4 border rounded-xl border-n-weak bg-n-solid-2">
            <p class="mb-2 text-xs uppercase tracking-wide text-n-slate-11">
              {{ t('RAMON.COMMAND.WEEK.BY_SOURCE') }}
            </p>
            <ul
              v-if="week.created_by_source && week.created_by_source.length"
              class="flex flex-col gap-1"
            >
              <li
                v-for="row in week.created_by_source"
                :key="row.source"
                class="flex items-center justify-between text-sm text-n-slate-12"
              >
                <span class="truncate">{{ row.source }}</span>
                <span class="text-n-slate-10">{{ row.count }}</span>
              </li>
            </ul>
            <p v-else class="text-xs text-n-slate-10">
              {{ t('RAMON.COMMAND.WEEK.EMPTY_SOURCE') }}
            </p>
          </div>

          <div class="p-4 border rounded-xl border-n-weak bg-n-solid-2">
            <p class="mb-2 text-xs uppercase tracking-wide text-n-slate-11">
              {{ t('RAMON.COMMAND.WEEK.LOST_REASONS') }}
            </p>
            <ul
              v-if="week.lost_reasons_30d && week.lost_reasons_30d.length"
              class="flex flex-col gap-1"
            >
              <li
                v-for="row in week.lost_reasons_30d"
                :key="row.reason"
                class="flex items-center justify-between text-sm text-n-slate-12"
              >
                <span class="truncate">{{ row.reason }}</span>
                <span class="text-n-slate-10">{{ row.count }}</span>
              </li>
            </ul>
            <p v-else class="text-xs text-n-slate-10">
              {{ t('RAMON.COMMAND.WEEK.EMPTY_LOST_REASONS') }}
            </p>
          </div>
        </div>
      </section>

      <!-- Bloco Histórico (Organismo, Onda 0) -->
      <section>
        <h2 class="mb-3 text-sm tracking-widest uppercase text-n-slate-9">
          {{ t('RAMON.COMMAND.HISTORY.TITLE') }}
        </h2>
        <div
          v-if="history.length"
          class="p-4 border rounded-xl border-n-weak bg-n-solid-2"
        >
          <Sparkline :points="historyPoints" :width="320" :height="48" />
          <table class="w-full mt-4 text-sm">
            <thead>
              <tr class="text-xs uppercase text-n-slate-10">
                <th class="py-1 font-normal text-left">
                  {{ t('RAMON.COMMAND.HISTORY.COL_DATE') }}
                </th>
                <th class="py-1 font-normal text-right">
                  {{ t('RAMON.COMMAND.HISTORY.COL_LEADS') }}
                </th>
                <th class="py-1 font-normal text-right">
                  {{ t('RAMON.COMMAND.HISTORY.COL_VALUE') }}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="row in history"
                :key="row.date"
                class="border-t border-n-weak text-n-slate-12"
              >
                <td class="py-1 text-left">{{ row.date }}</td>
                <td class="py-1 text-right">{{ row.leads_count }}</td>
                <td class="py-1 text-right">{{ brl(row.value_sum) }}</td>
              </tr>
            </tbody>
          </table>
        </div>
        <p v-else class="text-sm text-n-slate-10">
          {{ t('RAMON.COMMAND.HISTORY.EMPTY') }}
        </p>
      </section>
    </div>

    <FollowUpQueue
      v-if="isQueueOpen"
      :queue="followUpQueue"
      @close="isQueueOpen = false"
    />
  </div>
</template>
