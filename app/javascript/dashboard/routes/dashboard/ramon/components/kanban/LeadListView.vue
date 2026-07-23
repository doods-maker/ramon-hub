<script setup>
// Visão Lista do Funil: tabela densa ordenável client-side. Linha clicável
// abre a gaveta; o checkbox por linha usa a MESMA seleção em lote do board.
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { formatBrl } from '../../helpers/currency';
import { DEFAULT_STAGE_COLOR } from '../../helpers/stage';

const props = defineProps({
  leads: { type: Array, default: () => [] },
  stages: { type: Array, default: () => [] },
  selectedLeadIds: { type: Array, default: () => [] },
});
const emit = defineEmits(['openLead', 'toggleSelect']);

const { t } = useI18n();

const stageById = computed(
  () => new Map(props.stages.map(stage => [stage.id, stage]))
);

const sortKey = ref('name');
const sortDir = ref(1);
const setSort = key => {
  if (sortKey.value === key) {
    sortDir.value *= -1;
  } else {
    sortKey.value = key;
    sortDir.value = 1;
  }
};

const sortValue = lead => {
  switch (sortKey.value) {
    case 'stage':
      return stageById.value.get(lead.lead_stage_id)?.name || '';
    case 'value':
      return Number(lead.value) || 0;
    case 'next':
      return lead.next_task_due_at || '9999';
    case 'sdr':
      return lead.sdr_name || '';
    case 'thesis':
      return lead.thesis_name || '';
    case 'phone':
      return lead.contact_phone || '';
    default:
      return lead.name || '';
  }
};

const sorted = computed(() =>
  [...props.leads].sort((a, b) => {
    const va = sortValue(a);
    const vb = sortValue(b);
    if (typeof va === 'number' && typeof vb === 'number')
      return (va - vb) * sortDir.value;
    return String(va).localeCompare(String(vb), 'pt-BR') * sortDir.value;
  })
);

// Próxima ação com a mesma semântica de cor do card: vencida ruby, hoje âmbar,
// futura teal — versão enxuta pra caber numa célula.
const nextAction = lead => {
  const raw = lead.next_task_due_at;
  if (!raw) return null;
  const due = new Date(raw);
  if (Number.isNaN(due.getTime())) return null;
  const title = lead.next_task_title || '';
  if (due.getTime() < Date.now())
    return {
      class: 'text-n-ruby-11',
      label: t('RAMON.KANBAN.CARD.NEXT_OVERDUE', { title }),
    };
  const startOfToday = new Date();
  startOfToday.setHours(0, 0, 0, 0);
  const days = Math.floor((due.getTime() - startOfToday.getTime()) / 86400000);
  if (days === 0)
    return {
      class: 'text-n-amber-11',
      label: t('RAMON.KANBAN.CARD.NEXT_TODAY', { title }),
    };
  if (days === 1)
    return {
      class: 'text-n-teal-11',
      label: t('RAMON.KANBAN.CARD.NEXT_TOMORROW', { title }),
    };
  return {
    class: 'text-n-teal-11',
    label: t('RAMON.KANBAN.CARD.NEXT_IN_DAYS', { days, title }),
  };
};

const columns = [
  { key: 'name', label: 'RAMON.KANBAN.LIST.NAME' },
  { key: 'stage', label: 'RAMON.KANBAN.LIST.STAGE' },
  { key: 'value', label: 'RAMON.KANBAN.LIST.VALUE' },
  { key: 'next', label: 'RAMON.KANBAN.LIST.NEXT' },
  { key: 'sdr', label: 'RAMON.KANBAN.LIST.SDR' },
  { key: 'thesis', label: 'RAMON.KANBAN.LIST.THESIS' },
  { key: 'phone', label: 'RAMON.KANBAN.LIST.PHONE' },
];
</script>

<template>
  <div class="flex-1 min-h-0 overflow-auto px-4 pb-4" data-testid="lead-list">
    <table class="w-full text-sm border-separate border-spacing-0">
      <thead>
        <tr>
          <th
            class="sticky top-0 z-10 w-8 px-2 py-2 bg-n-background border-b border-n-weak"
          />
          <th
            v-for="column in columns"
            :key="column.key"
            class="sticky top-0 z-10 px-2 py-2 text-left bg-n-background border-b border-n-weak"
          >
            <button
              :data-testid="`list-sort-${column.key}`"
              class="inline-flex items-center gap-1 text-xs font-semibold text-n-slate-10 hover:text-n-slate-12"
              @click="setSort(column.key)"
            >
              {{ $t(column.label) }}
              <span
                v-if="sortKey === column.key"
                class="size-3"
                :class="
                  sortDir === 1
                    ? 'i-lucide-chevron-up'
                    : 'i-lucide-chevron-down'
                "
              />
            </button>
          </th>
        </tr>
      </thead>
      <tbody>
        <tr
          v-for="lead in sorted"
          :key="lead.id"
          data-testid="list-row"
          class="cursor-pointer hover:bg-n-alpha-2"
          @click="emit('openLead', lead)"
        >
          <td class="px-2 py-1.5 border-b border-n-weak">
            <button
              data-testid="list-select-toggle"
              class="flex items-center justify-center size-3.5 rounded shrink-0 border-[1.5px] transition duration-150"
              :class="
                selectedLeadIds.includes(lead.id)
                  ? 'bg-n-iris-9 border-n-iris-9'
                  : 'border-n-slate-9'
              "
              @click.stop="emit('toggleSelect', lead)"
            >
              <span
                v-if="selectedLeadIds.includes(lead.id)"
                class="i-lucide-check size-2.5 text-white"
              />
            </button>
          </td>
          <td
            class="px-2 py-1.5 font-medium truncate max-w-56 border-b border-n-weak text-n-slate-12"
          >
            {{ lead.name }}
          </td>
          <td class="px-2 py-1.5 border-b border-n-weak">
            <span
              class="inline-flex items-center gap-1.5 px-2 py-0.5 text-xs rounded-full bg-n-alpha-2 text-n-slate-11 whitespace-nowrap"
            >
              <span
                class="rounded-full size-1.5 shrink-0"
                :style="{
                  backgroundColor:
                    stageById.get(lead.lead_stage_id)?.color ||
                    DEFAULT_STAGE_COLOR,
                }"
              />
              {{ stageById.get(lead.lead_stage_id)?.name || '—' }}
            </span>
          </td>
          <td
            data-testid="list-value"
            class="px-2 py-1.5 text-xs tabular-nums whitespace-nowrap border-b border-n-weak"
            :class="
              lead.value ? 'text-n-iris-11 font-medium' : 'text-n-slate-10'
            "
          >
            {{ lead.value ? formatBrl(lead.value) : '—' }}
          </td>
          <td
            class="px-2 py-1.5 text-xs truncate max-w-52 border-b border-n-weak"
          >
            <span v-if="nextAction(lead)" :class="nextAction(lead).class">
              {{ nextAction(lead).label }}
            </span>
            <span v-else class="text-n-slate-10">—</span>
          </td>
          <td
            class="px-2 py-1.5 text-xs truncate max-w-36 border-b border-n-weak text-n-slate-11"
          >
            {{ lead.sdr_name || '—' }}
          </td>
          <td
            class="px-2 py-1.5 text-xs truncate max-w-44 border-b border-n-weak text-n-slate-11"
          >
            {{ lead.thesis_name || '—' }}
          </td>
          <td
            class="px-2 py-1.5 text-xs tabular-nums whitespace-nowrap border-b border-n-weak text-n-slate-11"
          >
            {{ lead.contact_phone || '—' }}
          </td>
        </tr>
      </tbody>
    </table>
    <p
      v-if="!sorted.length"
      data-testid="list-empty"
      class="pt-6 text-xs text-center text-n-slate-9"
    >
      {{ $t('RAMON.KANBAN.LIST.EMPTY') }}
    </p>
  </div>
</template>
