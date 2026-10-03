<script setup>
// Placar de TV (/tv) — mock 5a. Página standalone sem chrome, dark sempre:
// base fixa 1280×720 escalada por transform pra caber em qualquer 16:9.
// Cores fixas do mock de propósito (ambiente controlado de TV).
import { computed, onMounted, onUnmounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useStoreGetters } from 'dashboard/composables/store';
import { brlCompact } from '../helpers/currency';

const { t } = useI18n();
const store = useStore();
const getters = useStoreGetters();

const data = computed(() => getters['ramonDashboard/getData'].value);
const tv = computed(() => data.value?.tv || null);
const month = computed(() => tv.value?.month || null);
const today = computed(() => month.value?.today || {});
const byThesis = computed(() => tv.value?.by_thesis || []);
const race = computed(() => tv.value?.race || []);
const nextMeeting = computed(() => tv.value?.next_meeting || null);
const lastWon = computed(() => tv.value?.last_won || null);

// ---- Escala 1280×720 → viewport (letterbox) ------------------------------
const scale = ref(1);
const updateScale = () => {
  scale.value = Math.min(window.innerWidth / 1280, window.innerHeight / 720);
};

// ---- Relógio + refresh ----------------------------------------------------
const now = ref(new Date());
const clock = computed(() =>
  new Intl.DateTimeFormat('pt-BR', {
    hour: '2-digit',
    minute: '2-digit',
  }).format(now.value)
);
const monthName = computed(() =>
  new Intl.DateTimeFormat('pt-BR', { month: 'long' }).format(now.value)
);

const refetch = () => store.dispatch('ramonDashboard/fetch');
let clockTimer;
let fallbackTimer;
let debounceTimer;
let unsubscribe;
onMounted(() => {
  refetch();
  updateScale();
  window.addEventListener('resize', updateScale);
  clockTimer = setInterval(() => {
    now.value = new Date();
  }, 60 * 1000);
  // Fallback caso o cable caia: re-fetch a cada 2min.
  fallbackTimer = setInterval(refetch, 120 * 1000);
  // Broadcast lead.created/updated já faz leads/upsert (MERGE_LEAD):
  // qualquer mexida em lead agenda um re-fetch com debounce de 5s.
  unsubscribe = store.subscribe(mutation => {
    // módulo leads é namespaced: o type chega prefixado
    if (mutation.type !== 'leads/MERGE_LEAD') return;
    clearTimeout(debounceTimer);
    debounceTimer = setTimeout(refetch, 5000);
  });
});
onUnmounted(() => {
  window.removeEventListener('resize', updateScale);
  clearInterval(clockTimer);
  clearInterval(fallbackTimer);
  clearTimeout(debounceTimer);
  if (unsubscribe) unsubscribe();
});
// ponytail: sem rotação de destaque a cada 30s — adicionar se a TV pedir variedade.

// ---- Formatação -----------------------------------------------------------
const brlFull = value =>
  new Intl.NumberFormat('pt-BR', {
    style: 'currency',
    currency: 'BRL',
    maximumFractionDigits: 0,
  }).format(Number(value) || 0);
const minutesLabel = value =>
  value === null || value === undefined ? '—' : `${Math.round(value)}min`;
const hourLabel = iso =>
  new Intl.DateTimeFormat('pt-BR', { hour: '2-digit', minute: '2-digit' })
    .format(new Date(iso))
    .replace(':', 'h');

// ---- Meta do mês ----------------------------------------------------------
const goalValue = computed(() => Number(month.value?.goal) || 0);
const goalPct = computed(() =>
  goalValue.value > 0
    ? Math.round(
        ((Number(month.value?.won_value) || 0) / goalValue.value) * 100
      )
    : 0
);
const goalBarWidth = computed(() => `${Math.min(100, goalPct.value)}%`);

// ---- Por tese: dot + subnota ---------------------------------------------
const DOT_COLORS = ['#c9a97c', '#8f9a6b', '#b4785a', '#6b8f85', '#8d867d'];
const dotColor = index => DOT_COLORS[index % DOT_COLORS.length];

// Melhor conversão do mês: maior conversion_pct entre teses com ganho no mês.
const bestThesis = computed(() =>
  byThesis.value.reduce((best, row) => {
    if (!row.won_month || row.conversion_pct === null) return best;
    if (!best || row.conversion_pct > best.conversion_pct) return row;
    return best;
  }, null)
);

// Subnota só quando há história, na ordem: prescrevendo > melhor conversão
// > parados > estável.
const thesisNote = row => {
  if (row.prescribing_count > 0) {
    return {
      text: t('RAMON.TV.NOTE_PRESCRIBING', { count: row.prescribing_count }),
      cls: 'text-[#ff949d]',
    };
  }
  if (bestThesis.value === row) {
    return { text: t('RAMON.TV.NOTE_BEST'), cls: 'text-[#0bd8b6]' };
  }
  if (row.stalled_count > 0) {
    return {
      text: t('RAMON.TV.NOTE_STALLED', { count: row.stalled_count }),
      cls: 'text-[#ffca16]',
    };
  }
  return { text: t('RAMON.TV.NOTE_STABLE'), cls: 'text-[#77716a]' };
};

// ---- Funil ativo em 1 linha ----------------------------------------------
const openFunnel = computed(() =>
  (data.value?.funnel || []).filter(row => !row.is_won && !row.is_lost)
);
const funnelLine = computed(() => {
  if (!openFunnel.value.length) return '';
  const count = openFunnel.value.reduce((sum, row) => sum + row.count, 0);
  const stages = openFunnel.value
    .map(row => `${row.name} ${row.count}`)
    .join(' · ');
  return t('RAMON.TV.FUNNEL_LINE', { count, stages });
});
</script>

<template>
  <div
    class="fixed inset-0 flex items-center justify-center overflow-hidden bg-[#141210] cursor-none"
  >
    <div
      data-testid="tv-stage"
      class="flex h-[720px] w-[1280px] flex-none flex-col box-border bg-[#1e1b19] px-[52px] py-[40px] font-inter"
      :style="{ transform: `scale(${scale})` }"
    >
      <!-- Topo: eyebrow + relógio -->
      <div class="flex items-baseline gap-4">
        <p class="m-0 text-[11px] uppercase tracking-[.24em] text-[#c9a97c]">
          {{ `${t('RAMON.TV.EYEBROW')} · ${monthName}` }}
        </p>
        <span
          class="ml-auto inline-flex items-center gap-1.5 text-[11px] text-[#77716a]"
        >
          <span class="h-[7px] w-[7px] rounded-full bg-[#0bd8b6]" />
          {{ `${t('RAMON.TV.LIVE')} · ${clock}` }}
        </span>
      </div>

      <template v-if="month">
        <!-- Hero: ganhos no mês + meta + hoje -->
        <div class="mt-5 flex items-end gap-12">
          <div>
            <p class="m-0 text-[11px] uppercase tracking-[.1em] text-[#8d867d]">
              {{ t('RAMON.TV.MONTH_WON') }}
            </p>
            <p
              data-testid="tv-hero-value"
              class="m-0 font-cormorant text-[88px] font-semibold leading-none text-[#ece7df]"
            >
              {{ brlCompact(month.won_value) }}
            </p>
          </div>
          <div
            v-if="goalValue > 0"
            data-testid="tv-goal"
            class="max-w-[380px] flex-1 pb-3"
          >
            <p class="m-0 text-[11px] uppercase tracking-[.1em] text-[#8d867d]">
              {{ t('RAMON.TV.GOAL', { value: brlCompact(goalValue) }) }}
            </p>
            <div class="mt-2 flex items-center gap-3">
              <span class="block h-2 flex-1 rounded-full bg-[#c9a97c]/[.14]">
                <span
                  class="block h-full rounded-full bg-gradient-to-r from-[#8a5c33] to-[#c9a97c]"
                  :style="{ width: goalBarWidth }"
                />
              </span>
              <span class="text-base font-semibold text-[#c9a97c]">
                {{ `${goalPct}%` }}
              </span>
            </div>
            <p class="mb-0 mt-[5px] text-[11px] text-[#77716a]">
              {{ t('RAMON.TV.DAYS_LEFT', { count: month.business_days_left }) }}
            </p>
          </div>
          <div class="ml-auto pb-2 text-right">
            <p class="m-0 text-[11px] uppercase tracking-[.1em] text-[#8d867d]">
              {{ t('RAMON.TV.TODAY') }}
            </p>
            <div data-testid="tv-today" class="mt-1 flex gap-[26px]">
              <div>
                <p
                  class="m-0 font-cormorant text-[32px] font-semibold leading-[1.1] text-[#0bd8b6]"
                >
                  {{ today.won_count }}
                </p>
                <p class="m-0 text-[10px] text-[#77716a]">
                  {{ t('RAMON.TV.TODAY_WON') }}
                </p>
              </div>
              <div>
                <p
                  class="m-0 font-cormorant text-[32px] font-semibold leading-[1.1] text-[#ece7df]"
                >
                  {{ today.new_count }}
                </p>
                <p class="m-0 text-[10px] text-[#77716a]">
                  {{ t('RAMON.TV.TODAY_NEW') }}
                </p>
              </div>
              <div>
                <p
                  class="m-0 font-cormorant text-[32px] font-semibold leading-[1.1] text-[#ece7df]"
                >
                  {{ minutesLabel(today.avg_first_response_minutes) }}
                </p>
                <p class="m-0 text-[10px] text-[#77716a]">
                  {{ t('RAMON.TV.TODAY_RESPONSE') }}
                </p>
              </div>
            </div>
          </div>
        </div>

        <!-- Centro: por tese + coluna direita -->
        <div class="mt-[34px] grid min-h-0 flex-1 grid-cols-[1.7fr_1fr] gap-11">
          <div>
            <p
              class="mb-3.5 mt-0 text-[10px] font-semibold uppercase tracking-[.16em] text-[#8d867d]"
            >
              {{ t('RAMON.TV.BY_THESIS') }}
            </p>
            <div class="flex flex-col">
              <div
                v-for="(row, index) in byThesis"
                :key="row.thesis_id ?? 'none'"
                data-testid="tv-thesis-row"
                class="flex items-center gap-4 border-t border-[#c9a97c]/10 py-[13px] last:border-b"
              >
                <span
                  class="h-[9px] w-[9px] flex-none rounded-full"
                  :style="{ background: dotColor(index) }"
                />
                <div class="min-w-0 flex-1">
                  <p class="m-0 text-base font-medium text-[#ece7df]">
                    {{ row.name }}
                  </p>
                  <p
                    data-testid="tv-thesis-note"
                    class="mb-0 mt-px text-[11px]"
                    :class="thesisNote(row).cls"
                  >
                    {{ thesisNote(row).text }}
                  </p>
                </div>
                <div class="w-[110px] text-right">
                  <p
                    class="m-0 font-cormorant text-[26px] font-semibold leading-[1.1] text-[#ece7df]"
                  >
                    {{ row.leads_count }}
                  </p>
                  <p class="m-0 text-[9.5px] text-[#77716a]">
                    {{ t('RAMON.TV.LEADS_SUB', { count: row.new_week }) }}
                  </p>
                </div>
                <div class="w-[90px] text-right">
                  <p
                    class="m-0 font-cormorant text-[26px] font-semibold leading-[1.1] text-[#0bd8b6]"
                  >
                    {{ row.won_month }}
                  </p>
                  <p class="m-0 text-[9.5px] text-[#77716a]">
                    <template v-if="row.conversion_pct !== null">
                      {{ t('RAMON.TV.WON_SUB', { pct: row.conversion_pct }) }}
                    </template>
                    <template v-else>
                      {{ t('RAMON.TV.WON_SUB_EMPTY') }}
                    </template>
                  </p>
                </div>
                <div class="w-[110px] text-right">
                  <p
                    class="m-0 text-[17px] font-semibold tabular-nums text-[#0bd8b6]"
                  >
                    {{ brlCompact(row.won_value_month) }}
                  </p>
                </div>
              </div>
            </div>
            <p
              v-if="funnelLine"
              data-testid="tv-funnel-line"
              class="mb-0 mt-3.5 text-[11px] text-[#77716a]"
            >
              {{ funnelLine }}
            </p>
          </div>

          <div class="flex flex-col gap-4">
            <div
              class="rounded-[14px] border border-[#c9a97c]/10 bg-[#2b2825] px-5 py-[18px]"
            >
              <p
                class="mb-3 mt-0 text-[10px] font-semibold uppercase tracking-[.12em] text-[#8d867d]"
              >
                {{ t('RAMON.TV.RACE') }}
              </p>
              <div class="flex flex-col gap-2.5">
                <div
                  v-for="(runner, index) in race"
                  :key="runner.name"
                  data-testid="tv-race-row"
                  class="flex items-center gap-2.5"
                >
                  <span
                    class="w-[18px] font-cormorant text-xl"
                    :class="index === 0 ? 'text-[#c9a97c]' : 'text-[#8d867d]'"
                  >
                    {{ index + 1 }}
                  </span>
                  <span class="text-sm font-medium text-[#ece7df]">
                    {{ runner.name }}
                  </span>
                  <span
                    class="ml-auto text-sm font-semibold tabular-nums text-[#0bd8b6]"
                  >
                    {{ brlCompact(runner.won_value) }}
                  </span>
                </div>
                <p v-if="!race.length" class="m-0 text-[11px] text-[#77716a]">
                  {{ t('RAMON.TV.RACE_EMPTY') }}
                </p>
              </div>
            </div>

            <div
              data-testid="tv-prescribing"
              class="rounded-[14px] border border-[#e54666]/30 bg-[#2b2825] px-5 py-[18px]"
            >
              <p
                class="m-0 text-[10px] font-semibold uppercase tracking-[.12em] text-[#ff949d]"
              >
                {{ t('RAMON.TV.PRESCRIBING') }}
              </p>
              <p
                class="mb-0 mt-2 font-cormorant text-[34px] font-semibold leading-none text-[#ff949d]"
              >
                {{
                  t('RAMON.TV.PRESCRIBING_MONTH', {
                    value: brlFull(tv.prescribing_total_monthly),
                  })
                }}
              </p>
              <p class="mb-0 mt-1 text-[10.5px] text-[#77716a]">
                {{
                  t('RAMON.TV.PRESCRIBING_SUB', {
                    count: byThesis.reduce(
                      (sum, row) => sum + row.prescribing_count,
                      0
                    ),
                  })
                }}
              </p>
            </div>

            <div
              data-testid="tv-next-meeting"
              class="rounded-[14px] border border-[#c9a97c]/10 bg-[#2b2825] px-5 py-4"
            >
              <p
                class="m-0 text-[10px] font-semibold uppercase tracking-[.12em] text-[#8d867d]"
              >
                {{ t('RAMON.TV.NEXT') }}
              </p>
              <template v-if="nextMeeting">
                <p class="mb-0 mt-2 text-sm text-[#ece7df]">
                  <b class="text-[#c9a97c]">{{ hourLabel(nextMeeting.at) }}</b>
                  {{ `· ${nextMeeting.lead_name}` }}
                </p>
                <p
                  v-if="nextMeeting.user_name"
                  class="mb-0 mt-0.5 text-[11px] text-[#77716a]"
                >
                  {{ nextMeeting.user_name }}
                </p>
              </template>
              <p v-else class="mb-0 mt-2 text-[11px] text-[#77716a]">
                {{ t('RAMON.TV.NEXT_EMPTY') }}
              </p>
            </div>
          </div>
        </div>

        <!-- Ticker do último ganho de hoje -->
        <div
          v-if="lastWon"
          data-testid="tv-ticker"
          class="mt-auto flex items-center gap-2.5 pt-5"
        >
          <span class="h-2 w-2 rounded-full bg-[#0bd8b6]" />
          <p class="m-0 text-sm text-[#c9c2b8]">
            <b class="text-[#0bd8b6]">{{ t('RAMON.TV.TICKER_NOW') }}</b>
            {{
              t('RAMON.TV.TICKER', {
                closer: lastWon.closer_name || '—',
                lead: lastWon.lead_name,
                value: brlFull(lastWon.value),
                benefit: lastWon.benefit || '—',
              })
            }}
          </p>
        </div>
      </template>
    </div>
  </div>
</template>
