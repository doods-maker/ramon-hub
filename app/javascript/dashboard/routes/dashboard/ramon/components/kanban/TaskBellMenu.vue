<script setup>
import { ref, watch, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { vOnClickOutside } from '@vueuse/components';
import Button from 'dashboard/components-next/button/Button.vue';
import { BOTAO_COMPACTO, CAMPO, LINHA, MENU, SECAO } from '../../helpers/ui';

const props = defineProps({ label: { type: String, default: '' } });
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
    <!-- ref no wrapper: o Button é componente, o clique-fora precisa de elemento -->
    <span ref="bellRef" class="inline-flex">
      <Button
        data-testid="task-bell-toggle"
        :class="props.label ? BOTAO_COMPACTO : ''"
        :title="t('RAMON.KANBAN.BELL.TITLE')"
        xs
        :variant="props.label ? 'faded' : 'ghost'"
        color="slate"
        icon="i-lucide-bell-plus"
        :label="props.label"
        @click.stop="toggle"
      />
    </span>
    <Teleport to="body">
      <div
        v-if="open"
        v-on-click-outside="[close, { ignore: [bellRef] }]"
        data-testid="task-bell-menu"
        class="fixed z-50 w-56"
        :class="MENU"
        :style="{ top: `${pos.top}px`, left: `${pos.left}px` }"
        @click.stop
      >
        <input
          v-model="title"
          data-testid="task-bell-title"
          :placeholder="t('RAMON.KANBAN.BELL.TITLE_PLACEHOLDER')"
          class="!mb-1.5"
          :class="CAMPO"
          @click.stop
        />
        <button
          data-testid="task-bell-tomorrow"
          :class="LINHA"
          @click.stop="inDaysAt9(1)"
        >
          {{ t('RAMON.KANBAN.BELL.TOMORROW') }}
        </button>
        <button
          data-testid="task-bell-3-days"
          :class="LINHA"
          @click.stop="inDaysAt9(3)"
        >
          {{ t('RAMON.KANBAN.BELL.IN_3_DAYS') }}
        </button>
        <button
          data-testid="task-bell-1-week"
          :class="LINHA"
          @click.stop="inDaysAt9(7)"
        >
          {{ t('RAMON.KANBAN.BELL.IN_1_WEEK') }}
        </button>
        <div class="flex flex-col gap-1.5 mt-1.5 !pt-1.5" :class="SECAO">
          <input
            v-model="customDate"
            data-testid="task-bell-date"
            type="datetime-local"
            :min="minDate"
            class="font-mono"
            :class="CAMPO"
            @click.stop
          />
          <Button
            data-testid="task-bell-confirm"
            sm
            class="w-full"
            :label="t('RAMON.KANBAN.BELL.CONFIRM')"
            :disabled="!customDate"
            @click.stop="confirmCustom"
          />
        </div>
      </div>
    </Teleport>
  </div>
</template>
