<script setup>
import { ref, computed, nextTick, watch, onBeforeUnmount } from 'vue';
import { vOnClickOutside } from '@vueuse/components';
import { DEFAULT_STAGE_COLOR } from '../../helpers/stage';

const props = defineProps({
  stage: { type: Object, required: true },
});
const emit = defineEmits(['rename', 'recolor', 'setType', 'remove']);

// Paleta fixa (mesma das Labels do Chatwoot) + o fallback padrão de etapa.
const PALETTE = [
  '#6b7280',
  '#3b82f6',
  '#8b5cf6',
  '#06b6d4',
  '#f59e0b',
  '#ef4444',
  '#22c55e',
  DEFAULT_STAGE_COLOR,
  '#ec4899',
  '#14b8a6',
];

const open = ref(false);
const toggleRef = ref(null);
const renameInput = ref(null);
const editingName = ref('');
const renaming = ref(false);

// O menu é teleportado pro body com position:fixed — a coluna tem
// overflow-hidden e cortaria um dropdown absolute (mesmo padrão do TaskBellMenu).
const MENU_WIDTH = 192; // w-48
const MENU_HEIGHT = 320; // estimativa p/ decidir abrir pra cima
const pos = ref({ top: 0, left: 0 });

const close = () => {
  open.value = false;
  renaming.value = false;
};

// Esc fecha o menu (e cancela um rename em andamento).
const onDocKeydown = e => {
  if (e.key === 'Escape') close();
};
// Qualquer scroll (coluna, board, página) desalinha o menu fixo → fecha.
const onAnyScroll = () => close();

const bindGlobal = () => {
  document.addEventListener('keydown', onDocKeydown);
  document.addEventListener('scroll', onAnyScroll, true);
  window.addEventListener('resize', onAnyScroll);
};
const unbindGlobal = () => {
  document.removeEventListener('keydown', onDocKeydown);
  document.removeEventListener('scroll', onAnyScroll, true);
  window.removeEventListener('resize', onAnyScroll);
};

const toggle = () => {
  if (open.value) {
    close();
    return;
  }
  const rect = toggleRef.value.getBoundingClientRect();
  let top = rect.bottom + 4;
  if (top + MENU_HEIGHT > window.innerHeight) {
    top = Math.max(8, rect.top - 4 - MENU_HEIGHT);
  }
  const left = Math.max(8, rect.right - MENU_WIDTH);
  pos.value = { top, left };
  open.value = true;
};

// listeners globais acompanham o estado aberto/fechado
watch(open, isOpen => {
  if (isOpen) bindGlobal();
  else unbindGlobal();
});
onBeforeUnmount(unbindGlobal);

const currentColor = computed(() => props.stage.color || DEFAULT_STAGE_COLOR);
const currentType = computed(() => {
  if (props.stage.is_won) return 'won';
  if (props.stage.is_lost) return 'lost';
  return 'normal';
});

const startRename = () => {
  editingName.value = props.stage.name;
  renaming.value = true;
  nextTick(() => renameInput.value?.focus());
};
const confirmRename = () => {
  const name = editingName.value.trim();
  if (name && name !== props.stage.name) emit('rename', name);
  close();
};
const pickColor = color => {
  emit('recolor', color);
  close();
};
const setType = type => {
  emit('setType', type);
  close();
};
const remove = () => {
  emit('remove', props.stage);
  close();
};
</script>

<template>
  <div class="relative">
    <button
      ref="toggleRef"
      data-testid="stage-menu-toggle"
      :title="$t('RAMON.FUNIL.STAGE.MENU')"
      class="text-n-slate-9 hover:text-n-slate-12"
      @click="toggle"
    >
      <span class="i-lucide-ellipsis-vertical size-4" />
    </button>
    <Teleport to="body">
      <div
        v-if="open"
        v-on-click-outside="[close, { ignore: [toggleRef] }]"
        data-testid="stage-menu"
        class="fixed z-50 w-48 p-2 rounded-lg shadow-lg bg-n-solid-2 border border-n-weak"
        :style="{ top: `${pos.top}px`, left: `${pos.left}px` }"
      >
        <template v-if="renaming">
          <input
            ref="renameInput"
            v-model="editingName"
            data-testid="stage-rename-input"
            class="w-full px-2 py-1 mb-2 text-sm rounded-lg bg-n-alpha-2 text-n-slate-12 border border-transparent focus:border-n-slate-8 outline-none"
            @keyup.enter="confirmRename"
          />
          <button
            data-testid="stage-rename-confirm"
            class="w-full px-2 py-1 text-sm rounded-lg bg-n-iris-9 text-white hover:bg-n-iris-10"
            @click="confirmRename"
          >
            {{ $t('RAMON.FUNIL.STAGE.SAVE') }}
          </button>
        </template>
        <template v-else>
          <button
            data-testid="stage-rename"
            class="block w-full px-2 py-1 text-sm text-left rounded-lg text-n-slate-11 hover:bg-n-alpha-2"
            @click="startRename"
          >
            {{ $t('RAMON.FUNIL.STAGE.RENAME') }}
          </button>
          <div class="flex flex-wrap gap-1 px-2 py-2">
            <button
              v-for="color in PALETTE"
              :key="color"
              data-testid="stage-color"
              :title="color"
              class="rounded-full size-5 border border-n-weak"
              :class="{ 'ring-2 ring-n-slate-8': color === currentColor }"
              :style="{ backgroundColor: color }"
              @click="pickColor(color)"
            />
          </div>
          <button
            data-testid="stage-type-normal"
            class="flex items-center justify-between w-full px-2 py-1 text-sm text-left rounded-lg text-n-slate-11 hover:bg-n-alpha-2"
            @click="setType('normal')"
          >
            {{ $t('RAMON.FUNIL.STAGE.TYPE_NORMAL') }}
            <span
              v-if="currentType === 'normal'"
              class="i-lucide-check size-3.5"
            />
          </button>
          <button
            data-testid="stage-type-won"
            class="flex items-center justify-between w-full px-2 py-1 text-sm text-left rounded-lg text-n-slate-11 hover:bg-n-alpha-2"
            @click="setType('won')"
          >
            {{ $t('RAMON.FUNIL.STAGE.TYPE_WON') }}
            <span
              v-if="currentType === 'won'"
              class="i-lucide-check size-3.5"
            />
          </button>
          <button
            data-testid="stage-type-lost"
            class="flex items-center justify-between w-full px-2 py-1 text-sm text-left rounded-lg text-n-slate-11 hover:bg-n-alpha-2"
            @click="setType('lost')"
          >
            {{ $t('RAMON.FUNIL.STAGE.TYPE_LOST') }}
            <span
              v-if="currentType === 'lost'"
              class="i-lucide-check size-3.5"
            />
          </button>
          <button
            data-testid="stage-remove"
            class="block w-full px-2 py-1 text-sm text-left rounded-lg text-n-ruby-11 hover:bg-n-alpha-2"
            @click="remove"
          >
            {{ $t('RAMON.FUNIL.STAGE.REMOVE') }}
          </button>
        </template>
      </div>
    </Teleport>
  </div>
</template>
