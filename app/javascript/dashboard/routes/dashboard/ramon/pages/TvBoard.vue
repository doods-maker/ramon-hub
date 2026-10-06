<script setup>
// Placar de TV (/tv) — mock 5a. Página standalone sem chrome, escura sempre
// (classe `dark` na raiz: tokens do tema preto mesmo com o hub no claro):
// base fixa 1280×720 escalada por transform pra caber em qualquer 16:9.
// Kit visual do hub em tamanho de TV (lê de longe); números em font-mono.
import { computed, onMounted, onUnmounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAccount } from 'dashboard/composables/useAccount';
import Button from 'dashboard/components-next/button/Button.vue';
import { useStore, useStoreGetters } from 'dashboard/composables/store';
import { brlCompact } from '../helpers/currency';
import { CARTAO } from '../helpers/ui';

// Kit em tamanho de TV: rótulo/sub/número maiores que os do hub.
const ROTULO_TV =
  'm-0 text-xs font-semibold uppercase tracking-widest text-n-slate-11';
const SUB_TV = 'm-0 text-[11px] text-n-slate-11';
const NUMERO_TV =
  'm-0 font-mono text-[32px] font-medium leading-[1.1] tabular-nums text-n-slate-12';
const CARTAO_TV = `${CARTAO} !px-5 !py-4`;

const { t } = useI18n();
const router = useRouter();
const { accountScopedRoute } = useAccount();
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

// "ao vivo" honesto: cada fetch bem-sucedido troca o objeto do store; se
// passar de 3 min sem troca (cable e fallback falhando), o selo avisa.
const DESATUALIZADO_MIN = 3;
const atualizadoEm = ref(null);
watch(
  data,
  valor => {
    if (valor) atualizadoEm.value = Date.now();
  },
  { immediate: true }
);
const minutosSemAtualizar = computed(() =>
  atualizadoEm.value
    ? Math.floor((now.value.getTime() - atualizadoEm.value) / 60000)
    : 0
);
const desatualizado = computed(
  () => minutosSemAtualizar.value >= DESATUALIZADO_MIN
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
// ---- Controles (só admin abre o placar): aparecem ao mexer o mouse ------
// "Voltar ao hub" e tela cheia; Esc fora da tela cheia também volta.
const controles = ref(false);
const telaCheia = ref(false);
let controlesTimer;
const mostrarControles = () => {
  controles.value = true;
  clearTimeout(controlesTimer);
  controlesTimer = setTimeout(() => {
    controles.value = false;
  }, 3000);
};
const voltar = () => router.push(accountScopedRoute('ramon_index'));
const alternarTelaCheia = () =>
  document.fullscreenElement
    ? document.exitFullscreen()
    : document.documentElement.requestFullscreen();
const aoMudarTelaCheia = () => {
  telaCheia.value = !!document.fullscreenElement;
};
const aoTeclar = event => {
  if (event.key === 'Escape' && !document.fullscreenElement) voltar();
};
onMounted(() => {
  document.addEventListener('fullscreenchange', aoMudarTelaCheia);
  window.addEventListener('keydown', aoTeclar);
});
onUnmounted(() => {
  document.removeEventListener('fullscreenchange', aoMudarTelaCheia);
  window.removeEventListener('keydown', aoTeclar);
  clearTimeout(controlesTimer);
  if (document.fullscreenElement) document.exitFullscreen();
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
// Só marcador de linha (sem significado): azul da marca em degradê.
const DOT_COLORS = [
  'bg-n-blue-9',
  'bg-n-blue-9/80',
  'bg-n-blue-9/60',
  'bg-n-blue-9/45',
  'bg-n-slate-9',
];
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
      cls: 'text-n-ruby-11',
    };
  }
  if (bestThesis.value === row) {
    return { text: t('RAMON.TV.NOTE_BEST'), cls: 'text-n-teal-11' };
  }
  if (row.stalled_count > 0) {
    return {
      text: t('RAMON.TV.NOTE_STALLED', { count: row.stalled_count }),
      cls: 'text-n-amber-11',
    };
  }
  return { text: t('RAMON.TV.NOTE_STABLE'), cls: 'text-n-slate-11' };
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
    class="dark fixed inset-0 flex items-center justify-center overflow-hidden bg-n-background text-n-slate-12"
    :class="{ 'cursor-none': !controles }"
    @mousemove="mostrarControles"
  >
    <div
      data-testid="tv-controles"
      class="absolute right-4 top-4 z-10 flex gap-2 transition-opacity duration-300"
      :class="controles ? 'opacity-100' : 'pointer-events-none opacity-0'"
    >
      <Button
        data-testid="tv-tela-cheia"
        :icon="telaCheia ? 'i-lucide-minimize' : 'i-lucide-maximize'"
        :label="
          telaCheia ? t('RAMON.TV.SAIR_TELA_CHEIA') : t('RAMON.TV.TELA_CHEIA')
        "
        sm
        faded
        slate
        @click="alternarTelaCheia"
      />
      <Button
        data-testid="tv-voltar"
        icon="i-lucide-x"
        :label="t('RAMON.TV.VOLTAR')"
        sm
        faded
        slate
        @click="voltar"
      />
    </div>
    <div
      data-testid="tv-stage"
      class="box-border flex h-[720px] w-[1280px] flex-none flex-col bg-n-background px-[52px] py-[40px]"
      :style="{ transform: `scale(${scale})` }"
    >
      <!-- Topo: eyebrow + relógio -->
      <div class="flex items-baseline gap-4">
        <p
          class="m-0 text-xs font-semibold uppercase tracking-[.24em] text-n-blue-11"
        >
          {{ `${t('RAMON.TV.EYEBROW')} · ${monthName}` }}
        </p>
        <span
          data-testid="tv-live"
          class="ml-auto inline-flex items-center gap-1.5 text-xs"
          :class="desatualizado ? 'text-n-amber-11' : 'text-n-slate-11'"
        >
          <span
            class="size-[7px] rounded-full"
            :class="desatualizado ? 'bg-n-amber-9' : 'bg-n-teal-9'"
          />
          <template v-if="desatualizado">
            {{ t('RAMON.TV.STALE', { min: minutosSemAtualizar }) }}
          </template>
          <template v-else>{{ t('RAMON.TV.LIVE') }}</template>
          ·
          <span class="font-mono tabular-nums">{{ clock }}</span>
        </span>
      </div>

      <template v-if="month">
        <!-- Hero: ganhos no mês + meta + hoje -->
        <div class="mt-5 flex items-end gap-12">
          <div>
            <p :class="ROTULO_TV">{{ t('RAMON.TV.MONTH_WON') }}</p>
            <p
              data-testid="tv-hero-value"
              class="m-0 mt-1 font-mono text-[80px] font-medium leading-none tracking-tight tabular-nums text-n-slate-12"
            >
              {{ brlCompact(month.won_value) }}
            </p>
          </div>
          <div
            v-if="goalValue > 0"
            data-testid="tv-goal"
            class="max-w-[380px] flex-1 pb-3"
          >
            <p :class="ROTULO_TV">
              {{ t('RAMON.TV.GOAL', { value: brlCompact(goalValue) }) }}
            </p>
            <div class="mt-2 flex items-center gap-3">
              <span
                class="block h-2.5 flex-1 overflow-hidden rounded-full bg-n-alpha-2"
              >
                <span
                  class="block h-full rounded-full bg-n-blue-9"
                  :style="{ width: goalBarWidth }"
                />
              </span>
              <span
                class="font-mono text-lg font-medium tabular-nums text-n-blue-11"
              >
                {{ `${goalPct}%` }}
              </span>
            </div>
            <p class="mb-0 mt-1.5 text-xs text-n-slate-11">
              {{ t('RAMON.TV.DAYS_LEFT', { count: month.business_days_left }) }}
            </p>
          </div>
          <div class="ml-auto pb-2 text-right">
            <p :class="ROTULO_TV">{{ t('RAMON.TV.TODAY') }}</p>
            <div data-testid="tv-today" class="mt-1 flex gap-[26px]">
              <div>
                <p :class="NUMERO_TV" class="!text-n-teal-11">
                  {{ today.won_count }}
                </p>
                <p :class="SUB_TV">{{ t('RAMON.TV.TODAY_WON') }}</p>
              </div>
              <div>
                <p :class="NUMERO_TV">{{ today.new_count }}</p>
                <p :class="SUB_TV">{{ t('RAMON.TV.TODAY_NEW') }}</p>
              </div>
              <div>
                <p :class="NUMERO_TV">
                  {{ minutesLabel(today.avg_first_response_minutes) }}
                </p>
                <p :class="SUB_TV">{{ t('RAMON.TV.TODAY_RESPONSE') }}</p>
              </div>
            </div>
          </div>
        </div>

        <!-- Centro: por tese + coluna direita -->
        <div class="mt-[30px] grid min-h-0 flex-1 grid-cols-[1.7fr_1fr] gap-11">
          <div>
            <p :class="ROTULO_TV" class="!mb-3">
              {{ t('RAMON.TV.BY_THESIS') }}
            </p>
            <div class="flex flex-col">
              <div
                v-for="(row, index) in byThesis"
                :key="row.thesis_id ?? 'none'"
                data-testid="tv-thesis-row"
                class="flex items-center gap-4 border-t border-n-weak py-3 last:border-b"
              >
                <span
                  class="size-2.5 flex-none rounded-full"
                  :class="dotColor(index)"
                />
                <div class="min-w-0 flex-1">
                  <p class="m-0 text-[17px] font-medium text-n-slate-12">
                    {{ row.name }}
                  </p>
                  <p
                    data-testid="tv-thesis-note"
                    class="mb-0 mt-px text-xs"
                    :class="thesisNote(row).cls"
                  >
                    {{ thesisNote(row).text }}
                  </p>
                </div>
                <div class="w-[120px] text-right">
                  <p :class="NUMERO_TV" class="!text-[26px]">
                    {{ row.leads_count }}
                  </p>
                  <p :class="SUB_TV">
                    {{ t('RAMON.TV.LEADS_SUB', { count: row.new_week }) }}
                  </p>
                </div>
                <div class="w-[90px] text-right">
                  <p :class="NUMERO_TV" class="!text-[26px] !text-n-teal-11">
                    {{ row.won_month }}
                  </p>
                  <p :class="SUB_TV">
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
                    class="m-0 font-mono text-lg font-medium tabular-nums text-n-teal-11"
                  >
                    {{ brlCompact(row.won_value_month) }}
                  </p>
                </div>
              </div>
            </div>
            <p
              v-if="funnelLine"
              data-testid="tv-funnel-line"
              class="mb-0 mt-3 text-xs text-n-slate-11"
            >
              {{ funnelLine }}
            </p>
          </div>

          <div class="flex flex-col gap-4">
            <div :class="CARTAO_TV">
              <p :class="ROTULO_TV" class="!mb-3">{{ t('RAMON.TV.RACE') }}</p>
              <ol class="m-0 flex list-none flex-col gap-2.5 p-0">
                <li
                  v-for="(runner, index) in race"
                  :key="runner.name"
                  data-testid="tv-race-row"
                  class="flex items-center gap-2.5"
                >
                  <span
                    class="w-[18px] font-mono text-xl tabular-nums"
                    :class="index === 0 ? 'text-n-blue-11' : 'text-n-slate-11'"
                  >
                    {{ index + 1 }}
                  </span>
                  <span class="text-[15px] font-medium text-n-slate-12">
                    {{ runner.name }}
                  </span>
                  <span
                    class="ml-auto font-mono text-[15px] font-medium tabular-nums text-n-teal-11"
                  >
                    {{ brlCompact(runner.won_value) }}
                  </span>
                </li>
              </ol>
              <p v-if="!race.length" class="m-0 text-xs text-n-slate-11">
                {{ t('RAMON.TV.RACE_EMPTY') }}
              </p>
            </div>

            <div
              data-testid="tv-prescribing"
              :class="CARTAO_TV"
              class="border-l-4 border-l-n-ruby-9"
            >
              <p :class="ROTULO_TV" class="!text-n-ruby-11">
                {{ t('RAMON.TV.PRESCRIBING') }}
              </p>
              <p
                class="mb-0 mt-2 font-mono text-[30px] font-medium leading-none tabular-nums text-n-ruby-11"
              >
                {{
                  t('RAMON.TV.PRESCRIBING_MONTH', {
                    value: brlFull(tv.prescribing_total_monthly),
                  })
                }}
              </p>
              <p class="mb-0 mt-1.5 text-xs text-n-slate-11">
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

            <div data-testid="tv-next-meeting" :class="CARTAO_TV">
              <p :class="ROTULO_TV">{{ t('RAMON.TV.NEXT') }}</p>
              <template v-if="nextMeeting">
                <p class="mb-0 mt-2 text-[15px] text-n-slate-12">
                  <b class="font-mono font-medium text-n-blue-11">
                    {{ hourLabel(nextMeeting.at) }}
                  </b>
                  {{ `· ${nextMeeting.lead_name}` }}
                </p>
                <p
                  v-if="nextMeeting.user_name"
                  class="mb-0 mt-0.5 text-xs text-n-slate-11"
                >
                  {{ nextMeeting.user_name }}
                </p>
              </template>
              <p v-else class="mb-0 mt-2 text-xs text-n-slate-11">
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
          <span class="size-2 rounded-full bg-n-teal-9" />
          <p class="m-0 text-[15px] text-n-slate-12">
            <b class="text-n-teal-11">{{ t('RAMON.TV.TICKER_NOW') }}</b>
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
