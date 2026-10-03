<script setup>
// Quadros salvos (mock 2a): as antigas Smart Views promovidas a entidade
// nomeada com cor + estado (filtros, colunas colapsadas, visualização,
// agrupamento), em ui_settings.ramon_lead_boards. O legado ramon_lead_views
// é convertido UMA vez na leitura e persistido no formato novo.
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { vOnClickOutside } from '@vueuse/components';
import { useStore, useStoreGetters } from 'dashboard/composables/store';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { BOARD_PALETTE, legacyToBoards } from '../../helpers/leadBoards';
import NamePromptModal from '../NamePromptModal.vue';
import ConfirmModal from '../ConfirmModal.vue';

const props = defineProps({
  view: { type: String, default: 'columns' },
  groupBy: { type: String, default: 'thesis' },
});
const emit = defineEmits(['apply']);

const store = useStore();
const getters = useStoreGetters();
const { t } = useI18n();
const { uiSettings, updateUISettings } = useUISettings();

const ACTIVE_KEY = 'ramon_lead_board_active';
const COLLAPSED_KEY = 'ramon_kanban_collapsed';

const boards = computed(() => uiSettings.value?.ramon_lead_boards ?? []);
const leads = computed(() => getters['leads/getLeads']?.value ?? []);
const currentFilters = computed(() => getters['leads/getFilters']?.value ?? {});

// Conversão do legado: roda uma única vez quando os ui_settings chegam com
// ramon_lead_views mas ainda sem ramon_lead_boards.
const migrated = ref(false);
// getter (não o ref cru): funciona igual com o ref real e com stubs de teste.
watch(
  () => uiSettings.value,
  settings => {
    if (migrated.value || !settings) return;
    const legacy = settings.ramon_lead_views;
    if (settings.ramon_lead_boards === undefined && legacy?.length) {
      migrated.value = true;
      updateUISettings({ ramon_lead_boards: legacyToBoards(legacy) });
    }
  },
  { immediate: true }
);

const readActiveId = () => {
  try {
    return JSON.parse(localStorage.getItem(ACTIVE_KEY) || 'null');
  } catch (e) {
    return null;
  }
};
const activeBoardId = ref(readActiveId());
const persistActive = id => {
  try {
    localStorage.setItem(ACTIVE_KEY, JSON.stringify(id));
  } catch (e) {
    // localStorage indisponível: seguimos sem persistir
  }
};

const activeBoard = computed(
  () => boards.value.find(board => board.id === activeBoardId.value) || null
);

const eq = (a, b) => String(a) === String(b);

// Contador client-side sobre os leads já carregados. A busca textual (q) NÃO
// entra aqui — o texto é resolvido server-side e não temos como reproduzi-lo.
const matchesFilters = (lead, filters = {}) => {
  if (filters.leadStageId && !eq(lead.lead_stage_id, filters.leadStageId))
    return false;
  if (filters.benefitTypeId && !eq(lead.benefit_type_id, filters.benefitTypeId))
    return false;
  if (
    filters.leadPriorityId &&
    !eq(lead.lead_priority_id, filters.leadPriorityId)
  )
    return false;
  if (filters.source && !eq(lead.source, filters.source)) return false;
  // agentId no servidor casa SDR ou Closer (leads_controller).
  if (
    filters.agentId &&
    !eq(lead.sdr_id, filters.agentId) &&
    !eq(lead.closer_id, filters.agentId)
  )
    return false;
  if (filters.channel && !eq(lead.channel, filters.channel)) return false;
  if (filters.stalled && !lead.stalled) return false;
  if (filters.noOpenTask && lead.open_tasks_count !== 0) return false;
  // created_at é ISO; comparar só a data (YYYY-MM-DD) evita ruído de fuso.
  const leadDate = lead.created_at ? lead.created_at.slice(0, 10) : null;
  if (filters.createdAfter && (!leadDate || leadDate < filters.createdAfter))
    return false;
  if (filters.createdBefore && (!leadDate || leadDate > filters.createdBefore))
    return false;
  return true;
};

const countFor = filters =>
  leads.value.filter(lead => matchesFilters(lead, filters)).length;

const open = ref(false);
const close = () => {
  open.value = false;
};

// Snapshot completo → o merge do setFilters equivale a substituir tudo,
// zerando o que o quadro não define.
const EMPTY_FILTERS = {
  benefitTypeId: null,
  leadPriorityId: null,
  agentId: null,
  source: '',
  channel: '',
  q: '',
  leadStageId: null,
  createdAfter: null,
  createdBefore: null,
  stalled: false,
  noOpenTask: false,
};

const readCollapsed = () => {
  try {
    return JSON.parse(localStorage.getItem(COLLAPSED_KEY) || '[]');
  } catch (e) {
    return [];
  }
};
const writeCollapsed = ids => {
  try {
    localStorage.setItem(COLLAPSED_KEY, JSON.stringify(ids || []));
  } catch (e) {
    // localStorage indisponível: seguimos sem persistir
  }
};

const applyBoard = board => {
  close();
  activeBoardId.value = board?.id ?? null;
  persistActive(activeBoardId.value);
  if (board) writeCollapsed(board.collapsed || []);
  store.dispatch('leads/setFilters', {
    ...EMPTY_FILTERS,
    ...(board?.filters || {}),
  });
  emit('apply', board);
};

// "Salvar no quadro": aparece quando os filtros atuais divergem do snapshot
// do quadro ativo — normaliza falsy pra null pra não acusar '' vs null.
const FILTER_KEYS = Object.keys(EMPTY_FILTERS);
const normalized = filters =>
  FILTER_KEYS.map(key => (filters?.[key] ? String(filters[key]) : null)).join(
    '|'
  );
const isDirty = computed(
  () =>
    !!activeBoard.value &&
    normalized(currentFilters.value) !== normalized(activeBoard.value.filters)
);

const persistBoards = next => updateUISettings({ ramon_lead_boards: next });

const saveToActiveBoard = () => {
  const next = boards.value.map(board =>
    board.id === activeBoardId.value
      ? {
          ...board,
          filters: { ...currentFilters.value },
          collapsed: readCollapsed(),
          view: props.view,
          groupBy: props.groupBy,
        }
      : board
  );
  persistBoards(next);
};

const newModalOpen = ref(false);
const confirmNewBoard = name => {
  newModalOpen.value = false;
  const board = {
    id: Date.now(),
    name,
    color: BOARD_PALETTE[boards.value.length % BOARD_PALETTE.length],
    filters: { ...currentFilters.value },
    collapsed: readCollapsed(),
    view: props.view,
    groupBy: props.groupBy,
  };
  persistBoards([...boards.value, board]);
  activeBoardId.value = board.id;
  persistActive(board.id);
  emit('apply', board);
};

const boardToRename = ref(null);
const confirmRename = name => {
  const next = boards.value.map(board =>
    board.id === boardToRename.value.id ? { ...board, name } : board
  );
  persistBoards(next);
  boardToRename.value = null;
};

const boardToRemove = ref(null);
const confirmRemove = () => {
  const removedId = boardToRemove.value.id;
  persistBoards(boards.value.filter(board => board.id !== removedId));
  boardToRemove.value = null;
  if (activeBoardId.value === removedId) applyBoard(null);
};
</script>

<template>
  <div v-on-click-outside="close" class="relative" data-testid="saved-views">
    <div class="flex items-center gap-1.5">
      <button
        data-testid="board-dropdown-toggle"
        class="flex items-center gap-2 px-3 py-1.5 text-sm rounded-lg bg-n-alpha-2 border border-n-weak text-n-slate-12 hover:border-n-iris-8"
        @click="open = !open"
      >
        <span
          class="size-2 rounded-sm shrink-0"
          :style="{ backgroundColor: activeBoard?.color || '#8d867d' }"
        />
        <span
          data-testid="board-active-name"
          class="max-w-56 truncate font-medium"
        >
          {{ $t('RAMON.FUNIL.BOARDS.LABEL') }}:
          {{ activeBoard?.name || $t('RAMON.FUNIL.BOARDS.ALL') }}
        </span>
        <span class="i-lucide-chevron-down size-3.5 text-n-slate-10" />
      </button>
      <button
        v-if="isDirty"
        data-testid="board-save-current"
        class="px-2.5 py-1 text-xs rounded-full text-n-iris-11 bg-n-alpha-2 hover:bg-n-alpha-3"
        :title="$t('RAMON.FUNIL.BOARDS.SAVE_TO_BOARD')"
        @click="saveToActiveBoard"
      >
        {{ $t('RAMON.FUNIL.BOARDS.SAVE_TO_BOARD') }}
      </button>
    </div>
    <div
      v-show="open"
      data-testid="board-dropdown"
      class="absolute top-full left-0 z-50 mt-2 w-80 p-2 rounded-xl bg-n-solid-2 border border-n-weak shadow-lg"
    >
      <p
        class="mb-1.5 px-2 pt-1 text-[10px] font-semibold tracking-[0.14em] uppercase text-n-slate-9"
      >
        {{ $t('RAMON.FUNIL.BOARDS.TITLE') }}
      </p>
      <div class="flex flex-col gap-0.5">
        <button
          data-testid="board-item-all"
          class="flex items-center gap-2 px-2 py-1.5 text-sm text-left rounded-lg"
          :class="
            activeBoard
              ? 'text-n-slate-11 hover:bg-n-alpha-2'
              : 'bg-n-alpha-2 text-n-slate-12 font-medium'
          "
          @click="applyBoard(null)"
        >
          <span class="size-2 rounded-sm shrink-0 bg-n-slate-9" />
          <span class="flex-1 truncate">
            {{ $t('RAMON.FUNIL.BOARDS.ALL') }}
          </span>
          <span class="text-xs text-n-slate-10">{{ leads.length }}</span>
        </button>
        <div
          v-for="board in boards"
          :key="board.id"
          class="flex items-center gap-1 group"
        >
          <button
            data-testid="board-item"
            class="flex items-center flex-1 min-w-0 gap-2 px-2 py-1.5 text-sm text-left rounded-lg"
            :class="
              board.id === activeBoardId
                ? 'bg-n-alpha-2 text-n-slate-12 font-medium'
                : 'text-n-slate-11 hover:bg-n-alpha-2'
            "
            @click="applyBoard(board)"
          >
            <span
              class="size-2 rounded-sm shrink-0"
              :style="{ backgroundColor: board.color }"
            />
            <span class="flex-1 truncate">{{ board.name }}</span>
            <span
              data-testid="board-count"
              class="text-xs"
              :class="
                board.id === activeBoardId
                  ? 'text-n-iris-11'
                  : 'text-n-slate-10'
              "
            >
              {{ countFor(board.filters) }}
            </span>
          </button>
          <button
            data-testid="board-rename"
            class="hidden group-hover:flex items-center p-1 rounded text-n-slate-10 hover:text-n-slate-12"
            :aria-label="$t('RAMON.FUNIL.BOARDS.RENAME')"
            :title="$t('RAMON.FUNIL.BOARDS.RENAME')"
            @click="boardToRename = board"
          >
            <span class="i-lucide-pencil size-3.5" />
          </button>
          <button
            data-testid="board-remove"
            class="hidden group-hover:flex items-center p-1 rounded text-n-slate-10 hover:text-n-ruby-11"
            :aria-label="$t('RAMON.FUNIL.BOARDS.DELETE')"
            :title="$t('RAMON.FUNIL.BOARDS.DELETE')"
            @click="boardToRemove = board"
          >
            <span class="i-lucide-trash-2 size-3.5" />
          </button>
        </div>
      </div>
      <button
        data-testid="board-new"
        class="w-full mt-1.5 px-2 py-1.5 text-xs text-left rounded-lg border-t border-n-weak text-n-iris-11 hover:bg-n-alpha-2"
        @click="
          newModalOpen = true;
          close();
        "
      >
        + {{ $t('RAMON.FUNIL.BOARDS.NEW') }}
      </button>
    </div>
    <NamePromptModal
      v-if="newModalOpen"
      :title="t('RAMON.FUNIL.BOARDS.NEW_PROMPT')"
      :placeholder="t('RAMON.FUNIL.BOARDS.NEW_PROMPT')"
      :confirm-label="t('RAMON.FUNIL.BOARDS.CREATE')"
      @confirm="confirmNewBoard"
      @cancel="newModalOpen = false"
    />
    <NamePromptModal
      v-if="boardToRename"
      :title="t('RAMON.FUNIL.BOARDS.RENAME_PROMPT')"
      :placeholder="boardToRename.name"
      :confirm-label="t('RAMON.FUNIL.BOARDS.RENAME')"
      @confirm="confirmRename"
      @cancel="boardToRename = null"
    />
    <ConfirmModal
      v-if="boardToRemove"
      :title="t('RAMON.FUNIL.BOARDS.DELETE_CONFIRM')"
      :confirm-label="t('RAMON.FUNIL.BOARDS.DELETE')"
      @confirm="confirmRemove"
      @cancel="boardToRemove = null"
    />
  </div>
</template>
