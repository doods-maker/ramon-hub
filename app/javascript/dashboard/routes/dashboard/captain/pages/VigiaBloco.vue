<script setup>
// Bloco Vigia da Visão geral (I-WD1): o vigia que já roda — retomada diária às
// 11:00 e copiloto noturno às 05:00 — com a régua e os casos parados.
// Sugestões pendentes e execuções ficam nos blocos Aprovações e Ferramentas da
// mesma tela. Não dispara nada.
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useStore } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import RamonWatchdogAPI from 'dashboard/api/ramonWatchdog';
import {
  CARTAO,
  CHIP,
  LINHA,
  TITULO,
  TOM,
} from 'dashboard/routes/dashboard/ramon/helpers/ui';

defineOptions({ name: 'CaptainVigiaBloco' });

const VISIVEIS = 5;

const { t } = useI18n();
const store = useStore();
const router = useRouter();
const { accountScopedRoute } = useAccount();

const data = ref(null);
const loading = ref(true);
const error = ref(false);
const mostrarTodos = ref(false);

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
const visiveis = computed(() =>
  mostrarTodos.value ? items.value : items.value.slice(0, VISIVEIS)
);

const fmtData = value =>
  value ? new Date(value).toLocaleDateString('pt-BR') : '—';

// Mesmo padrão das outras telas: abre o Funil e seleciona o caso.
const openLead = id => {
  router.push(accountScopedRoute('ramon_funil'));
  store.dispatch('leads/select', id);
};
</script>

<template>
  <section data-testid="vigia-bloco" :class="CARTAO">
    <h2 :class="TITULO">{{ t('CAPTAIN_RAMON.WATCHDOG.TITLE') }}</h2>
    <p class="mt-1 text-xs text-n-slate-10">
      {{ t('CAPTAIN_RAMON.WATCHDOG.SUBTITLE') }}
    </p>

    <p
      v-if="error"
      data-testid="watchdog-error"
      class="mt-3 text-sm text-n-ruby-11"
    >
      {{ t('CAPTAIN_RAMON.LOAD_ERROR') }}
      <button
        type="button"
        class="ml-1 text-xs text-n-blue-11 hover:underline"
        @click="fetchData"
      >
        {{ t('CAPTAIN_RAMON.RETRY') }}
      </button>
    </p>

    <template v-else>
      <div class="flex flex-wrap gap-1.5 mt-3">
        <span :class="[CHIP, counters.parados_agora ? TOM.amber : TOM.slate]">
          {{
            t('CAPTAIN_RAMON.WATCHDOG.PARADOS_N', {
              n: counters.parados_agora ?? 0,
            })
          }}
        </span>
        <span :class="[CHIP, TOM.slate]">
          {{
            t('CAPTAIN_RAMON.WATCHDOG.RETOMADAS_N', {
              n: counters.retomadas_24h ?? 0,
            })
          }}
        </span>
      </div>
      <p class="mt-2 text-xs text-n-slate-10">
        {{
          t('CAPTAIN_RAMON.WATCHDOG.REGUA', {
            cap: thresholds.teto_diario,
            gap: thresholds.intervalo_minimo_dias,
            retomada: thresholds.horario_retomada,
            copiloto: thresholds.horario_copiloto,
          })
        }}
      </p>

      <p v-if="loading" class="mt-3 text-sm text-n-slate-10">
        {{ t('CAPTAIN_RAMON.LOADING') }}
      </p>
      <p
        v-else-if="!items.length"
        data-testid="watchdog-vazio"
        class="mt-3 text-sm text-n-slate-10"
      >
        {{ t('CAPTAIN_RAMON.WATCHDOG.EMPTY') }}
      </p>

      <div v-else class="flex flex-col mt-2">
        <button
          v-for="item in visiveis"
          :key="item.lead_id"
          type="button"
          data-testid="watchdog-linha"
          :class="LINHA"
          @click="openLead(item.lead_id)"
        >
          <div class="flex items-center gap-2">
            <span class="font-medium text-n-slate-12">{{ item.name }}</span>
            <span v-if="item.tentativas" :class="[CHIP, TOM.amber]">
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
          <p class="mt-0.5 text-xs text-n-slate-11">
            {{ item.stage_name }} ·
            {{ t('CAPTAIN_RAMON.WATCHDOG.ULTIMA') }}
            {{ fmtData(item.ultima_retomada_em) }}
            <span v-if="item.tarefa_aberta">
              · {{ t('CAPTAIN_RAMON.WATCHDOG.COM_TAREFA') }}
            </span>
          </p>
        </button>
        <button
          v-if="items.length > VISIVEIS"
          type="button"
          class="self-start mt-1 text-xs text-n-blue-11 hover:underline"
          @click="mostrarTodos = !mostrarTodos"
        >
          {{
            mostrarTodos
              ? t('CAPTAIN_RAMON.WATCHDOG.VER_MENOS')
              : t('CAPTAIN_RAMON.WATCHDOG.VER_TODOS', { n: items.length })
          }}
        </button>
      </div>
    </template>
  </section>
</template>
