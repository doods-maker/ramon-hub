<script setup>
import { ref, watch, computed, onMounted, onUnmounted } from 'vue';
import { useI18n } from 'vue-i18n';
import Draggable from 'vuedraggable';
import { DEFAULT_STAGE_COLOR } from '../../helpers/stage';
import { brlCompact } from '../../helpers/currency';
import { prescriptionInfo } from '../../helpers/prescription';
import LeadCard from './LeadCard.vue';
import StageHeaderMenu from './StageHeaderMenu.vue';

const props = defineProps({
  stage: { type: Object, required: true },
  leads: { type: Array, default: () => [] },
  focusedLeadId: { type: Number, default: null },
  // Seleção em lote (repassada ao card; a store de seleção chega em outra fase).
  selectable: { type: Boolean, default: false },
  selectedLeadIds: { type: Array, default: () => [] },
  conversionRate: { type: Number, default: null },
});
const emit = defineEmits([
  'move',
  'openConversation',
  'openLead',
  'openDossie',
  'toggleSelect',
  'renameStage',
  'recolorStage',
  'setStageType',
  'removeStage',
]);

// vuedraggable precisa de um array GRAVÁVEL (v-model) para mover o card de fato.
// Ligar direto no getter (read-only via :model-value) fazia o card "voltar" ao
// soltar. Mantemos uma cópia local sincronizada com a fonte de verdade (store).
const localLeads = ref([...props.leads]);
watch(
  () => props.leads,
  newLeads => {
    localLeads.value = [...newLeads];
  }
);

// added = card chegou de outra coluna (persiste etapa nova); moved = reordenou
// dentro da própria coluna (persiste posição). removed = saiu p/ outra coluna:
// ignorado, pois a coluna de DESTINO já persiste via added.
const onChange = evt => {
  const change = evt.added || evt.moved;
  if (!change) return;
  emit('move', {
    id: change.element.id,
    leadStageId: props.stage.id,
    newIndex: change.newIndex,
  });
};

const totalValue = computed(() =>
  props.leads.reduce((sum, lead) => sum + (Number(lead.value) || 0), 0)
);

// Forecast ponderado = soma × probabilidade da etapa. Só faz sentido quando a
// etapa tem probabilidade > 0 (some p/ etapas de perda, que ficam em 0).
const stageProbability = computed(() => Number(props.stage.probability) || 0);
const showWeighted = computed(() => stageProbability.value > 0);
const weightedValue = computed(
  () => totalValue.value * (stageProbability.value / 100)
);

const { t } = useI18n();

// Alertas agregados do header — prioridade: prescrevendo (ruby) > fora do
// SLA (ruby) > parados (âmbar); mostramos até 2.
const stalledCount = computed(
  () => props.leads.filter(lead => lead.stalled).length
);
const prescribingMonthly = computed(() =>
  props.leads.reduce((sum, lead) => {
    const p = prescriptionInfo(lead);
    return p?.lostInstallments > 0
      ? sum + (Number(lead.benefit_monthly_value) || 0)
      : sum;
  }, 0)
);

// Relógio de 30s: o "fora do SLA" atravessa o due_at sem esperar re-fetch.
const now = ref(Date.now());
let slaTimer = null;
onMounted(() => {
  slaTimer = setInterval(() => {
    now.value = Date.now();
  }, 30000);
});
onUnmounted(() => clearInterval(slaTimer));

const slaBreachedCount = computed(
  () =>
    props.leads.filter(
      lead =>
        lead.sla?.due_at &&
        !lead.sla.replied_at &&
        new Date(lead.sla.due_at).getTime() < now.value
    ).length
);

const alerts = computed(() =>
  [
    prescribingMonthly.value > 0 && {
      key: 'prescribing',
      class: 'text-n-ruby-11',
      label: t('RAMON.KANBAN.COLUMN.PRESCRIBING', {
        value: brlCompact(prescribingMonthly.value),
      }),
    },
    slaBreachedCount.value > 0 && {
      key: 'sla',
      class: 'text-n-ruby-11',
      label: t('RAMON.KANBAN.SLA.COL_BREACHED', {
        count: slaBreachedCount.value,
      }),
    },
    stalledCount.value > 0 && {
      key: 'stalled',
      class: 'text-n-amber-11',
      label: t('RAMON.KANBAN.COLUMN.STALLED', { count: stalledCount.value }),
    },
  ]
    .filter(Boolean)
    .slice(0, 2)
);

// Persistência do colapso por etapa (mesmo padrão do FILTERS_KEY em leads.js).
const COLLAPSED_KEY = 'ramon_kanban_collapsed';
const readCollapsed = () => {
  try {
    return JSON.parse(localStorage.getItem(COLLAPSED_KEY) || '[]');
  } catch (e) {
    return [];
  }
};
const collapsed = ref(readCollapsed().includes(props.stage.id));
const toggleCollapsed = () => {
  collapsed.value = !collapsed.value;
  try {
    const ids = readCollapsed().filter(id => id !== props.stage.id);
    if (collapsed.value) ids.push(props.stage.id);
    localStorage.setItem(COLLAPSED_KEY, JSON.stringify(ids));
  } catch (e) {
    // localStorage indisponível: seguimos sem persistir
  }
};
</script>

<template>
  <!-- faixa colapsada: só nome vertical + contador; clique expande -->
  <button
    v-if="collapsed"
    data-testid="stage-expand"
    class="flex flex-col items-center gap-2 w-10 flex-shrink-0 rounded-xl ramon-column border border-n-weak pb-3 cursor-pointer overflow-hidden"
    :title="$t('RAMON.KANBAN.COLUMN.EXPAND')"
    @click="toggleCollapsed"
  >
    <!-- acento estrutural: a cor da etapa marca o topo da coluna -->
    <span
      class="h-0.5 w-full flex-shrink-0"
      :style="{ backgroundColor: stage.color || DEFAULT_STAGE_COLOR }"
    />
    <span
      class="rounded-full size-2.5 flex-shrink-0"
      :style="{ backgroundColor: stage.color || DEFAULT_STAGE_COLOR }"
    />
    <span data-testid="stage-count" class="text-xs text-n-slate-9">
      {{ localLeads.length }}
    </span>
    <span
      class="text-sm text-n-slate-12 [writing-mode:vertical-rl] whitespace-nowrap overflow-hidden"
    >
      {{ stage.name }}
    </span>
  </button>
  <div
    v-else
    class="flex flex-col w-72 max-h-full flex-shrink-0 rounded-xl ramon-column border border-n-weak overflow-hidden"
  >
    <!-- acento estrutural: a cor da etapa marca o topo da coluna -->
    <div
      class="h-0.5 flex-shrink-0"
      :style="{ backgroundColor: stage.color || DEFAULT_STAGE_COLOR }"
    />
    <div class="flex items-center gap-2 px-3 py-2">
      <span
        class="flex items-center gap-2 min-w-0 text-sm font-medium text-n-slate-12 stage-drag-handle cursor-grab"
      >
        <span
          class="rounded-full size-2.5 shrink-0"
          :style="{ backgroundColor: stage.color || DEFAULT_STAGE_COLOR }"
        />
        <span class="truncate">{{ stage.name }}</span>
        <span
          v-if="stage.is_won"
          class="i-lucide-trophy size-3 shrink-0 text-n-amber-11"
        />
        <span
          v-if="stage.is_lost"
          class="i-lucide-x-circle size-3 shrink-0 text-n-ruby-11"
        />
      </span>
      <!-- "N · R$ X mil · ~R$ Y ponderado ↳ Z%": cabeça da coluna (mock 1d) -->
      <span class="text-[11px] tabular-nums whitespace-nowrap text-n-slate-9">
        <span data-testid="stage-count">{{ localLeads.length }}</span>
        <span v-if="totalValue" data-testid="stage-total">
          {{ `· ${brlCompact(totalValue)}` }}
        </span>
        <span
          v-if="showWeighted"
          data-testid="stage-weighted"
          class="text-n-iris-11/80"
        >
          {{ `· ~${brlCompact(weightedValue)}` }}
        </span>
        <span
          v-if="conversionRate != null"
          data-testid="stage-conversion"
          :title="$t('RAMON.KANBAN.COLUMN.CONVERSION_TIP')"
          class="text-[10px] text-n-slate-10"
        >
          {{ $t('RAMON.KANBAN.COLUMN.CONVERSION', { rate: conversionRate }) }}
        </span>
      </span>
      <span class="flex items-center gap-2 ms-auto min-w-0">
        <span
          v-for="alert in alerts"
          :key="alert.key"
          :data-testid="`column-alert-${alert.key}`"
          class="text-[10.5px] truncate"
          :class="alert.class"
        >
          {{ alert.label }}
        </span>
        <button
          data-testid="stage-collapse-toggle"
          class="flex items-center text-n-slate-9 hover:text-n-slate-12"
          :title="$t('RAMON.KANBAN.COLUMN.COLLAPSE')"
          @click="toggleCollapsed"
        >
          <span class="i-lucide-chevrons-left-right size-3.5 rotate-90" />
        </button>
        <StageHeaderMenu
          :stage="stage"
          @rename="name => emit('renameStage', { id: stage.id, name })"
          @recolor="color => emit('recolorStage', { id: stage.id, color })"
          @set-type="type => emit('setStageType', { id: stage.id, type })"
          @remove="s => emit('removeStage', s)"
        />
      </span>
    </div>
    <p
      v-if="!localLeads.length"
      data-testid="column-empty"
      class="px-3 pt-3 text-xs text-center text-n-slate-9"
    >
      {{ $t('RAMON.KANBAN.COLUMN.EMPTY') }}
    </p>
    <Draggable
      v-model="localLeads"
      group="leads"
      item-key="id"
      ghost-class="ramon-drag-ghost"
      class="flex-1 px-2 pb-2 min-h-[120px] overflow-y-auto"
      @change="onChange"
    >
      <template #item="{ element }">
        <LeadCard
          :lead="element"
          :focused="element.id === focusedLeadId"
          :selectable="selectable"
          :selected="selectedLeadIds.includes(element.id)"
          @open-conversation="id => emit('openConversation', id)"
          @open-lead="lead => emit('openLead', lead)"
          @open-dossie="lead => emit('openDossie', lead)"
          @toggle-select="lead => emit('toggleSelect', lead)"
        />
      </template>
    </Draggable>
  </div>
</template>
