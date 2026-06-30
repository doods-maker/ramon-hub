<script setup>
import { computed, onMounted } from 'vue';
import { useStore, useStoreGetters } from 'dashboard/composables/store';
import KanbanColumn from './KanbanColumn.vue';

const emit = defineEmits(['new-lead', 'open-conversation', 'open-lead']);
const store = useStore();
const getters = useStoreGetters();

const stages = computed(() => getters['leadConfig/getStages'].value);
const leadsByStage = stageId => getters['leads/getLeadsByStage'].value(stageId);

const onMove = ({ id, leadStageId, newIndex }) => {
  store.dispatch('leads/move', { id, leadStageId, position: newIndex });
};

onMounted(() => {
  store.dispatch('leadConfig/get');
  store.dispatch('leads/get');
});
</script>

<template>
  <div class="flex flex-col h-full">
    <div class="flex items-center justify-between px-4 py-3">
      <h1 class="text-xl font-cormorant text-n-slate-12">
        {{ $t('RAMON.FUNIL.TITLE') }}
      </h1>
      <button
        class="flex items-center gap-1 px-3 py-1.5 text-sm rounded-lg bg-n-iris-9 text-white hover:bg-n-iris-10"
        @click="emit('new-lead')"
      >
        <span class="i-lucide-plus size-4" />{{ $t('RAMON.FUNIL.NEW_LEAD') }}
      </button>
    </div>
    <div class="flex flex-1 gap-3 px-4 pb-4 overflow-x-auto">
      <KanbanColumn
        v-for="stage in stages"
        :key="stage.id"
        :stage="stage"
        :leads="leadsByStage(stage.id)"
        @move="onMove"
        @open-conversation="id => emit('open-conversation', id)"
        @open-lead="lead => emit('open-lead', lead)"
      />
    </div>
  </div>
</template>
