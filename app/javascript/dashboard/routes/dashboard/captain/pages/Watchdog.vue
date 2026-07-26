<script setup>
// Tela do Watchdog (Fatia 3 da área de IA): o vigia que já roda — retomada
// diária às 11:00 e copiloto noturno às 05:00 — com limites visíveis,
// contadores de 24h e a lista de casos em alerta. Não dispara nada.
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useStore } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import RamonWatchdogAPI from 'dashboard/api/ramonWatchdog';

defineOptions({ name: 'CaptainWatchdog' });

const { t } = useI18n();
const store = useStore();
const router = useRouter();
const { accountScopedRoute } = useAccount();

const data = ref(null);
const loading = ref(false);
const error = ref(false);

const fetchData = async () => {
  loading.value = true;
  error.value = false;
  try {
    const response = await RamonWatchdogAPI.get();
    data.value = response.data;
  } catch (e) {
    error.value = true;
  } finally {
    loading.value = false;
  }
};
onMounted(fetchData);

const thresholds = computed(() => data.value?.thresholds ?? {});
const counters = computed(() => data.value?.counters ?? {});
const items = computed(() => data.value?.items ?? []);

const fmtData = value =>
  value ? new Date(value).toLocaleDateString('pt-BR') : '—';

// Mesmo padrão das outras telas: abre o Funil e seleciona o caso.
const openLead = id => {
  router.push(accountScopedRoute('ramon_funil'));
  store.dispatch('leads/select', id);
};
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-auto bg-n-surface-1">
    <div class="w-full max-w-5xl px-6 py-6 mx-auto">
      <h1 class="text-xl font-medium text-n-slate-12">
        {{ t('CAPTAIN_RAMON.WATCHDOG.TITLE') }}
      </h1>
      <p class="mt-1 text-sm text-n-slate-10">
        {{ t('CAPTAIN_RAMON.WATCHDOG.SUBTITLE') }}
      </p>

      <div
        v-if="error"
        data-testid="watchdog-error"
        class="p-4 mt-4 text-sm border rounded-xl border-n-weak bg-n-solid-2"
      >
        <p class="text-n-ruby-11">{{ t('CAPTAIN_RAMON.LOAD_ERROR') }}</p>
        <button
          type="button"
          class="mt-1 text-xs text-n-iris-11 hover:underline"
          @click="fetchData"
        >
          {{ t('CAPTAIN_RAMON.RETRY') }}
        </button>
      </div>

      <template v-else>
        <div class="grid grid-cols-2 gap-3 mt-5 sm:grid-cols-4">
          <div class="p-4 border rounded-xl border-n-weak bg-n-solid-1">
            <p class="text-[11px] uppercase tracking-wide text-n-slate-10">
              {{ t('CAPTAIN_RAMON.WATCHDOG.PARADOS') }}
            </p>
            <p class="text-2xl font-semibold text-n-slate-12">
              {{ counters.parados_agora ?? 0 }}
            </p>
          </div>
          <div class="p-4 border rounded-xl border-n-weak bg-n-solid-1">
            <p class="text-[11px] uppercase tracking-wide text-n-slate-10">
              {{ t('CAPTAIN_RAMON.WATCHDOG.RETOMADAS_24H') }}
            </p>
            <p class="text-2xl font-semibold text-n-slate-12">
              {{ counters.retomadas_24h ?? 0 }}
            </p>
          </div>
          <div class="p-4 border rounded-xl border-n-weak bg-n-solid-1">
            <p class="text-[11px] uppercase tracking-wide text-n-slate-10">
              {{ t('CAPTAIN_RAMON.WATCHDOG.PENDENTES') }}
            </p>
            <p class="text-2xl font-semibold text-n-slate-12">
              {{ counters.sugestoes_pendentes ?? 0 }}
            </p>
          </div>
          <div class="p-4 border rounded-xl border-n-weak bg-n-solid-1">
            <p class="text-[11px] uppercase tracking-wide text-n-slate-10">
              {{ t('CAPTAIN_RAMON.WATCHDOG.EXECUCOES_24H') }}
            </p>
            <p class="text-2xl font-semibold text-n-slate-12">
              {{ counters.execucoes_24h ?? 0 }}
            </p>
          </div>
        </div>

        <p class="mt-4 text-xs text-n-slate-10">
          {{
            t('CAPTAIN_RAMON.WATCHDOG.REGUA', {
              cap: thresholds.teto_diario,
              gap: thresholds.intervalo_minimo_dias,
              retomada: thresholds.horario_retomada,
              copiloto: thresholds.horario_copiloto,
            })
          }}
        </p>

        <p v-if="loading" class="mt-6 text-sm text-n-slate-10">
          {{ t('CAPTAIN_RAMON.LOADING') }}
        </p>
        <p
          v-else-if="!items.length"
          data-testid="watchdog-vazio"
          class="mt-6 text-sm text-n-slate-10"
        >
          {{ t('CAPTAIN_RAMON.WATCHDOG.EMPTY') }}
        </p>

        <div v-else class="flex flex-col gap-2 mt-4">
          <button
            v-for="item in items"
            :key="item.lead_id"
            type="button"
            data-testid="watchdog-linha"
            class="px-4 py-3 text-left border rounded-xl border-n-weak bg-n-solid-1 hover:bg-n-solid-2"
            @click="openLead(item.lead_id)"
          >
            <div class="flex items-center gap-2">
              <span class="text-sm font-medium text-n-slate-12">
                {{ item.name }}
              </span>
              <span
                v-if="item.tentativas"
                class="px-2 py-0.5 text-[10px] font-semibold rounded-full bg-n-amber-3 text-n-amber-11"
              >
                {{
                  t('CAPTAIN_RAMON.WATCHDOG.TENTATIVAS', {
                    count: item.tentativas,
                  })
                }}
              </span>
              <span class="ml-auto text-[11px] text-n-slate-9">
                {{
                  t('CAPTAIN_RAMON.WATCHDOG.PARADO_HA', {
                    days: item.dias_parado,
                  })
                }}
              </span>
            </div>
            <p class="mt-1 text-xs text-n-slate-11">
              {{ item.stage_name }} ·
              {{ t('CAPTAIN_RAMON.WATCHDOG.ULTIMA') }}
              {{ fmtData(item.ultima_retomada_em) }}
              <span v-if="item.tarefa_aberta">
                · {{ t('CAPTAIN_RAMON.WATCHDOG.COM_TAREFA') }}
              </span>
            </p>
          </button>
        </div>
      </template>
    </div>
  </section>
</template>
