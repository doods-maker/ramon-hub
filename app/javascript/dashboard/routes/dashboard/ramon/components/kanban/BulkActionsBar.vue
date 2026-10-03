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
import Button from 'dashboard/components-next/button/Button.vue';
import { DEFAULT_STAGE_COLOR } from '../../helpers/stage';
import { CARTAO, CAMPO, LINHA, MENU } from '../../helpers/ui';
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
// Papéis (playbook §13): só o gestor troca o SDR em lote.
const isAdmin = computed(
  () => getters.getCurrentRole?.value === 'administrator'
);
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
    class="flex flex-none flex-wrap items-center gap-2 mx-4 mb-3 shadow-lg"
    :class="CARTAO"
  >
    <span
      data-testid="bulk-count"
      class="text-sm font-semibold text-n-slate-12"
    >
      {{ $t('RAMON.KANBAN.BULK.SELECTED', { count: selectedIds.length }) }}
    </span>
    <span class="w-px h-4 bg-n-weak" />
    <div class="relative">
      <Button
        data-testid="bulk-move-stage"
        xs
        faded
        :label="$t('RAMON.KANBAN.BULK.MOVE')"
        @click="toggleMenu('stage')"
      />
      <div
        v-show="openMenu === 'stage'"
        data-testid="bulk-stage-menu"
        class="absolute bottom-full left-0 z-50 mb-2 w-56 max-h-64 overflow-y-auto"
        :class="MENU"
      >
        <button
          v-for="stage in stages"
          :key="stage.id"
          data-testid="bulk-stage-option"
          class="flex items-center gap-2 text-n-slate-12"
          :class="LINHA"
          @click="pickStage(stage)"
        >
          <span
            class="rounded-full size-2 shrink-0"
            :style="{ backgroundColor: stage.color || DEFAULT_STAGE_COLOR }"
          />
          <span class="truncate">{{ stage.name }}</span>
        </button>
      </div>
    </div>
    <div v-if="isAdmin" class="relative">
      <Button
        data-testid="bulk-assign-sdr"
        xs
        faded
        slate
        :label="$t('RAMON.KANBAN.BULK.ASSIGN')"
        @click="toggleMenu('sdr')"
      />
      <div
        v-show="openMenu === 'sdr'"
        data-testid="bulk-sdr-menu"
        class="absolute bottom-full left-0 z-50 mb-2 w-56 max-h-64 overflow-y-auto"
        :class="MENU"
      >
        <button
          v-for="agent in agents"
          :key="agent.id"
          data-testid="bulk-sdr-option"
          class="block truncate text-n-slate-12"
          :class="LINHA"
          @click="pickAgent(agent)"
        >
          {{ agent.name }}
        </button>
      </div>
    </div>
    <div class="relative">
      <Button
        data-testid="bulk-follow-up"
        xs
        faded
        slate
        :label="$t('RAMON.KANBAN.BULK.FOLLOW_UP')"
        @click="toggleMenu('task')"
      />
      <div
        v-show="openMenu === 'task'"
        data-testid="bulk-task-menu"
        class="absolute bottom-full left-0 z-50 mb-2 w-56 flex flex-col gap-1.5"
        :class="MENU"
      >
        <input
          v-model="followUpDate"
          data-testid="bulk-task-date"
          type="datetime-local"
          class="font-mono"
          :class="CAMPO"
        />
        <Button
          data-testid="bulk-task-confirm"
          sm
          class="w-full"
          :label="$t('RAMON.KANBAN.BULK.FOLLOW_UP_CONFIRM')"
          :disabled="!followUpDate"
          @click="confirmFollowUp"
        />
      </div>
    </div>
    <Button
      data-testid="bulk-clear"
      xs
      ghost
      slate
      :label="$t('RAMON.KANBAN.BULK.CLEAR')"
      @click="clearSelection"
    />
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
