<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

// "Perdas por tese" (mock 3e): barra empilhada de lost_reason por tese,
// delta vs. trimestre anterior e a linha "Sinal:" gerada aqui no front.
const props = defineProps({
  losses: { type: Object, required: true },
});

const { t } = useI18n();

const theses = computed(() => props.losses?.theses || []);

// Seletor "por tese ▾": default mostra todas; escolher uma filtra o bloco.
const selectedId = ref('all');
const visible = computed(() =>
  selectedId.value === 'all'
    ? theses.value
    : theses.value.filter(th => String(th.thesis_id) === selectedId.value)
);

const totalCount = computed(() =>
  theses.value.reduce((sum, th) => sum + (th.total || 0), 0)
);

const deltaPct = th => {
  if (!th.prev_total) return null;
  return Math.round(((th.total - th.prev_total) / th.prev_total) * 100);
};
const deltaLabel = th => {
  const pct = deltaPct(th);
  if (pct === null)
    return t('RAMON.COMMAND.LOSSES.DELTA_NONE', { count: th.total });
  if (pct > 0)
    return t('RAMON.COMMAND.LOSSES.DELTA_UP', { count: th.total, pct });
  if (pct < 0)
    return t('RAMON.COMMAND.LOSSES.DELTA_DOWN', {
      count: th.total,
      pct: Math.abs(pct),
    });
  return t('RAMON.COMMAND.LOSSES.DELTA_STABLE', { count: th.total });
};
const deltaClass = th => {
  const pct = deltaPct(th);
  if (pct === null || pct === 0) return 'text-n-slate-10';
  return pct > 0 ? 'text-n-ruby-11' : 'text-n-teal-11';
};

// Gradações de ruby por posição (as razões já vêm ordenadas desc do backend).
const SEGMENT_CLASSES = [
  'bg-n-ruby-9 text-white font-semibold',
  'bg-n-ruby-7 text-white',
  'bg-n-ruby-5 text-n-ruby-11',
  'bg-n-alpha-2 text-n-slate-11',
];
const segmentClass = index =>
  SEGMENT_CLASSES[Math.min(index, SEGMENT_CLASSES.length - 1)];

// Razão dominante ≥50% vira leitura acionável; sem dominante, sem sinal.
const signal = th => {
  const top = th.reasons?.[0];
  if (!top || !th.total) return null;
  const pct = Math.round((top.count / th.total) * 100);
  if (pct < 50) return null;
  return t('RAMON.COMMAND.LOSSES.SIGNAL', { reason: top.reason, pct });
};
</script>

<template>
  <div data-testid="losses-by-thesis">
    <div class="flex flex-wrap items-baseline justify-between gap-2 mb-3">
      <h2
        class="text-xs font-semibold tracking-[.12em] uppercase text-n-slate-10"
      >
        {{ t('RAMON.COMMAND.LOSSES.TITLE', { days: losses.window_days }) }}
      </h2>
      <div class="flex items-center gap-2 text-[11px] text-n-slate-9">
        <select
          v-model="selectedId"
          data-testid="losses-thesis-select"
          class="h-6 px-1 mb-0 text-[11px] bg-transparent border-none rounded text-n-slate-10"
        >
          <option value="all">{{ t('RAMON.COMMAND.LOSSES.ALL') }}</option>
          <option
            v-for="th in theses"
            :key="String(th.thesis_id)"
            :value="String(th.thesis_id)"
          >
            {{ th.name }}
          </option>
        </select>
        <span>{{
          t('RAMON.COMMAND.LOSSES.TOTAL', { count: totalCount })
        }}</span>
      </div>
    </div>
    <div
      class="flex flex-col gap-3.5 p-4 rounded-[14px] border border-n-weak bg-n-solid-2"
    >
      <div
        v-for="th in visible"
        :key="String(th.thesis_id)"
        data-testid="losses-thesis"
      >
        <div class="flex flex-wrap items-baseline gap-2 mb-1.5">
          <span class="text-[13px] font-semibold text-n-slate-12">
            {{ th.name }}
          </span>
          <span
            data-testid="losses-delta"
            class="text-[11px]"
            :class="deltaClass(th)"
          >
            {{ deltaLabel(th) }}
          </span>
        </div>
        <div class="flex h-[22px] gap-0.5 overflow-hidden rounded-md">
          <span
            v-for="(reason, index) in th.reasons"
            :key="reason.reason"
            data-testid="losses-segment"
            class="flex items-center min-w-0 px-1.5 overflow-hidden text-[10px] whitespace-nowrap"
            :class="segmentClass(index)"
            :style="{ flex: `${reason.count} 1 0%` }"
          >
            {{ reason.reason }} · {{ reason.count }}
          </span>
        </div>
        <p
          v-if="signal(th)"
          data-testid="losses-signal"
          class="mt-1.5 text-[11px] text-n-iris-11"
        >
          {{ signal(th) }}
        </p>
      </div>
    </div>
  </div>
</template>
