<script setup>
// Filtros ativos como chips removíveis + resumo do pipeline à direita
// (mock 1d): "SDR: Eduardo ✕ · Canal: WhatsApp ✕ … 32 leads · R$ 616 mil ·
// previsão R$ 187 mil". O painel completo de filtros continua atrás do botão.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStoreGetters } from 'dashboard/composables/store';
import { brlCompact } from '../../helpers/currency';

const props = defineProps({
  filters: { type: Object, required: true },
});
const emit = defineEmits(['update']);

const { t } = useI18n();
const getters = useStoreGetters();

const benefitTypes = computed(
  () => getters['leadConfig/getBenefitTypes']?.value ?? []
);
const priorities = computed(
  () => getters['leadConfig/getPriorities']?.value ?? []
);
const channels = computed(() => getters['leadConfig/getChannels']?.value ?? []);
const stages = computed(() => getters['leadConfig/getStages']?.value ?? []);
const agents = computed(() => getters['agents/getAgents']?.value ?? []);
const leads = computed(() => getters['leads/getLeads']?.value ?? []);

const nameOf = (list, id) =>
  list.find(item => String(item.id) === String(id))?.name || String(id);

const dateBr = iso => {
  const [year, month, day] = String(iso).split('-');
  return day && month ? `${day}/${month}` : iso;
};

// Cada filtro ativo vira { key, label, cleared } — cleared é o partial que o
// ✕ manda pro setFilters para zerar SÓ aquele filtro.
const chips = computed(() => {
  const f = props.filters || {};
  const list = [];
  const push = (key, label, cleared) => list.push({ key, label, cleared });
  if (f.q) push('q', `"${f.q}"`, { q: '' });
  if (f.benefitTypeId)
    push(
      'benefitTypeId',
      `${t('RAMON.FUNIL.FILTERS.BENEFIT')}: ${nameOf(benefitTypes.value, f.benefitTypeId)}`,
      { benefitTypeId: null }
    );
  if (f.leadPriorityId)
    push(
      'leadPriorityId',
      `${t('RAMON.FUNIL.FILTERS.PRIORITY')}: ${nameOf(priorities.value, f.leadPriorityId)}`,
      { leadPriorityId: null }
    );
  if (f.agentId)
    push(
      'agentId',
      `${t('RAMON.FUNIL.FILTERS.AGENT')}: ${nameOf(agents.value, f.agentId)}`,
      { agentId: null }
    );
  if (f.source)
    push('source', `${t('RAMON.FUNIL.FILTERS.SOURCE')}: ${f.source}`, {
      source: '',
    });
  if (f.channel) {
    const channel = channels.value.find(c => c.key === f.channel);
    push(
      'channel',
      `${t('RAMON.FUNIL.FILTERS.CHANNEL')}: ${channel?.label || f.channel}`,
      { channel: '' }
    );
  }
  if (f.leadStageId)
    push(
      'leadStageId',
      `${t('RAMON.FUNIL.FILTERS.STAGE')}: ${nameOf(stages.value, f.leadStageId)}`,
      { leadStageId: null }
    );
  if (f.createdAfter)
    push(
      'createdAfter',
      `${t('RAMON.FUNIL.FILTERS.CREATED_AFTER')} ${dateBr(f.createdAfter)}`,
      { createdAfter: null }
    );
  if (f.createdBefore)
    push(
      'createdBefore',
      `${t('RAMON.FUNIL.FILTERS.CREATED_BEFORE')} ${dateBr(f.createdBefore)}`,
      { createdBefore: null }
    );
  if (f.stalled)
    push('stalled', t('RAMON.FUNIL.FILTERS.STALLED'), { stalled: false });
  if (f.noOpenTask)
    push('noOpenTask', t('RAMON.FUNIL.FILTERS.NO_OPEN_TASK'), {
      noOpenTask: false,
    });
  return list;
});

// Resumo dos leads carregados (já filtrados no server): contagem, Σ valor e
// previsão ponderada Σ valor × probabilidade da etapa.
const summary = computed(() => {
  const stageById = new Map(stages.value.map(s => [s.id, s]));
  let total = 0;
  let forecast = 0;
  leads.value.forEach(lead => {
    const value = Number(lead.value) || 0;
    total += value;
    const probability =
      Number(stageById.get(lead.lead_stage_id)?.probability) || 0;
    forecast += value * (probability / 100);
  });
  return { count: leads.value.length, total, forecast };
});
</script>

<template>
  <div
    class="flex flex-wrap items-center gap-1.5 px-4 py-1.5"
    data-testid="filter-chips"
  >
    <span
      v-for="chip in chips"
      :key="chip.key"
      :data-testid="`filter-chip-${chip.key}`"
      class="inline-flex items-center gap-1 py-0.5 pl-2.5 pr-1 text-xs rounded-full bg-n-alpha-2 text-n-iris-11 border border-n-weak"
    >
      {{ chip.label }}
      <button
        :data-testid="`filter-chip-remove-${chip.key}`"
        class="flex items-center p-0.5 rounded-full text-n-slate-10 hover:text-n-slate-12"
        :aria-label="$t('RAMON.FUNIL.CHIPS.REMOVE')"
        :title="$t('RAMON.FUNIL.CHIPS.REMOVE')"
        @click="emit('update', chip.cleared)"
      >
        <span class="i-lucide-x size-3" />
      </button>
    </span>
    <span
      data-testid="pipeline-summary"
      class="ms-auto text-xs whitespace-nowrap text-n-slate-10"
    >
      {{
        $t('RAMON.FUNIL.CHIPS.SUMMARY', {
          count: summary.count,
          total: brlCompact(summary.total),
        })
      }}
      <span class="text-n-iris-11">
        {{
          $t('RAMON.FUNIL.CHIPS.FORECAST', {
            forecast: brlCompact(summary.forecast),
          })
        }}
      </span>
    </span>
  </div>
</template>
