<script setup>
import Draggable from 'vuedraggable';
import LeadCard from './LeadCard.vue';

defineProps({
  stage: { type: Object, required: true },
  leads: { type: Array, default: () => [] },
  benefitTypes: { type: Array, default: () => [] },
  priorities: { type: Array, default: () => [] },
});
const emit = defineEmits(['move', 'open-conversation']);

const onChange = stageId => evt => {
  const added = evt.added || evt.moved;
  if (!added) return;
  emit('move', { id: added.element.id, leadStageId: stageId, newIndex: added.newIndex });
};
</script>

<template>
  <div class="flex flex-col w-72 flex-shrink-0 rounded-xl bg-[#17120d] border border-n-weak">
    <div class="flex items-center justify-between px-3 py-2">
      <span class="text-sm text-n-slate-12">{{ stage.name }}</span>
      <span class="text-xs text-n-slate-9">{{ leads.length }}</span>
    </div>
    <Draggable
      :model-value="leads"
      group="leads"
      item-key="id"
      class="flex-1 px-2 pb-2 min-h-[120px]"
      @change="onChange(stage.id)"
    >
      <template #item="{ element }">
        <LeadCard
          :lead="element"
          :benefit-types="benefitTypes"
          :priorities="priorities"
          @open-conversation="id => emit('open-conversation', id)"
        />
      </template>
    </Draggable>
  </div>
</template>
