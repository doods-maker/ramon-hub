<script setup>
import { ref, watch, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { vOnClickOutside } from '@vueuse/components';

const emit = defineEmits(['schedule']);
const { t } = useI18n();

const open = ref(false);
const bellRef = ref(null);
const title = ref('');
const customDate = ref('');

// O menu é teleportado pro body com position:fixed — a lista de cards da
// coluna tem overflow-y-auto e cortaria um dropdown absolute dentro do card.
const MENU_WIDTH = 224; // w-56
const MENU_HEIGHT = 300; // estimativa p/ decidir abrir pra cima
const pos = ref({ top: 0, left: 0 });

// Piso do datetime-local: agora, em horário local (YYYY-MM-DDTHH:mm) —
// não faz sentido agendar follow-up no passado. Recalculado a cada abertura.
const localNow = () =>
  new Date(Date.now() - new Date().getTimezoneOffset() * 60000)
    .toISOString()
    .slice(0, 16);
const minDate = ref(localNow());

const close = () => {
  open.value = false;
  title.value = '';
  customDate.value = '';
};

const onDocKeydown = e => {
  if (e.key === 'Escape') close();
};
// Qualquer scroll (coluna, board, página) desalinha o menu fixo → fecha.
const onAnyScroll = () => close();

const bindGlobal = () => {
  document.addEventListener('keydown', onDocKeydown);
  document.addEventListener('scroll', onAnyScroll, true);
};
const unbindGlobal = () => {
  document.removeEventListener('keydown', onDocKeydown);
  document.removeEventListener('scroll', onAnyScroll, true);
};

const toggle = () => {
  if (open.value) {
    close();
    return;
  }
  const rect = bellRef.value.getBoundingClientRect();
  let top = rect.bottom + 4;
  if (top + MENU_HEIGHT > window.innerHeight) {
    top = Math.max(8, rect.top - 4 - MENU_HEIGHT);
  }
  const left = Math.max(8, rect.right - MENU_WIDTH);
  pos.value = { top, left };
  minDate.value = localNow();
  open.value = true;
};

// listeners globais acompanham o estado aberto/fechado
watch(open, isOpen => {
  if (isOpen) bindGlobal();
  else unbindGlobal();
});
onBeforeUnmount(unbindGlobal);

// título opcional; sem texto → default i18n "Follow-up"
const resolvedTitle = () =>
  title.value.trim() || t('RAMON.KANBAN.BELL.DEFAULT_TITLE');

// dueAt sempre ISO (UTC) a partir de um Date local.
const emitSchedule = date => {
  emit('schedule', { dueAt: date.toISOString(), title: resolvedTitle() });
  close();
};

// presets ancorados às 9h locais.
const inDaysAt9 = days => {
  const d = new Date();
  d.setDate(d.getDate() + days);
  d.setHours(9, 0, 0, 0);
  emitSchedule(d);
};
const confirmCustom = () => {
  if (!customDate.value) return;
  emitSchedule(new Date(customDate.value));
};
</script>

<template>
  <div class="relative" @click.stop>
    <button
      ref="bellRef"
      data-testid="task-bell-toggle"
      :title="t('RAMON.KANBAN.BELL.TITLE')"
      class="flex items-center justify-center size-6 rounded-full text-n-slate-9 hover:text-n-iris-11 hover:bg-n-alpha-2"
      @click.stop="toggle"
    >
      <span class="i-lucide-bell-plus size-4" />
    </button>
    <Teleport to="body">
      <div
        v-if="open"
        v-on-click-outside="[close, { ignore: [bellRef] }]"
        data-testid="task-bell-menu"
        class="fixed z-50 w-56 p-2 rounded-lg shadow-lg bg-n-solid-2 border border-n-weak"
        :style="{ top: `${pos.top}px`, left: `${pos.left}px` }"
        @click.stop
      >
        <input
          v-model="title"
          data-testid="task-bell-title"
          :placeholder="t('RAMON.KANBAN.BELL.TITLE_PLACEHOLDER')"
          class="w-full px-2 py-1 mb-2 text-sm rounded-lg bg-n-alpha-2 text-n-slate-12 border border-transparent focus:border-n-slate-8 outline-none"
          @click.stop
        />
        <button
          data-testid="task-bell-tomorrow"
          class="block w-full px-2 py-1 text-sm text-left rounded-lg text-n-slate-11 hover:bg-n-alpha-2"
          @click.stop="inDaysAt9(1)"
        >
          {{ t('RAMON.KANBAN.BELL.TOMORROW') }}
        </button>
        <button
          data-testid="task-bell-3-days"
          class="block w-full px-2 py-1 text-sm text-left rounded-lg text-n-slate-11 hover:bg-n-alpha-2"
          @click.stop="inDaysAt9(3)"
        >
          {{ t('RAMON.KANBAN.BELL.IN_3_DAYS') }}
        </button>
        <button
          data-testid="task-bell-1-week"
          class="block w-full px-2 py-1 text-sm text-left rounded-lg text-n-slate-11 hover:bg-n-alpha-2"
          @click.stop="inDaysAt9(7)"
        >
          {{ t('RAMON.KANBAN.BELL.IN_1_WEEK') }}
        </button>
        <div class="flex flex-col gap-1 pt-2 mt-1 border-t border-n-weak">
          <input
            v-model="customDate"
            data-testid="task-bell-date"
            type="datetime-local"
            :min="minDate"
            class="w-full px-2 py-1 text-sm rounded-lg bg-n-alpha-2 text-n-slate-12 border border-transparent focus:border-n-slate-8 outline-none"
            @click.stop
          />
          <button
            data-testid="task-bell-confirm"
            class="w-full px-2 py-1 text-sm rounded-lg bg-n-iris-9 text-white hover:bg-n-iris-10 disabled:opacity-50"
            :disabled="!customDate"
            @click.stop="confirmCustom"
          >
            {{ t('RAMON.KANBAN.BELL.CONFIRM') }}
          </button>
        </div>
      </div>
    </Teleport>
  </div>
</template>
