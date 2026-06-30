<script setup>
import { ref, watch } from 'vue';
import Draggable from 'vuedraggable';
import LeadCard from './LeadCard.vue';

const props = defineProps({
  stage: { type: Object, required: true },
  leads: { type: Array, default: () => [] },
  benefitTypes: { type: Array, default: () => [] },
  priorities: { type: Array, default: () => [] },
});
const emit = defineEmits(['move', 'open-conversation']);

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
      <span class="text-sm text-n-slate-12">{{ stage.name }}</span>
      <span class="text-xs text-n-slate-9">{{ localLeads.length }}</span>
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
          :benefit-types="benefitTypes"
          :priorities="priorities"
          @open-conversation="id => emit('open-conversation', id)"
        />
      </template>
    </Draggable>
  </div>
</template>
