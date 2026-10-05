<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { CARTAO, LINHA, TOM } from '../../helpers/ui';

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

// A PRÓXIMA reunião futura ganha o bloco de hora azul; as demais, cinza.
const nextId = computed(() => {
  const now = Date.now();
  const next = props.items.find(item => new Date(item.due_at).getTime() >= now);
  return next ? next.id : null;
});

const metaLine = item =>
  [item.title, item.user_name, item.source].filter(Boolean).join(' · ');
</script>

<template>
  <div data-testid="agenda-today" :class="CARTAO" class="flex flex-col">
    <template v-if="items.length">
      <button
        v-for="(item, index) in items"
        :key="item.id"
        type="button"
        data-testid="agenda-item"
        :class="[
          LINHA,
          index > 0 ? 'border-t border-n-weak !rounded-none' : '',
        ]"
        class="flex items-start gap-3 !py-2.5"
        @click="emit('select', item.lead_id)"
      >
        <span
          class="flex-none w-[52px] py-1 text-center rounded-lg font-mono text-sm font-medium tabular-nums"
          :class="item.id === nextId ? TOM.blue : TOM.slate"
        >
          {{ fmtTime(item.due_at) }}
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
      <div class="flex justify-center pt-2 mt-1 border-t border-n-weak">
        <Button
          data-testid="agenda-view-week"
          link
          xs
          :label="t('RAMON.COMMAND.AGENDA.VIEW_WEEK')"
          @click="emit('viewWeek')"
        />
      </div>
    </template>
    <p v-else data-testid="agenda-empty" class="text-xs text-n-slate-10">
      {{ t('RAMON.COMMAND.AGENDA.EMPTY') }}
    </p>
  </div>
</template>
