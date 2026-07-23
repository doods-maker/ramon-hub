<script setup>
// Raias por agrupamento (mock 2b): raia = grupo (tese/dono/canal/prioridade),
// coluna = etapa. Célula-resumo à esquerda (nome, "N · R$ X", alertas) e uma
// mini-coluna de cards por etapa; drag entre etapas fica DENTRO da raia.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStoreGetters } from 'dashboard/composables/store';
import { DEFAULT_STAGE_COLOR } from '../../helpers/stage';
import { brlCompact } from '../../helpers/currency';
import { prescriptionInfo } from '../../helpers/prescription';
import SwimlaneCell from './SwimlaneCell.vue';

const props = defineProps({
  stages: { type: Array, default: () => [] },
  leads: { type: Array, default: () => [] },
  groupBy: { type: String, default: 'thesis' },
  selectedLeadIds: { type: Array, default: () => [] },
});
const emit = defineEmits([
  'move',
  'openConversation',
  'openLead',
  'openDossie',
  'toggleSelect',
]);

const { t } = useI18n();
const getters = useStoreGetters();
const channels = computed(() => getters['leadConfig/getChannels']?.value ?? []);

// [chave, rótulo] do grupo de um lead, conforme o agrupador escolhido.
const groupOf = lead => {
  const none = t('RAMON.KANBAN.LANES.NO_GROUP');
  switch (props.groupBy) {
    case 'sdr':
      return [lead.sdr_id ?? 'none', lead.sdr_name || none];
    case 'channel': {
      const channel = channels.value.find(c => c.key === lead.channel);
      return [lead.channel || 'none', channel?.label || lead.channel || none];
    }
    case 'priority':
      return [lead.lead_priority_id ?? 'none', lead.lead_priority_name || none];
    default:
      return [lead.thesis_id ?? 'none', lead.thesis_name || none];
  }
};

const lanes = computed(() => {
  const byKey = new Map();
  props.leads.forEach(lead => {
    const [key, name] = groupOf(lead);
    if (!byKey.has(key)) byKey.set(key, { key, name, leads: [] });
    byKey.get(key).leads.push(lead);
  });
  const list = [...byKey.values()].map(lane => {
    const byStage = new Map();
    let total = 0;
    let stalledCount = 0;
    let prescribingMonthly = 0;
    lane.leads.forEach(lead => {
      total += Number(lead.value) || 0;
      if (lead.stalled) stalledCount += 1;
      const p = prescriptionInfo(lead);
      if (p?.lostInstallments > 0)
        prescribingMonthly += Number(lead.benefit_monthly_value) || 0;
      if (!byStage.has(lead.lead_stage_id)) byStage.set(lead.lead_stage_id, []);
      byStage.get(lead.lead_stage_id).push(lead);
    });
    byStage.forEach(stageLeads =>
      stageLeads.sort((a, b) => a.position - b.position)
    );
    return { ...lane, byStage, total, stalledCount, prescribingMonthly };
  });
  // Raias maiores primeiro; "Sem grupo" por último.
  return list.sort((a, b) => {
    if (a.key === 'none') return 1;
    if (b.key === 'none') return -1;
    return b.leads.length - a.leads.length;
  });
});

// Grid dinâmico: célula-resumo fixa + uma coluna por etapa (precedente do
// fork p/ valores dinâmicos: :style com a cor da etapa no KanbanColumn).
const gridStyle = computed(() => ({
  gridTemplateColumns: `170px repeat(${props.stages.length}, 240px)`,
}));
</script>

<template>
  <div class="flex-1 min-h-0 overflow-auto px-4 pb-4" data-testid="swimlanes">
    <div class="w-max min-w-full">
      <!-- header: nome de cada etapa com o dot da cor, alinhado ao grid -->
      <div class="grid gap-x-2.5 items-center pb-1" :style="gridStyle">
        <span />
        <span
          v-for="stage in stages"
          :key="stage.id"
          class="flex items-center gap-1.5 text-[11px] font-semibold text-n-slate-10"
        >
          <span
            class="rounded-full size-2 shrink-0"
            :style="{ backgroundColor: stage.color || DEFAULT_STAGE_COLOR }"
          />
          {{ stage.name }}
        </span>
      </div>
      <div class="flex flex-col gap-2.5">
        <div
          v-for="lane in lanes"
          :key="lane.key"
          data-testid="swimlane"
          class="grid gap-2.5 p-2.5 rounded-xl ramon-column border border-n-weak"
          :style="gridStyle"
        >
          <div class="flex flex-col gap-1 p-1 min-w-0">
            <span
              data-testid="swimlane-name"
              class="text-sm font-semibold truncate text-n-slate-12"
            >
              {{ lane.name }}
            </span>
            <span
              data-testid="swimlane-summary"
              class="text-[11px] tabular-nums text-n-slate-10"
            >
              {{ lane.leads.length }}
              <span v-if="lane.total">{{ `· ${brlCompact(lane.total)}` }}</span>
            </span>
            <span
              v-if="lane.prescribingMonthly > 0"
              data-testid="swimlane-alert-prescribing"
              class="text-[10.5px] text-n-ruby-11"
            >
              {{
                $t('RAMON.KANBAN.COLUMN.PRESCRIBING', {
                  value: brlCompact(lane.prescribingMonthly),
                })
              }}
            </span>
            <span
              v-else-if="lane.stalledCount > 0"
              data-testid="swimlane-alert-stalled"
              class="text-[10.5px] text-n-amber-11"
            >
              {{
                $t('RAMON.KANBAN.COLUMN.STALLED', { count: lane.stalledCount })
              }}
            </span>
          </div>
          <SwimlaneCell
            v-for="stage in stages"
            :key="stage.id"
            :leads="lane.byStage.get(stage.id) || []"
            :stage-id="stage.id"
            :lane-key="lane.key"
            :selected-lead-ids="selectedLeadIds"
            @move="payload => emit('move', payload)"
            @open-conversation="id => emit('openConversation', id)"
            @open-lead="lead => emit('openLead', lead)"
            @open-dossie="lead => emit('openDossie', lead)"
            @toggle-select="lead => emit('toggleSelect', lead)"
          />
        </div>
      </div>
    </div>
  </div>
</template>
