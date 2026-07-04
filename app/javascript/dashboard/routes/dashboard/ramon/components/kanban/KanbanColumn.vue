<script setup>
import { ref, watch, computed } from 'vue';
import Draggable from 'vuedraggable';
import LeadCard from './LeadCard.vue';
import StageHeaderMenu from './StageHeaderMenu.vue';

const props = defineProps({
  stage: { type: Object, required: true },
  leads: { type: Array, default: () => [] },
});
const emit = defineEmits([
  'move',
  'openConversation',
  'openLead',
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
const brl = value =>
  new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(
    value
  );
const brlCompact = value =>
  new Intl.NumberFormat('pt-BR', {
    style: 'currency',
    currency: 'BRL',
    notation: 'compact',
    maximumFractionDigits: 1,
  }).format(value);

// Forecast ponderado = soma × probabilidade da etapa. Só faz sentido quando a
// etapa tem probabilidade > 0 (some p/ etapas de perda, que ficam em 0).
const stageProbability = computed(() => Number(props.stage.probability) || 0);
const showWeighted = computed(() => stageProbability.value > 0);
const weightedValue = computed(
  () => totalValue.value * (stageProbability.value / 100)
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
    class="flex flex-col items-center gap-2 w-10 flex-shrink-0 rounded-xl bg-[#17120d] border border-n-weak py-3 cursor-pointer"
    :title="$t('RAMON.KANBAN.COLUMN.EXPAND')"
    @click="toggleCollapsed"
  >
    <span
      class="rounded-full size-2.5 flex-shrink-0"
      :style="{ backgroundColor: stage.color || '#71717a' }"
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
    class="flex flex-col w-72 flex-shrink-0 rounded-xl bg-[#17120d] border border-n-weak"
  >
    <div class="flex items-center justify-between px-3 py-2">
      <span
        class="flex items-center gap-2 text-sm text-n-slate-12 stage-drag-handle cursor-grab"
      >
        <span
          class="rounded-full size-2.5"
          :style="{ backgroundColor: stage.color || '#71717a' }"
        />
        {{ stage.name }}
        <span
          v-if="stage.is_won"
          class="i-lucide-trophy size-3 text-n-amber-11"
        />
        <span
          v-if="stage.is_lost"
          class="i-lucide-x-circle size-3 text-n-ruby-11"
        />
      </span>
      <span class="flex items-center gap-2">
        <span class="flex flex-col items-end leading-tight">
          <span data-testid="stage-total" class="text-xs text-n-slate-9">
            {{ brl(totalValue) }}
          </span>
          <span
            v-if="showWeighted"
            data-testid="stage-weighted"
            class="text-[10px] text-n-slate-10"
          >
            {{
              $t('RAMON.KANBAN.COLUMN.WEIGHTED', {
                value: brlCompact(weightedValue),
              })
            }}
          </span>
        </span>
        <span data-testid="stage-count" class="text-xs text-n-slate-9">
          {{ localLeads.length }}
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
    <Draggable
      v-model="localLeads"
      group="leads"
      item-key="id"
      class="flex-1 px-2 pb-2 min-h-[120px]"
      @change="onChange"
    >
      <template #item="{ element }">
        <LeadCard
          :lead="element"
          @open-conversation="id => emit('openConversation', id)"
          @open-lead="lead => emit('openLead', lead)"
        />
      </template>
    </Draggable>
  </div>
</template>
