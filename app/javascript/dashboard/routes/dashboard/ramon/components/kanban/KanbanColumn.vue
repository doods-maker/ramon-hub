<script setup>
import { ref, watch } from 'vue';
import Draggable from 'vuedraggable';
import LeadCard from './LeadCard.vue';
import StageHeaderMenu from './StageHeaderMenu.vue';

const props = defineProps({
  stage: { type: Object, required: true },
  leads: { type: Array, default: () => [] },
});
const emit = defineEmits([
  'move',
  'open-conversation',
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
</script>

<template>
  <div
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
        <span class="text-xs text-n-slate-9">{{ localLeads.length }}</span>
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
          @open-conversation="id => emit('open-conversation', id)"
          @open-lead="lead => emit('openLead', lead)"
        />
      </template>
    </Draggable>
  </div>
</template>
