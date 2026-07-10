<script setup>
import { ref, nextTick } from 'vue';
import { vOnClickOutside } from '@vueuse/components';

const props = defineProps({
  stage: { type: Object, required: true },
});
const emit = defineEmits(['rename', 'recolor', 'setType', 'remove']);

// Paleta fixa (mesma das Labels do Chatwoot).
const PALETTE = [
  '#6b7280',
  '#3b82f6',
  '#8b5cf6',
  '#06b6d4',
  '#f59e0b',
  '#ef4444',
  '#22c55e',
  '#71717a',
  '#ec4899',
  '#14b8a6',
];

const open = ref(false);
const toggleRef = ref(null);
const renameInput = ref(null);
const editingName = ref('');
const renaming = ref(false);

const close = () => {
  open.value = false;
  renaming.value = false;
};
const toggle = () => {
  if (open.value) close();
  else open.value = true;
};
const startRename = () => {
  editingName.value = props.stage.name;
  renaming.value = true;
  nextTick(() => renameInput.value?.focus());
};
const confirmRename = () => {
  const name = editingName.value.trim();
  if (name && name !== props.stage.name) emit('rename', name);
  renaming.value = false;
  open.value = false;
};
const pickColor = color => {
  emit('recolor', color);
  open.value = false;
};
const setType = type => {
  emit('setType', type);
  open.value = false;
};
const remove = () => {
  emit('remove', props.stage);
  open.value = false;
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
    <div
      v-if="open"
      v-on-click-outside="[close, { ignore: [toggleRef] }]"
      class="absolute right-0 z-10 mt-1 w-48 p-2 rounded-lg shadow-lg bg-n-solid-2 border border-n-weak"
    >
      <template v-if="renaming">
        <input
          ref="renameInput"
          v-model="editingName"
          data-testid="stage-rename-input"
          class="w-full px-2 py-1 mb-2 text-sm rounded bg-n-alpha-2 text-n-slate-12"
          @keyup.enter="confirmRename"
        />
        <button
          data-testid="stage-rename-confirm"
          class="w-full px-2 py-1 text-sm rounded bg-n-iris-9 text-white"
          @click="confirmRename"
        >
          {{ $t('RAMON.FUNIL.STAGE.SAVE') }}
        </button>
      </template>
      <template v-else>
        <button
          data-testid="stage-rename"
          class="block w-full px-2 py-1 text-sm text-left rounded text-n-slate-11 hover:bg-n-alpha-2"
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
            :style="{ backgroundColor: color }"
            @click="pickColor(color)"
          />
        </div>
        <button
          data-testid="stage-type-normal"
          class="block w-full px-2 py-1 text-sm text-left rounded text-n-slate-11 hover:bg-n-alpha-2"
          @click="setType('normal')"
        >
          {{ $t('RAMON.FUNIL.STAGE.TYPE_NORMAL') }}
        </button>
        <button
          data-testid="stage-type-won"
          class="block w-full px-2 py-1 text-sm text-left rounded text-n-slate-11 hover:bg-n-alpha-2"
          @click="setType('won')"
        >
          {{ $t('RAMON.FUNIL.STAGE.TYPE_WON') }}
        </button>
        <button
          data-testid="stage-type-lost"
          class="block w-full px-2 py-1 text-sm text-left rounded text-n-slate-11 hover:bg-n-alpha-2"
          @click="setType('lost')"
        >
          {{ $t('RAMON.FUNIL.STAGE.TYPE_LOST') }}
        </button>
        <button
          data-testid="stage-remove"
          class="block w-full px-2 py-1 text-sm text-left rounded text-n-ruby-11 hover:bg-n-alpha-2"
          @click="remove"
        >
          {{ $t('RAMON.FUNIL.STAGE.REMOVE') }}
        </button>
      </template>
    </div>
  </div>
</template>
