<script setup>
// Mini-coluna de uma raia (mock 2b): os cards de UM grupo em UMA etapa.
// Mesmo truque do KanbanColumn: cópia local gravável p/ o vuedraggable não
// "devolver" o card no drop. group único por raia = drag só dentro da raia.
import { ref, watch } from 'vue';
import Draggable from 'vuedraggable';
import LeadCard from './LeadCard.vue';

const props = defineProps({
  leads: { type: Array, default: () => [] },
  stageId: { type: Number, required: true },
  laneKey: { type: [String, Number], required: true },
  selectedLeadIds: { type: Array, default: () => [] },
});
const emit = defineEmits([
  'move',
  'openConversation',
  'openLead',
  'openDossie',
  'toggleSelect',
]);

const localLeads = ref([...props.leads]);
watch(
  () => props.leads,
  newLeads => {
    localLeads.value = [...newLeads];
  }
);

const onChange = evt => {
  // ponytail: só `added` (troca de etapa) grava — `moved` (reorder dentro da
  // célula) não persiste posição no server, então não fingimos um save.
  const change = evt.added;
  if (!change) return;
  emit('move', {
    id: change.element.id,
    leadStageId: props.stageId,
    newIndex: change.newIndex,
  });
};
</script>

<template>
  <Draggable
    v-model="localLeads"
    :group="`lane-${laneKey}`"
    item-key="id"
    ghost-class="ramon-drag-ghost"
    class="flex flex-col min-h-[56px]"
    data-testid="swimlane-cell"
    @change="onChange"
  >
    <template #item="{ element }">
      <LeadCard
        :lead="element"
        selectable
        :selected="selectedLeadIds.includes(element.id)"
        @open-conversation="id => emit('openConversation', id)"
        @open-lead="lead => emit('openLead', lead)"
        @open-dossie="lead => emit('openDossie', lead)"
        @toggle-select="lead => emit('toggleSelect', lead)"
      />
    </template>
  </Draggable>
</template>
