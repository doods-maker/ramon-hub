<script setup>
// Tela Execuções (Fatia 3 da área de IA): o log auditável do que o agente
// executou — tool, parâmetros, resposta, duração. Leitura pura.
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import CaptainToolRunsAPI from 'dashboard/api/captainToolRuns';

defineOptions({ name: 'CaptainExecucoes' });

const { t } = useI18n();

const data = ref(null);
const loading = ref(false);
const error = ref(false);
const filtroTool = ref('');
const filtroStatus = ref('');
const aberto = ref(null);

const fetchData = async () => {
  loading.value = true;
  error.value = false;
  try {
    const params = {};
    if (filtroTool.value) params.tool_name = filtroTool.value;
    if (filtroStatus.value) params.status = filtroStatus.value;
    const response = await CaptainToolRunsAPI.list(params);
    data.value = response.data;
  } catch (e) {
    error.value = true;
  } finally {
    loading.value = false;
  }
};
onMounted(fetchData);

const resumo = computed(() => data.value?.resumo ?? {});
const items = computed(() => data.value?.items ?? []);
const tools = computed(() => resumo.value.tools ?? []);

const fmtHora = value =>
  new Date(value).toLocaleString('pt-BR', {
    day: '2-digit',
    month: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  });

const paramsResumo = run => {
  const entries = Object.entries(run.params || {});
  if (!entries.length) return '—';
  return entries.map(([k, v]) => `${k}: ${v}`).join(' · ');
};

const toggle = id => {
  aberto.value = aberto.value === id ? null : id;
};

// texto montado no script: o template não aceita string crua (eslint i18n)
const linhaTempo = run => `${fmtHora(run.created_at)} · ${run.duration_ms}ms`;
const linhaCaso = run =>
  run.lead_id ? ` · ${t('CAPTAIN_RAMON.EXECUCOES.CASO')} #${run.lead_id}` : '';
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-auto bg-n-surface-1">
    <div class="w-full max-w-5xl px-6 py-6 mx-auto">
      <h1 class="text-xl font-medium text-n-slate-12">
        {{ t('CAPTAIN_RAMON.EXECUCOES.TITLE') }}
      </h1>
      <p class="mt-1 text-sm text-n-slate-10">
        {{ t('CAPTAIN_RAMON.EXECUCOES.SUBTITLE') }}
      </p>

      <div
        v-if="error"
        data-testid="execucoes-error"
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
        <div class="grid grid-cols-2 gap-3 mt-5 sm:grid-cols-3">
          <div class="p-4 border rounded-xl border-n-weak bg-n-solid-1">
            <p class="text-[11px] uppercase tracking-wide text-n-slate-10">
              {{ t('CAPTAIN_RAMON.EXECUCOES.TOTAL_24H') }}
            </p>
            <p class="text-2xl font-semibold text-n-slate-12">
              {{ resumo.total_24h ?? 0 }}
            </p>
          </div>
          <div class="p-4 border rounded-xl border-n-weak bg-n-solid-1">
            <p class="text-[11px] uppercase tracking-wide text-n-slate-10">
              {{ t('CAPTAIN_RAMON.EXECUCOES.ERROS_24H') }}
            </p>
            <p
              class="text-2xl font-semibold"
              :class="resumo.erros_24h ? 'text-n-ruby-11' : 'text-n-slate-12'"
            >
              {{ resumo.erros_24h ?? 0 }}
            </p>
          </div>
          <div class="p-4 border rounded-xl border-n-weak bg-n-solid-1">
            <p class="text-[11px] uppercase tracking-wide text-n-slate-10">
              {{ t('CAPTAIN_RAMON.EXECUCOES.TOOLS_USADAS') }}
            </p>
            <p class="text-2xl font-semibold text-n-slate-12">
              {{ Object.keys(resumo.por_tool || {}).length }}
            </p>
          </div>
        </div>

        <div class="flex flex-wrap gap-2 mt-5">
          <select
            v-model="filtroTool"
            data-testid="execucoes-filtro-tool"
            class="px-2 py-1 text-xs border rounded-lg border-n-weak bg-n-solid-2 text-n-slate-11"
            @change="fetchData"
          >
            <option value="">
              {{ t('CAPTAIN_RAMON.EXECUCOES.ALL_TOOLS') }}
            </option>
            <option v-for="tool in tools" :key="tool" :value="tool">
              {{ tool }}
            </option>
          </select>
          <select
            v-model="filtroStatus"
            class="px-2 py-1 text-xs border rounded-lg border-n-weak bg-n-solid-2 text-n-slate-11"
            @change="fetchData"
          >
            <option value="">
              {{ t('CAPTAIN_RAMON.EXECUCOES.ALL_STATUS') }}
            </option>
            <option value="ok">
              {{ t('CAPTAIN_RAMON.EXECUCOES.STATUS_OK') }}
            </option>
            <option value="erro">
              {{ t('CAPTAIN_RAMON.EXECUCOES.STATUS_ERRO') }}
            </option>
          </select>
        </div>

        <p v-if="loading" class="mt-6 text-sm text-n-slate-10">
          {{ t('CAPTAIN_RAMON.LOADING') }}
        </p>
        <p
          v-else-if="!items.length"
          data-testid="execucoes-vazio"
          class="mt-6 text-sm text-n-slate-10"
        >
          {{ t('CAPTAIN_RAMON.EXECUCOES.EMPTY') }}
        </p>

        <div v-else class="flex flex-col gap-2 mt-4">
          <div
            v-for="run in items"
            :key="run.id"
            data-testid="execucoes-linha"
            class="px-4 py-3 border rounded-xl border-n-weak bg-n-solid-1"
          >
            <div class="flex items-center gap-2">
              <span
                class="px-2 py-0.5 text-[10px] font-semibold rounded-full uppercase"
                :class="
                  run.status === 'erro'
                    ? 'bg-n-ruby-3 text-n-ruby-11'
                    : 'bg-n-teal-3 text-n-teal-11'
                "
              >
                {{ run.status }}
              </span>
              <span class="text-sm font-medium text-n-slate-12">
                {{ run.tool_name }}
              </span>
              <span class="ml-auto text-[11px] text-n-slate-9">
                {{ linhaTempo(run) }}
              </span>
            </div>
            <p class="mt-1 text-xs text-n-slate-11">
              {{ paramsResumo(run) }}{{ linhaCaso(run) }}
            </p>
            <button
              type="button"
              class="mt-1 text-[11px] text-n-iris-11 hover:underline"
              @click="toggle(run.id)"
            >
              {{
                aberto === run.id
                  ? t('CAPTAIN_RAMON.EXECUCOES.HIDE_RESULT')
                  : t('CAPTAIN_RAMON.EXECUCOES.SHOW_RESULT')
              }}
            </button>
            <div
              v-if="aberto === run.id"
              class="p-2 mt-1 overflow-auto font-mono text-[11px] whitespace-pre-wrap rounded-lg bg-n-solid-2 text-n-slate-11 max-h-64"
            >
              {{ run.resultado }}
            </div>
          </div>
        </div>
      </template>
    </div>
  </section>
</template>
