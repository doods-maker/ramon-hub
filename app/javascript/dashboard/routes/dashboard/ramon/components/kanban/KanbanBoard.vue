<script setup>
import { computed, ref, onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Draggable from 'vuedraggable';
import { useStore, useStoreGetters } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { downloadCsvFile } from 'dashboard/helper/downloadHelper';
import { useKeyboardEvents } from 'dashboard/composables/useKeyboardEvents';
import { leadsToCsv } from '../../helpers/leadsCsv';
import KanbanColumn from './KanbanColumn.vue';
import KanbanFilters from './KanbanFilters.vue';
import SavedViews from './SavedViews.vue';
import LeadDrawer from './LeadDrawer.vue';
import ConversationDock from './ConversationDock.vue';
import RemoveStageModal from './RemoveStageModal.vue';
import LostReasonModal from './LostReasonModal.vue';
import WonValueModal from './WonValueModal.vue';

const emit = defineEmits(['new-lead']);
const store = useStore();
const getters = useStoreGetters();
const { t } = useI18n();

const stages = computed(() => getters['leadConfig/getStages'].value);
const lostReasons = computed(() => getters['leadConfig/getLostReasons'].value);
const orderedStages = ref([]);
const stageToRemove = ref(null);

// Guarda o movimento até o modal de perda/ganho resolver.
const pendingMove = ref(null);
const lostModalOpen = ref(false);
const wonModalOpen = ref(false);
// Bump para forçar o recomputo de stageLeads e devolver o card à origem quando
// o usuário cancela um movimento para etapa de perda (o store não mudou).
const boardVersion = ref(0);

const findStage = id => stages.value.find(s => s.id === id);
const findLead = id => getters['leads/getLeads'].value.find(l => l.id === id);

// Lê boardVersion durante o render para criar dependência reativa: ao
// incrementá-lo, o array de leads é recalculado (nova referência) e as colunas
// ressincronizam sua cópia local, revertendo um drop não persistido.
const stageLeads = stageId => {
  const version = boardVersion.value;
  return version >= 0 ? getters['leads/getLeadsByStage'].value(stageId) : [];
};
const filters = computed(() => getters['leads/getFilters'].value);
const onFilterUpdate = partial => store.dispatch('leads/setFilters', partial);

const onMove = async ({ id, leadStageId, newIndex }) => {
  const stage = findStage(leadStageId);
  const lead = findLead(id);
  // Etapa de perda sem motivo: segura o movimento e exige o motivo.
  if (stage?.is_lost && !lead?.lost_reason) {
    pendingMove.value = { id, leadStageId, position: newIndex };
    lostModalOpen.value = true;
    return;
  }
  // Etapa de ganho de lead sem valor: segura o movimento e pede o valor, para
  // o dossiê de ganho nascer já com o valor fechado (um único update no fim).
  if (stage?.is_won && !lead?.value) {
    pendingMove.value = { id, leadStageId, position: newIndex };
    wonModalOpen.value = true;
    return;
  }
  // Guarda a origem ANTES de persistir, para o desfazer do toast.
  const previous = {
    leadStageId: lead?.lead_stage_id,
    position: lead?.position,
  };
  // Demais casos (inclui ganho de lead que já tem valor) persistem na hora.
  await store.dispatch('leads/move', { id, leadStageId, position: newIndex });
  // Só oferece desfazer quando trocou de coluna (reordenar não pede undo).
  if (previous.leadStageId && previous.leadStageId !== leadStageId) {
    useAlert(t('RAMON.KANBAN.MOVE_DONE'), {
      type: 'button',
      message: t('RAMON.KANBAN.MOVE_UNDO'),
      duration: 5000,
      onClick: () =>
        store.dispatch('leads/move', {
          id,
          leadStageId: previous.leadStageId,
          position: previous.position ?? 0,
        }),
    });
  }
};

const confirmLost = async ({ lostReason }) => {
  if (!pendingMove.value) return;
  const { id, leadStageId, position } = pendingMove.value;
  await store.dispatch('leads/update', {
    id,
    lead_stage_id: leadStageId,
    position,
    lost_reason: lostReason,
  });
  pendingMove.value = null;
  lostModalOpen.value = false;
};

const cancelLost = () => {
  pendingMove.value = null;
  lostModalOpen.value = false;
  boardVersion.value += 1; // devolve o card à origem
};

const confirmWon = async ({ value }) => {
  if (!pendingMove.value) return;
  const { id, leadStageId, position } = pendingMove.value;
  // Um único update: move e (quando informado) grava o valor no mesmo passo.
  await store.dispatch('leads/update', {
    id,
    lead_stage_id: leadStageId,
    position,
    ...(value != null ? { value } : {}),
  });
  pendingMove.value = null;
  wonModalOpen.value = false;
};

const cancelWon = () => {
  pendingMove.value = null;
  wonModalOpen.value = false;
  boardVersion.value += 1; // devolve o card à origem
};
const onOpenLead = lead => {
  store.dispatch('leads/select', lead.id);
};
const onOpenConversation = id => store.dispatch('leads/toggleDock', id);

// Atalhos (item 13 do 4b): j/k navegam entre cards, e abre a gaveta, c abre a
// conversa. Lista achatada na ordem visual das colunas.
const focusedLeadId = ref(null);

const flatLeads = () => orderedStages.value.flatMap(s => stageLeads(s.id));

const moveFocus = delta => {
  const all = flatLeads();
  if (!all.length) return;
  const idx = all.findIndex(l => l.id === focusedLeadId.value);
  let next = idx + delta;
  if (idx === -1) next = delta > 0 ? 0 : all.length - 1;
  const clamped = Math.max(0, Math.min(all.length - 1, next));
  focusedLeadId.value = all[clamped].id;
};

const focusedLead = () => flatLeads().find(l => l.id === focusedLeadId.value);

useKeyboardEvents({
  KeyJ: { action: () => moveFocus(1) },
  KeyK: { action: () => moveFocus(-1) },
  KeyE: {
    action: () => {
      const lead = focusedLead();
      if (lead) onOpenLead(lead);
    },
  },
  KeyC: {
    action: () => {
      const lead = focusedLead();
      if (lead?.conversation_id) onOpenConversation(lead.conversation_id);
    },
  },
});

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

const exportCsv = () => {
  const all = orderedStages.value.flatMap(s => stageLeads(s.id));
  const date = new Date().toISOString().slice(0, 10);
  const channels = getters['leadConfig/getChannels'].value;
  downloadCsvFile(`funil-${date}.csv`, leadsToCsv(all, channels));
};
</script>

<template>
  <div class="flex flex-col h-full">
    <div class="flex items-center justify-between px-4 py-3">
      <h1 class="text-xl font-cormorant text-n-slate-12">
        {{ $t('RAMON.FUNIL.TITLE') }}
      </h1>
      <span class="hidden lg:inline text-xs text-n-slate-9">
        {{ $t('RAMON.FUNIL.HOTKEYS_HINT') }}
      </span>
      <div class="flex items-center gap-2">
        <button
          data-testid="export-csv"
          class="flex items-center gap-1 px-3 py-1.5 text-sm rounded-lg text-n-slate-11 border border-n-weak hover:text-n-slate-12"
          @click="exportCsv"
        >
          <span class="i-lucide-download size-4" />{{
            $t('RAMON.FUNIL.EXPORT_CSV')
          }}
        </button>
        <button
          class="flex items-center gap-1 px-3 py-1.5 text-sm rounded-lg bg-n-iris-9 text-white hover:bg-n-iris-10"
          @click="emit('new-lead')"
        >
          <span class="i-lucide-plus size-4" />{{ $t('RAMON.FUNIL.NEW_LEAD') }}
        </button>
      </div>
    </div>
    <SavedViews />
    <KanbanFilters :filters="filters" @update="onFilterUpdate" />
    <!-- min-h-0 permite a faixa encolher dentro do flex pai; sem isso a coluna
         cresce além da viewport e os cards abaixo da dobra ficam inacessíveis -->
    <div class="flex flex-1 min-h-0 gap-3 px-4 pb-4 overflow-x-auto">
      <Draggable
        v-model="orderedStages"
        group="stages"
        item-key="id"
        class="flex items-start h-full gap-3"
        handle=".stage-drag-handle"
        @change="onColumnsReorder"
      >
        <template #item="{ element }">
          <KanbanColumn
            :stage="element"
            :leads="stageLeads(element.id)"
            :focused-lead-id="focusedLeadId"
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
    <LostReasonModal
      v-if="lostModalOpen"
      :lost-reasons="lostReasons"
      @confirm-move="confirmLost"
      @cancel-move="cancelLost"
    />
    <WonValueModal
      v-if="wonModalOpen"
      @confirm-value="confirmWon"
      @cancel-value="cancelWon"
    />
  </div>
</template>
