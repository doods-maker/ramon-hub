<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { CARTAO, CHIP, LINHA, TOM } from '../../helpers/ui';

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

// A PRÓXIMA reunião futura (aberta) ganha o bloco de hora azul; as demais,
// cinza. Feita vem apagada com check; vencida (dias anteriores) fica no topo.
const nextId = computed(() => {
  const now = Date.now();
  const next = props.items.find(
    item => !item.completed_at && new Date(item.due_at).getTime() >= now
  );
  return next ? next.id : null;
});

const fmtDay = iso =>
  new Intl.DateTimeFormat('pt-BR', { day: '2-digit', month: '2-digit' }).format(
    new Date(iso)
  );

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
          index > 0 ? 'border-t border-solid border-n-weak !rounded-none' : '',
          { 'opacity-60': item.completed_at },
        ]"
        class="flex items-start gap-3 !py-2.5"
        @click="emit('select', item.lead_id)"
      >
        <span
          class="flex-none min-w-[52px] px-1 py-1 text-center rounded-lg font-mono text-sm font-medium tabular-nums"
          :class="item.id === nextId ? TOM.blue : TOM.slate"
        >
          <span
            v-if="item.completed_at"
            data-testid="agenda-item-done"
            class="i-lucide-check inline-block size-3 align-[-1px]"
          />
          {{ fmtTime(item.due_at) }}
        </span>
        <span class="flex-1 min-w-0">
          <span class="flex items-center gap-1.5 min-w-0">
            <span class="text-[13.5px] font-medium truncate text-n-slate-12">
              {{ item.lead_name }}
            </span>
            <span
              v-if="item.vencida"
              data-testid="agenda-item-overdue"
              :class="[CHIP, TOM.ruby]"
              class="shrink-0"
            >
              {{
                t('RAMON.COMMAND.AGENDA.OVERDUE', { data: fmtDay(item.due_at) })
              }}
            </span>
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
