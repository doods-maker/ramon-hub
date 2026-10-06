<script setup>
import { ref, computed, nextTick, watch, onBeforeUnmount } from 'vue';
import { vOnClickOutside } from '@vueuse/components';
import { DEFAULT_STAGE_COLOR } from '../../helpers/stage';
import Button from 'dashboard/components-next/button/Button.vue';
import { CAMPO, LINHA, MENU } from '../../helpers/ui';

const props = defineProps({
  stage: { type: Object, required: true },
});
const emit = defineEmits(['rename', 'recolor', 'setType', 'remove']);

// Paleta fixa (mesma das Labels do Chatwoot) + o fallback padrão de etapa.
// Fica em hex de propósito: a cor escolhida é DADO salvo na etapa (banco) e
// pinta a pílula via --stage — não é token de tema.
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
    <!-- ref no wrapper: o Button é componente, o clique-fora precisa de elemento -->
    <span ref="toggleRef" class="inline-flex">
      <Button
        data-testid="stage-menu-toggle"
        :title="$t('RAMON.FUNIL.STAGE.MENU')"
        xs
        ghost
        slate
        icon="i-lucide-ellipsis-vertical"
        @click="toggle"
      />
    </span>
    <Teleport to="body">
      <div
        v-if="open"
        v-on-click-outside="[close, { ignore: [toggleRef] }]"
        data-testid="stage-menu"
        class="fixed z-50 w-48"
        :class="MENU"
        :style="{ top: `${pos.top}px`, left: `${pos.left}px` }"
      >
        <template v-if="renaming">
          <input
            ref="renameInput"
            v-model="editingName"
            data-testid="stage-rename-input"
            class="!mb-1.5"
            :class="CAMPO"
            @keyup.enter="confirmRename"
          />
          <Button
            data-testid="stage-rename-confirm"
            sm
            class="w-full"
            :label="$t('RAMON.FUNIL.STAGE.SAVE')"
            @click="confirmRename"
          />
        </template>
        <template v-else>
          <button
            data-testid="stage-rename"
            class="block text-n-slate-12"
            :class="LINHA"
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
              class="p-0 rounded-full size-5 border border-solid border-n-weak"
              :class="{
                'ring-2 ring-n-blue-9 ring-offset-1 ring-offset-n-solid-2':
                  color === currentColor,
              }"
              :style="{ backgroundColor: color }"
              @click="pickColor(color)"
            />
          </div>
          <button
            data-testid="stage-type-normal"
            class="flex items-center justify-between text-n-slate-12"
            :class="LINHA"
            @click="setType('normal')"
          >
            {{ $t('RAMON.FUNIL.STAGE.TYPE_NORMAL') }}
            <span
              v-if="currentType === 'normal'"
              class="i-lucide-check size-3.5 text-n-blue-11"
            />
          </button>
          <button
            data-testid="stage-type-won"
            class="flex items-center justify-between text-n-slate-12"
            :class="LINHA"
            @click="setType('won')"
          >
            {{ $t('RAMON.FUNIL.STAGE.TYPE_WON') }}
            <span
              v-if="currentType === 'won'"
              class="i-lucide-check size-3.5 text-n-blue-11"
            />
          </button>
          <button
            data-testid="stage-type-lost"
            class="flex items-center justify-between text-n-slate-12"
            :class="LINHA"
            @click="setType('lost')"
          >
            {{ $t('RAMON.FUNIL.STAGE.TYPE_LOST') }}
            <span
              v-if="currentType === 'lost'"
              class="i-lucide-check size-3.5 text-n-blue-11"
            />
          </button>
          <!-- etapa das automações (quiz, agendamento, contrato): o código a
               acha pelo label, então não pode sumir — o servidor também recusa -->
          <button
            data-testid="stage-remove"
            class="block text-n-ruby-11"
            :class="LINHA"
            :disabled="stage.automacao"
            @click="remove"
          >
            {{ $t('RAMON.FUNIL.STAGE.REMOVE') }}
          </button>
          <p
            v-if="stage.automacao"
            data-testid="stage-remove-locked"
            class="m-0 px-2 pb-1 text-[11px] leading-snug text-n-slate-10"
          >
            {{ $t('RAMON.FUNIL.STAGE.REMOVE_LOCKED') }}
          </p>
        </template>
      </div>
    </Teleport>
  </div>
</template>
