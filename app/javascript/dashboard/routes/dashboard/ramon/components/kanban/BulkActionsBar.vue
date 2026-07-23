<script setup>
// Barra de ações em lote (mock 1d): aparece quando há seleção, fixa embaixo do
// board. Mover p/ etapa de perda pede o motivo UMA vez (LostReasonModal) e
// aplica a todos; o resto vira um único POST bulk_actions → job no backend.
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { onKeyStroke } from '@vueuse/core';
import { vOnClickOutside } from '@vueuse/components';
import { useStore, useStoreGetters } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import LostReasonModal from './LostReasonModal.vue';

const props = defineProps({
  // Board com modal aberto: o Esc daqui fica mudo.
  suspendEsc: { type: Boolean, default: false },
});

const store = useStore();
const getters = useStoreGetters();
const { t } = useI18n();

const selectedIds = computed(() => getters['leads/getSelectedIds'].value);
const stages = computed(() => getters['leadConfig/getStages']?.value ?? []);
const lostReasons = computed(
  () => getters['leadConfig/getLostReasons']?.value ?? []
);
const agents = computed(() => getters['agents/getAgents']?.value ?? []);
const dockOpen = computed(() => !!getters['leads/getDockConversationId'].value);

// Um menu por vez: 'stage' | 'sdr' | 'task' | null. v-show mantém o estado.
const openMenu = ref(null);
const toggleMenu = name => {
  openMenu.value = openMenu.value === name ? null : name;
};
const closeMenus = () => {
  openMenu.value = null;
};

const followUpDate = ref('');

// Etapa de perda escolhida no lote: segura até o motivo ser informado.
const pendingLostStage = ref(null);

const runBulk = async payload => {
  closeMenus();
  try {
    await store.dispatch('leads/bulkAction', payload);
    useAlert(t('RAMON.KANBAN.BULK.QUEUED'));
    return true;
  } catch (e) {
    useAlert(t('RAMON.KANBAN.BULK.ERROR'));
    return false;
  }
};

const pickStage = stage => {
  if (stage.is_lost) {
    closeMenus();
    pendingLostStage.value = stage;
    return;
  }
  runBulk({ fields: { lead_stage_id: stage.id } });
};

const confirmLost = async ({ lostReason }) => {
  const ok = await runBulk({
    fields: {
      lead_stage_id: pendingLostStage.value.id,
      lost_reason: lostReason,
    },
  });
  if (ok) pendingLostStage.value = null;
};

const pickAgent = agent => runBulk({ fields: { sdr_id: agent.id } });

const confirmFollowUp = () => {
  if (!followUpDate.value) return;
  runBulk({
    task: {
      due_at: new Date(followUpDate.value).toISOString(),
      title: t('RAMON.KANBAN.BELL.DEFAULT_TITLE'),
    },
  });
  followUpDate.value = '';
};

const runTriage = () => runBulk({ triage: true });

const clearSelection = () => store.dispatch('leads/clearSelection');

// Esc: fecha menu aberto → senão limpa a seleção. Mudo com modal (do board ou
// o de perda daqui) e com o dock de conversa aberto (o Esc é dele).
onKeyStroke('Escape', () => {
  if (props.suspendEsc || pendingLostStage.value || dockOpen.value) return;
  if (openMenu.value) {
    closeMenus();
    return;
  }
  clearSelection();
});
</script>

<template>
  <div
    v-on-click-outside="closeMenus"
    data-testid="bulk-actions-bar"
    class="flex flex-none flex-wrap items-center gap-2 mx-4 mb-3 px-4 py-2.5 rounded-xl bg-n-solid-2 border border-n-iris-8 shadow-lg"
  >
    <span
      data-testid="bulk-count"
      class="text-sm font-semibold text-n-slate-12"
    >
      {{ $t('RAMON.KANBAN.BULK.SELECTED', { count: selectedIds.length }) }}
    </span>
    <span class="w-px h-4 bg-n-weak" />
    <div class="relative">
      <button
        data-testid="bulk-move-stage"
        class="px-3 py-1.5 text-xs rounded-lg bg-n-alpha-2 text-n-iris-11 hover:bg-n-alpha-3"
        @click="toggleMenu('stage')"
      >
        {{ $t('RAMON.KANBAN.BULK.MOVE') }}
      </button>
      <div
        v-show="openMenu === 'stage'"
        data-testid="bulk-stage-menu"
        class="absolute bottom-full left-0 z-50 mb-2 w-56 max-h-64 overflow-y-auto p-1 rounded-lg bg-n-solid-2 border border-n-weak shadow-lg"
      >
        <button
          v-for="stage in stages"
          :key="stage.id"
          data-testid="bulk-stage-option"
          class="flex items-center w-full gap-2 px-2 py-1.5 text-sm text-left rounded-md text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
          @click="pickStage(stage)"
        >
          <span
            class="rounded-full size-2 shrink-0"
            :style="{ backgroundColor: stage.color || '#8d867d' }"
          />
          <span class="truncate">{{ stage.name }}</span>
        </button>
      </div>
    </div>
    <div class="relative">
      <button
        data-testid="bulk-assign-sdr"
        class="px-3 py-1.5 text-xs rounded-lg bg-n-alpha-2 text-n-slate-11 hover:text-n-slate-12 hover:bg-n-alpha-3"
        @click="toggleMenu('sdr')"
      >
        {{ $t('RAMON.KANBAN.BULK.ASSIGN') }}
      </button>
      <div
        v-show="openMenu === 'sdr'"
        data-testid="bulk-sdr-menu"
        class="absolute bottom-full left-0 z-50 mb-2 w-56 max-h-64 overflow-y-auto p-1 rounded-lg bg-n-solid-2 border border-n-weak shadow-lg"
      >
        <button
          v-for="agent in agents"
          :key="agent.id"
          data-testid="bulk-sdr-option"
          class="block w-full px-2 py-1.5 text-sm text-left truncate rounded-md text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
          @click="pickAgent(agent)"
        >
          {{ agent.name }}
        </button>
      </div>
    </div>
    <div class="relative">
      <button
        data-testid="bulk-follow-up"
        class="px-3 py-1.5 text-xs rounded-lg bg-n-alpha-2 text-n-slate-11 hover:text-n-slate-12 hover:bg-n-alpha-3"
        @click="toggleMenu('task')"
      >
        {{ $t('RAMON.KANBAN.BULK.FOLLOW_UP') }}
      </button>
      <div
        v-show="openMenu === 'task'"
        data-testid="bulk-task-menu"
        class="absolute bottom-full left-0 z-50 mb-2 w-56 p-2 flex flex-col gap-1.5 rounded-lg bg-n-solid-2 border border-n-weak shadow-lg"
      >
        <input
          v-model="followUpDate"
          data-testid="bulk-task-date"
          type="datetime-local"
          class="w-full px-2 py-1 text-sm rounded-lg bg-n-alpha-2 text-n-slate-12 border border-transparent focus:border-n-slate-8 outline-none"
        />
        <button
          data-testid="bulk-task-confirm"
          class="w-full px-2 py-1 text-sm rounded-lg bg-n-iris-9 text-white hover:bg-n-iris-10 disabled:opacity-50"
          :disabled="!followUpDate"
          @click="confirmFollowUp"
        >
          {{ $t('RAMON.KANBAN.BULK.FOLLOW_UP_CONFIRM') }}
        </button>
      </div>
    </div>
    <button
      data-testid="bulk-triage"
      class="px-3 py-1.5 text-xs rounded-lg bg-n-alpha-2 text-n-slate-11 hover:text-n-slate-12 hover:bg-n-alpha-3"
      @click="runTriage"
    >
      {{ $t('RAMON.KANBAN.BULK.TRIAGE') }}
    </button>
    <button
      data-testid="bulk-clear"
      class="px-3 py-1.5 text-xs rounded-lg text-n-slate-10 hover:text-n-slate-12"
      @click="clearSelection"
    >
      {{ $t('RAMON.KANBAN.BULK.CLEAR') }}
    </button>
    <span class="ms-auto text-[11px] text-n-slate-10">
      {{ $t('RAMON.KANBAN.BULK.ESC_HINT') }}
    </span>
    <Transition
      enter-active-class="transition-opacity duration-150"
      leave-active-class="transition-opacity duration-150"
      enter-from-class="opacity-0"
      leave-to-class="opacity-0"
    >
      <LostReasonModal
        v-if="pendingLostStage"
        :lost-reasons="lostReasons"
        @confirm-move="confirmLost"
        @cancel-move="pendingLostStage = null"
      />
    </Transition>
  </div>
</template>
