<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { vOnClickOutside } from '@vueuse/components';

const emit = defineEmits(['schedule']);
const { t } = useI18n();

const open = ref(false);
const bellRef = ref(null);
const title = ref('');
const customDate = ref('');

const close = () => {
  open.value = false;
  title.value = '';
  customDate.value = '';
};
const toggle = () => {
  if (open.value) close();
  else open.value = true;
};

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
    <div
      v-if="open"
      v-on-click-outside="[close, { ignore: [bellRef] }]"
      data-testid="task-bell-menu"
      class="absolute right-0 z-20 mt-1 w-56 p-2 rounded-lg shadow-lg bg-n-solid-2 border border-n-weak"
    >
      <input
        v-model="title"
        data-testid="task-bell-title"
        :placeholder="t('RAMON.KANBAN.BELL.TITLE_PLACEHOLDER')"
        class="w-full px-2 py-1 mb-2 text-sm rounded bg-n-alpha-2 text-n-slate-12"
        @click.stop
      />
      <button
        data-testid="task-bell-tomorrow"
        class="block w-full px-2 py-1 text-sm text-left rounded text-n-slate-11 hover:bg-n-alpha-2"
        @click.stop="inDaysAt9(1)"
      >
        {{ t('RAMON.KANBAN.BELL.TOMORROW') }}
      </button>
      <button
        data-testid="task-bell-3-days"
        class="block w-full px-2 py-1 text-sm text-left rounded text-n-slate-11 hover:bg-n-alpha-2"
        @click.stop="inDaysAt9(3)"
      >
        {{ t('RAMON.KANBAN.BELL.IN_3_DAYS') }}
      </button>
      <button
        data-testid="task-bell-1-week"
        class="block w-full px-2 py-1 text-sm text-left rounded text-n-slate-11 hover:bg-n-alpha-2"
        @click.stop="inDaysAt9(7)"
      >
        {{ t('RAMON.KANBAN.BELL.IN_1_WEEK') }}
      </button>
      <div class="flex flex-col gap-1 pt-2 mt-1 border-t border-n-weak">
        <input
          v-model="customDate"
          data-testid="task-bell-date"
          type="datetime-local"
          class="w-full px-2 py-1 text-sm rounded bg-n-alpha-2 text-n-slate-12"
          @click.stop
        />
        <button
          data-testid="task-bell-confirm"
          class="w-full px-2 py-1 text-sm rounded bg-n-iris-9 text-white disabled:opacity-50"
          :disabled="!customDate"
          @click.stop="confirmCustom"
        >
          {{ t('RAMON.KANBAN.BELL.CONFIRM') }}
        </button>
      </div>
    </div>
  </div>
</template>
