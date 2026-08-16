<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

// "Hoje na agenda" (mock 3c): reuniões do dia vindas do payload do Cockpit.
const props = defineProps({
  items: { type: Array, default: () => [] },
});
const emit = defineEmits(['select', 'viewWeek']);

const { t } = useI18n();

const fmtTime = iso =>
  new Intl.DateTimeFormat('pt-BR', {
    hour: '2-digit',
    minute: '2-digit',
  }).format(new Date(iso));

// A PRÓXIMA reunião futura ganha o bloco de hora bronze; as demais, cinza.
const nextId = computed(() => {
  const now = Date.now();
  const next = props.items.find(item => new Date(item.due_at).getTime() >= now);
  return next ? next.id : null;
});

const metaLine = item =>
  [item.title, item.user_name, item.source].filter(Boolean).join(' · ');
</script>

<template>
  <div
    data-testid="agenda-today"
    class="flex flex-col p-3.5 rounded-[14px] border border-n-weak bg-n-solid-2"
  >
    <template v-if="items.length">
      <button
        v-for="(item, index) in items"
        :key="item.id"
        type="button"
        data-testid="agenda-item"
        class="flex items-start w-full gap-3 px-1 py-2.5 text-left rounded-lg hover:bg-n-alpha-2"
        :class="index > 0 ? 'border-t border-n-weak' : ''"
        @click="emit('select', item.lead_id)"
      >
        <span
          class="flex-none w-[52px] py-1 text-center rounded-lg"
          :class="item.id === nextId ? 'bg-n-iris-3' : 'bg-n-alpha-2'"
        >
          <span
            class="block text-sm font-semibold tabular-nums"
            :class="item.id === nextId ? 'text-n-iris-11' : 'text-n-slate-11'"
          >
            {{ fmtTime(item.due_at) }}
          </span>
        </span>
        <span class="flex-1 min-w-0">
          <span
            class="block text-[13.5px] font-medium truncate text-n-slate-12"
          >
            {{ item.lead_name }}
          </span>
          <span class="block mt-0.5 text-[11px] truncate text-n-slate-10">
            {{ metaLine(item) }}
          </span>
        </span>
      </button>
      <button
        type="button"
        data-testid="agenda-view-week"
        class="pt-2 mt-1 text-[11px] text-center text-n-iris-11 border-t border-n-weak hover:underline"
        @click="emit('viewWeek')"
      >
        {{ t('RAMON.COMMAND.AGENDA.VIEW_WEEK') }}
      </button>
    </template>
    <p v-else data-testid="agenda-empty" class="text-xs text-n-slate-10">
      {{ t('RAMON.COMMAND.AGENDA.EMPTY') }}
    </p>
  </div>
</template>
