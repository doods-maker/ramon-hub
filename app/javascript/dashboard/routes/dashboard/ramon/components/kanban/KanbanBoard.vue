<script setup>
import { computed, ref, onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Draggable from 'vuedraggable';
import { useStore, useStoreGetters } from 'dashboard/composables/store';
import KanbanColumn from './KanbanColumn.vue';
import KanbanFilters from './KanbanFilters.vue';
import LeadDrawer from './LeadDrawer.vue';
import ConversationDock from './ConversationDock.vue';
import RemoveStageModal from './RemoveStageModal.vue';

const emit = defineEmits(['new-lead']);
const store = useStore();
const getters = useStoreGetters();
const { t } = useI18n();

const stages = computed(() => getters['leadConfig/getStages'].value);
const orderedStages = ref([]);
const stageToRemove = ref(null);

const leadsByStage = stageId => getters['leads/getLeadsByStage'].value(stageId);
const filters = computed(() => getters['leads/getFilters'].value);
const onFilterUpdate = partial => store.dispatch('leads/setFilters', partial);

const onMove = ({ id, leadStageId, newIndex }) => {
  store.dispatch('leads/move', { id, leadStageId, position: newIndex });
};
const onOpenLead = lead => {
  store.dispatch('leads/select', lead.id);
};
const onOpenConversation = id => store.dispatch('leads/toggleDock', id);

const onRenameStage = ({ id, name }) =>
  store.dispatch('leadConfig/updateStage', { id, name });
const onRecolorStage = ({ id, color }) =>
  store.dispatch('leadConfig/updateStage', { id, color });
const onSetStageType = ({ id, type }) =>
  store.dispatch('leadConfig/updateStage', {
    id,
    is_won: type === 'won',
    is_lost: type === 'lost',
  });
const onRemoveStage = stage => {
  stageToRemove.value = stage;
};
const confirmRemove = async ({ id, moveToStageId }) => {
  await store.dispatch('leadConfig/deleteStage', { id, moveToStageId });
  stageToRemove.value = null;
};
const addStage = async () => {
  // eslint-disable-next-line no-alert
  const name = window.prompt(t('RAMON.FUNIL.STAGE.NEW_PROMPT'));
  if (name && name.trim())
    await store.dispatch('leadConfig/createStage', { name: name.trim() });
};
const onColumnsReorder = () => {
  store.dispatch(
    'leadConfig/reorderStages',
    orderedStages.value.map(s => s.id)
  );
};

// Espelha as stages do store num array local gravável para o vuedraggable.
watch(
  stages,
  newStages => {
    orderedStages.value = [...newStages];
  },
  { immediate: true }
);

onMounted(() => {
  store.dispatch('leadConfig/get');
  store.dispatch('leads/loadFilters');
  store.dispatch('agents/get');
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
    <KanbanFilters :filters="filters" @update="onFilterUpdate" />
    <div class="flex flex-1 gap-3 px-4 pb-4 overflow-x-auto">
      <Draggable
        v-model="orderedStages"
        group="stages"
        item-key="id"
        class="flex gap-3"
        handle=".stage-drag-handle"
        @change="onColumnsReorder"
      >
        <template #item="{ element }">
          <KanbanColumn
            :stage="element"
            :leads="leadsByStage(element.id)"
            @move="onMove"
            @open-conversation="onOpenConversation"
            @open-lead="onOpenLead"
            @rename-stage="onRenameStage"
            @recolor-stage="onRecolorStage"
            @set-stage-type="onSetStageType"
            @remove-stage="onRemoveStage"
          />
        </template>
      </Draggable>
      <button
        class="flex items-center self-start gap-1 px-3 py-2 text-sm rounded-lg text-n-slate-11 border border-dashed border-n-weak hover:text-n-slate-12"
        @click="addStage"
      >
        <span class="i-lucide-plus size-4" />{{ $t('RAMON.FUNIL.STAGE.ADD') }}
      </button>
    </div>
    <LeadDrawer @open-conversation="onOpenConversation" />
    <ConversationDock />
    <RemoveStageModal
      v-if="stageToRemove"
      :stage="stageToRemove"
      :stages="stages"
      @confirm="confirmRemove"
      @cancel="stageToRemove = null"
    />
  </div>
</template>
