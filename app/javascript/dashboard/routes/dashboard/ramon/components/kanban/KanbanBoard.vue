<script setup>
import { computed, ref, onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import Draggable from 'vuedraggable';
import { useStore, useStoreGetters } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { downloadCsvFile } from 'dashboard/helper/downloadHelper';
import { useKeyboardEvents } from 'dashboard/composables/useKeyboardEvents';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { CAMPO } from '../../helpers/ui';
import { leadsToCsv } from '../../helpers/leadsCsv';
import { mensagemErro } from '../../helpers/erro';
import KanbanColumn from './KanbanColumn.vue';
import KanbanFilters from './KanbanFilters.vue';
import FilterChips from './FilterChips.vue';
import SavedViews from './SavedViews.vue';
import SwimlaneBoard from './SwimlaneBoard.vue';
import LeadListView from './LeadListView.vue';
import BulkActionsBar from './BulkActionsBar.vue';
import LeadDrawer from './LeadDrawer.vue';
import ConversationDock from './ConversationDock.vue';
import RemoveStageModal from './RemoveStageModal.vue';
import LostReasonModal from './LostReasonModal.vue';
import WonValueModal from './WonValueModal.vue';
import NamePromptModal from '../NamePromptModal.vue';
import ConfirmModal from '../ConfirmModal.vue';
import RamonPageHeader from '../RamonPageHeader.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const emit = defineEmits(['new-lead']);
const store = useStore();
const getters = useStoreGetters();
const { t } = useI18n();
// Etapas são do admin (LeadStagePolicy): criar, editar e reordenar.
const { isAdmin } = useAdmin();

const stages = computed(() => getters['leadConfig/getStages'].value);

// Conversão por etapa (do dashboard): mapa stage_id → rate, só quando alguém
// de fato entrou na etapa na janela — mesma guarda de FunnelConversion.vue.
const conversion = computed(
  () => getters['ramonDashboard/getData']?.value?.conversion || []
);
const rateByStage = computed(() =>
  Object.fromEntries(
    conversion.value
      .filter(row => row.entered > 0)
      .map(row => [row.stage_id, row.rate])
  )
);
const rateFor = stageId => rateByStage.value[stageId] ?? null;
const lostReasons = computed(() => getters['leadConfig/getLostReasons'].value);
const orderedStages = ref([]);
const stageToRemove = ref(null);
const newStageModalOpen = ref(false);
// Ganho/Perdido mudam o que acontece com os leads da etapa: confirmar antes.
const stageTypeToConfirm = ref(null);

// Estado do primeiro carregamento: skeleton enquanto busca, erro com retry.
const uiFlags = computed(() => getters['leads/getUIFlags'].value);
const hasLoadedOnce = ref(false);
watch(
  () => uiFlags.value.isFetching,
  (now, prev) => {
    if (prev && !now) hasLoadedOnce.value = true;
  }
);
const initialLoading = computed(
  () => uiFlags.value.isFetching && !hasLoadedOnce.value
);
const loadError = ref(false);
const loadLeads = async () => {
  loadError.value = false;
  try {
    await store.dispatch('leads/loadFilters');
  } catch (e) {
    loadError.value = true;
  }
};

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

// Busca do board (nome/contato, server-side) sempre à vista no header, com
// debounce ~300ms para não disparar um request por tecla.
const search = ref(filters.value?.q ?? '');
let searchTimer = null;
watch(search, value => {
  clearTimeout(searchTimer);
  if (value === filters.value?.q) return;
  searchTimer = setTimeout(() => onFilterUpdate({ q: value }), 300);
});
// loadFilters / Limpar / quadro mudam o q por fora — refletir na caixa
watch(
  () => filters.value?.q,
  value => {
    if (value !== search.value) search.value = value ?? '';
  }
);

// Painel de filtros recolhido por padrão — o kanban é o protagonista da tela.
// O badge no botão mostra quantos filtros estão ativos mesmo com o painel fechado.
const filtersOpen = ref(false);
const FILTER_KEYS = [
  'q',
  'benefitTypeId',
  'leadPriorityId',
  'agentId',
  'source',
  'channel',
  'leadStageId',
  'createdAfter',
  'createdBefore',
  'stalled',
  'noOpenTask',
];
const activeFilterCount = computed(() => {
  const f = filters.value || {};
  return FILTER_KEYS.filter(key => f[key]).length;
});

const onMove = async ({ id, leadStageId, newIndex }) => {
  const stage = findStage(leadStageId);
  const lead = findLead(id);
  // Etapa de perda sem motivo: segura o movimento e exige o motivo.
  if (stage?.is_lost && !lead?.lost_reason) {
    pendingMove.value = { id, leadStageId, position: newIndex };
    lostModalOpen.value = true;
    return;
  }
  // Etapa de ganho de lead: SEMPRE segura o movimento e pede confirmação do
  // valor (pré-preenchido quando já existe), para o valor estimado automático
  // nunca virar "valor de contrato" sem 1 clique/Enter humano.
  if (stage?.is_won) {
    pendingMove.value = { id, leadStageId, position: newIndex };
    wonModalOpen.value = true;
    return;
  }
  // Guarda a origem ANTES de persistir, para o desfazer do toast.
  const previous = {
    leadStageId: lead?.lead_stage_id,
    position: lead?.position,
  };
  // Demais casos persistem na hora.
  try {
    await store.dispatch('leads/move', { id, leadStageId, position: newIndex });
  } catch (e) {
    useAlert(t('RAMON.FUNIL.SAVE_ERROR'));
    boardVersion.value += 1; // devolve o card à origem
    return;
  }
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
  try {
    await store.dispatch('leads/update', {
      id,
      lead_stage_id: leadStageId,
      position,
      lost_reason: lostReason,
    });
  } catch (e) {
    // modal fica aberto para o retry
    useAlert(t('RAMON.FUNIL.SAVE_ERROR'));
    return;
  }
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
  try {
    await store.dispatch('leads/update', {
      id,
      lead_stage_id: leadStageId,
      position,
      ...(value != null ? { value } : {}),
    });
  } catch (e) {
    // modal fica aberto para o retry
    useAlert(t('RAMON.FUNIL.SAVE_ERROR'));
    return;
  }
  pendingMove.value = null;
  wonModalOpen.value = false;
};

const cancelWon = () => {
  pendingMove.value = null;
  wonModalOpen.value = false;
  boardVersion.value += 1; // devolve o card à origem
};

// Ctrl K → etapa de ganho: o palette só pede; o modal de valor é o mesmo.
watch(
  () => getters['leads/getWonRequest']?.value,
  request => {
    if (!request) return;
    pendingMove.value = { ...request };
    wonModalOpen.value = true;
    store.dispatch('leads/requestWon', null);
  },
  { immediate: true }
);
const onOpenLead = lead => {
  store.dispatch('leads/select', lead.id);
};
const onOpenConversation = id => store.dispatch('leads/toggleDock', id);
const router = useRouter();
const onOpenDossie = lead =>
  router.push({ name: 'ramon_lead_dossie', params: { leadId: lead.id } });

// Seleção em lote: checkbox no card/linha alimenta leads.selectedIds; a barra
// de ações aparece embaixo enquanto houver seleção.
const selectedIds = computed(
  () => getters['leads/getSelectedIds']?.value ?? []
);
const onToggleSelect = lead => store.dispatch('leads/toggleSelection', lead.id);

// Toggle Colunas / Raias / Lista + agrupador das raias, persistidos por
// usuário (mesmo padrão localStorage dos filtros).
const VIEW_KEY = 'ramon_kanban_view';
const readViewState = () => {
  try {
    return JSON.parse(localStorage.getItem(VIEW_KEY) || '{}');
  } catch (e) {
    return {};
  }
};
const savedViewState = readViewState();
const VIEW_MODES = ['columns', 'lanes', 'list'];
// 'sdr' era o antigo "dono" — quadros/views salvos com ele seguem valendo.
const GROUP_BYS = ['thesis', 'sdr', 'closer', 'channel', 'priority'];
const viewMode = ref(
  VIEW_MODES.includes(savedViewState.view) ? savedViewState.view : 'columns'
);
const groupBy = ref(
  GROUP_BYS.includes(savedViewState.groupBy) ? savedViewState.groupBy : 'thesis'
);
watch([viewMode, groupBy], ([view, group]) => {
  try {
    localStorage.setItem(VIEW_KEY, JSON.stringify({ view, groupBy: group }));
  } catch (e) {
    // localStorage indisponível: seguimos sem persistir
  }
});

// Aplicar um quadro remonta as colunas (:key) para relerem o colapso salvo.
const columnsKey = ref(0);
const onApplyBoard = board => {
  viewMode.value = VIEW_MODES.includes(board?.view) ? board.view : 'columns';
  groupBy.value = GROUP_BYS.includes(board?.groupBy) ? board.groupBy : 'thesis';
  columnsKey.value += 1;
};

// Atalhos (item 13 do 4b): j/k navegam entre cards, e abre a gaveta, c abre a
// conversa. Lista achatada na ordem visual das colunas.
const focusedLeadId = ref(null);

// Lista achatada na ordem visual das colunas — também alimenta raias e lista.
const allLeads = computed(() =>
  orderedStages.value.flatMap(s => stageLeads(s.id))
);
const flatLeads = () => allLeads.value;

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

// Com qualquer modal aberto, os atalhos do board ficam mudos.
const anyModalOpen = () =>
  lostModalOpen.value ||
  wonModalOpen.value ||
  !!stageToRemove.value ||
  !!stageTypeToConfirm.value ||
  newStageModalOpen.value;

useKeyboardEvents({
  KeyJ: {
    action: () => {
      if (!anyModalOpen()) moveFocus(1);
    },
  },
  KeyK: {
    action: () => {
      if (!anyModalOpen()) moveFocus(-1);
    },
  },
  KeyE: {
    action: () => {
      if (anyModalOpen()) return;
      const lead = focusedLead();
      if (lead) onOpenLead(lead);
    },
  },
  KeyC: {
    action: () => {
      if (anyModalOpen()) return;
      const lead = focusedLead();
      if (lead?.conversation_id) onOpenConversation(lead.conversation_id);
    },
  },
});

// Erro do servidor (nome duplicado, valor inválido…) aparece com o motivo.
const updateStage = async payload => {
  try {
    await store.dispatch('leadConfig/updateStage', payload);
  } catch (e) {
    useAlert(mensagemErro(e, t('RAMON.FUNIL.SAVE_ERROR')));
  }
};
const onRenameStage = ({ id, name }) => updateStage({ id, name });
const onRecolorStage = ({ id, color }) => updateStage({ id, color });
const onSetStageClientName = ({ id, nomeCliente }) =>
  updateStage({ id, nome_cliente: nomeCliente });
const applyStageType = async ({ id, type }) => {
  await updateStage({ id, is_won: type === 'won', is_lost: type === 'lost' });
  // o servidor desmarca a etapa de ganho/perda anterior: recarrega todas
  store.dispatch('leadConfig/get');
};
const onSetStageType = ({ id, type }) => {
  const stage = stages.value.find(s => s.id === id);
  const flag = { won: 'is_won', lost: 'is_lost' }[type];
  if (!flag || stage?.[flag]) {
    applyStageType({ id, type });
    return;
  }
  const atual = stages.value.find(s => s[flag] && s.id !== id);
  stageTypeToConfirm.value = {
    id,
    type,
    name: stage?.name,
    atual: atual?.name,
  };
};
const stageTypeMessage = computed(() => {
  const confirm = stageTypeToConfirm.value;
  if (!confirm) return '';
  const won = confirm.type === 'won';
  const efeito = won
    ? t('RAMON.FUNIL.STAGE.CONFIRM_WON_EFFECT')
    : t('RAMON.FUNIL.STAGE.CONFIRM_LOST_EFFECT');
  if (!confirm.atual) return efeito;
  const anterior = won
    ? t('RAMON.FUNIL.STAGE.CONFIRM_WON_PREVIOUS', { name: confirm.atual })
    : t('RAMON.FUNIL.STAGE.CONFIRM_LOST_PREVIOUS', { name: confirm.atual });
  return `${efeito} ${anterior}`;
});
const stageTypeTitle = computed(() => {
  const confirm = stageTypeToConfirm.value;
  if (!confirm) return '';
  return confirm.type === 'won'
    ? t('RAMON.FUNIL.STAGE.CONFIRM_WON_TITLE', { name: confirm.name })
    : t('RAMON.FUNIL.STAGE.CONFIRM_LOST_TITLE', { name: confirm.name });
});
const stageTypeConfirmLabel = computed(() =>
  stageTypeToConfirm.value?.type === 'won'
    ? t('RAMON.FUNIL.STAGE.TYPE_WON')
    : t('RAMON.FUNIL.STAGE.TYPE_LOST')
);
const confirmStageType = () => {
  const confirm = stageTypeToConfirm.value;
  stageTypeToConfirm.value = null;
  applyStageType(confirm);
};
const onRemoveStage = stage => {
  stageToRemove.value = stage;
};
const confirmRemove = async ({ id, moveToStageId }) => {
  try {
    await store.dispatch('leadConfig/deleteStage', { id, moveToStageId });
    stageToRemove.value = null;
    // A movimentação roda em job; os cards migram conforme os broadcasts chegam.
    useAlert(t('RAMON.FUNIL.STAGE_MERGE_QUEUED'));
  } catch (e) {
    useAlert(mensagemErro(e, t('RAMON.FUNIL.SAVE_ERROR')));
  }
};
const addStage = () => {
  newStageModalOpen.value = true;
};
const confirmAddStage = async name => {
  // Fechar antes do dispatch = guard contra duplo-fire do confirm.
  if (!newStageModalOpen.value) return;
  newStageModalOpen.value = false;
  try {
    await store.dispatch('leadConfig/createStage', { name });
  } catch (e) {
    useAlert(mensagemErro(e, t('RAMON.FUNIL.SAVE_ERROR')));
  }
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
  loadLeads();
  store.dispatch('agents/get');
});

const exportCsv = () => {
  const all = allLeads.value;
  const date = new Date().toISOString().slice(0, 10);
  const channels = getters['leadConfig/getChannels'].value;
  downloadCsvFile(`funil-${date}.csv`, leadsToCsv(all, channels));
};
</script>

<template>
  <div class="flex flex-col h-full">
    <div class="px-4 pt-3">
      <!-- mock 1d: título curto, sem subtítulo; a busca do board fica à vista
           (o Ctrl K global continua abrindo o palette) -->
      <RamonPageHeader compact :title="$t('RAMON.FUNIL.TITLE')">
        <template #actions>
          <label class="relative mb-0 w-44 md:w-56">
            <span
              class="absolute i-lucide-search size-3.5 text-n-slate-10 start-2.5 top-1/2 -translate-y-1/2 pointer-events-none"
            />
            <input
              v-model="search"
              data-testid="funil-search"
              class="!ps-8"
              :class="[CAMPO, { '!outline-n-blue-8': filters?.q }]"
              :title="$t('RAMON.FUNIL.HOTKEYS_HINT')"
              :placeholder="$t('RAMON.FUNIL.FILTERS.SEARCH')"
            />
          </label>
          <Button
            data-testid="filters-toggle"
            sm
            faded
            :color="filtersOpen || activeFilterCount ? 'blue' : 'slate'"
            icon="i-lucide-sliders-horizontal"
            @click="filtersOpen = !filtersOpen"
          >
            {{ $t('RAMON.FUNIL.FILTERS.TOGGLE') }}
            <span
              v-if="activeFilterCount"
              data-testid="filters-active-count"
              class="flex items-center justify-center min-w-4 h-4 px-1 font-mono text-[10px] rounded-full bg-n-brand text-white"
            >
              {{ activeFilterCount }}
            </span>
          </Button>
          <Button
            data-testid="export-csv"
            sm
            faded
            slate
            icon="i-lucide-download"
            :label="$t('RAMON.FUNIL.EXPORT_CSV')"
            @click="exportCsv"
          />
          <Button
            sm
            icon="i-lucide-plus"
            :label="$t('RAMON.FUNIL.NEW_LEAD')"
            @click="emit('new-lead')"
          />
        </template>
      </RamonPageHeader>
    </div>
    <!-- linha de controle: quadro ativo + toggle Colunas/Raias/Lista + agrupador -->
    <div class="flex flex-wrap items-center gap-3 px-4 pb-1">
      <SavedViews :view="viewMode" :group-by="groupBy" @apply="onApplyBoard" />
      <div
        class="flex gap-0.5 rounded-lg p-0.5 bg-n-alpha-2"
        data-testid="view-toggle"
      >
        <button
          v-for="mode in ['columns', 'lanes', 'list']"
          :key="mode"
          :data-testid="`view-toggle-${mode}`"
          class="px-3 py-1 text-xs rounded-md"
          :class="
            viewMode === mode
              ? 'bg-n-solid-1 text-n-slate-12 font-medium shadow-sm'
              : 'text-n-slate-10 hover:text-n-slate-12'
          "
          @click="viewMode = mode"
        >
          {{ $t(`RAMON.KANBAN.VIEW.${mode.toUpperCase()}`) }}
        </button>
      </div>
      <!-- mock 2b: "agrupar por: tese · dono · canal · prioridade" inline,
           ativo em azul — sem select (o CSS global de select desalinha) -->
      <div
        v-show="viewMode === 'lanes'"
        data-testid="lanes-group-by"
        class="flex items-center gap-0.5 text-xs text-n-slate-10"
      >
        <span class="ltr:mr-1 rtl:ml-1">{{
          $t('RAMON.KANBAN.VIEW.GROUP_BY')
        }}</span>
        <button
          v-for="group in GROUP_BYS"
          :key="group"
          :data-testid="`lanes-group-${group}`"
          class="rounded-md px-1.5 py-1 text-xs"
          :class="
            groupBy === group
              ? 'bg-n-blue-9/[0.08] dark:bg-n-blue-9/[0.16] font-medium text-n-blue-11'
              : 'text-n-slate-10 hover:text-n-slate-12'
          "
          @click="groupBy = group"
        >
          {{ $t(`RAMON.KANBAN.VIEW.GROUP.${group.toUpperCase()}`) }}
        </button>
      </div>
    </div>
    <!-- chips removíveis dos filtros ativos + resumo do pipeline -->
    <FilterChips :filters="filters" @update="onFilterUpdate" />
    <!-- v-show (não v-if): o board reage ao evento update do KanbanFilters
         mesmo com o painel fechado, e abrir/fechar não perde o estado da busca -->
    <div v-show="filtersOpen" class="pb-1 border-b border-n-weak">
      <KanbanFilters :filters="filters" @update="onFilterUpdate" />
    </div>
    <!-- fetch inicial falhou: mensagem + retry no lugar de um board vazio -->
    <div
      v-if="loadError"
      data-testid="board-load-error"
      class="flex flex-col items-center justify-center flex-1 gap-3 px-4 pb-4"
    >
      <p class="text-sm text-n-slate-11">
        {{ $t('RAMON.FUNIL.LOAD_ERROR') }}
      </p>
      <Button
        data-testid="board-load-retry"
        sm
        faded
        slate
        :label="$t('RAMON.LEAD_PANEL.RETRY')"
        @click="loadLeads"
      />
    </div>
    <!-- primeiro fetch: skeleton em vez de colunas "vazias" mentirosas -->
    <div
      v-else-if="initialLoading"
      data-testid="board-skeleton"
      class="flex flex-1 min-h-0 gap-3 px-4 pb-4 overflow-x-hidden"
    >
      <div
        v-for="n in 4"
        :key="n"
        class="w-72 h-full flex-shrink-0 rounded-xl bg-n-alpha-2 animate-pulse"
      />
    </div>
    <!-- min-h-0 permite a faixa encolher dentro do flex pai; sem isso a coluna
         cresce além da viewport e os cards abaixo da dobra ficam inacessíveis -->
    <div
      v-else-if="viewMode === 'columns'"
      class="flex flex-1 min-h-0 gap-3 px-4 pb-4 overflow-x-auto"
    >
      <Draggable
        :key="columnsKey"
        v-model="orderedStages"
        group="stages"
        item-key="id"
        :disabled="!isAdmin"
        ghost-class="ramon-drag-ghost"
        class="flex h-full gap-3"
        handle=".stage-drag-handle"
        @change="onColumnsReorder"
      >
        <template #item="{ element }">
          <KanbanColumn
            :stage="element"
            :leads="stageLeads(element.id)"
            :focused-lead-id="focusedLeadId"
            selectable
            :selected-lead-ids="selectedIds"
            :conversion-rate="rateFor(element.id)"
            :editable="isAdmin"
            @move="onMove"
            @open-conversation="onOpenConversation"
            @open-lead="onOpenLead"
            @open-dossie="onOpenDossie"
            @toggle-select="onToggleSelect"
            @rename-stage="onRenameStage"
            @recolor-stage="onRecolorStage"
            @set-stage-type="onSetStageType"
            @set-stage-client-name="onSetStageClientName"
            @remove-stage="onRemoveStage"
          />
        </template>
      </Draggable>
      <Button
        v-if="isAdmin"
        data-testid="add-stage"
        sm
        faded
        slate
        icon="i-lucide-plus"
        class="self-start shrink-0"
        :label="$t('RAMON.FUNIL.STAGE.ADD')"
        @click="addStage"
      />
    </div>
    <SwimlaneBoard
      v-else-if="viewMode === 'lanes'"
      :stages="orderedStages"
      :leads="allLeads"
      :group-by="groupBy"
      :selected-lead-ids="selectedIds"
      @move="onMove"
      @open-conversation="onOpenConversation"
      @open-lead="onOpenLead"
      @open-dossie="onOpenDossie"
      @toggle-select="onToggleSelect"
    />
    <LeadListView
      v-else
      :leads="allLeads"
      :stages="orderedStages"
      :selected-lead-ids="selectedIds"
      @open-lead="onOpenLead"
      @toggle-select="onToggleSelect"
    />
    <BulkActionsBar v-if="selectedIds.length" :suspend-esc="anyModalOpen()" />
    <LeadDrawer @open-conversation="onOpenConversation" />
    <ConversationDock :suspend-esc="anyModalOpen()" />
    <Transition
      enter-active-class="transition-opacity duration-150"
      leave-active-class="transition-opacity duration-150"
      enter-from-class="opacity-0"
      leave-to-class="opacity-0"
    >
      <RemoveStageModal
        v-if="stageToRemove"
        :stage="stageToRemove"
        :stages="stages"
        :leads-count="stageLeads(stageToRemove.id).length"
        @confirm="confirmRemove"
        @cancel="stageToRemove = null"
      />
    </Transition>
    <Transition
      enter-active-class="transition-opacity duration-150"
      leave-active-class="transition-opacity duration-150"
      enter-from-class="opacity-0"
      leave-to-class="opacity-0"
    >
      <LostReasonModal
        v-if="lostModalOpen"
        :lost-reasons="lostReasons"
        @confirm-move="confirmLost"
        @cancel-move="cancelLost"
      />
    </Transition>
    <Transition
      enter-active-class="transition-opacity duration-150"
      leave-active-class="transition-opacity duration-150"
      enter-from-class="opacity-0"
      leave-to-class="opacity-0"
    >
      <WonValueModal
        v-if="wonModalOpen"
        :initial-value="findLead(pendingMove?.id)?.value ?? null"
        @confirm-value="confirmWon"
        @cancel-value="cancelWon"
      />
    </Transition>
    <Transition
      enter-active-class="transition-opacity duration-150"
      leave-active-class="transition-opacity duration-150"
      enter-from-class="opacity-0"
      leave-to-class="opacity-0"
    >
      <NamePromptModal
        v-if="newStageModalOpen"
        :title="$t('RAMON.FUNIL.STAGE.NEW_PROMPT')"
        :placeholder="$t('RAMON.FUNIL.STAGE.NEW_PROMPT')"
        :confirm-label="$t('RAMON.FUNIL.STAGE.ADD')"
        @confirm="confirmAddStage"
        @cancel="newStageModalOpen = false"
      />
    </Transition>
    <ConfirmModal
      v-if="stageTypeToConfirm"
      data-testid="stage-type-confirm"
      :title="stageTypeTitle"
      :message="stageTypeMessage"
      :confirm-label="stageTypeConfirmLabel"
      :confirm-color="stageTypeToConfirm.type === 'won' ? 'blue' : 'ruby'"
      @confirm="confirmStageType"
      @cancel="stageTypeToConfirm = null"
    />
  </div>
</template>
