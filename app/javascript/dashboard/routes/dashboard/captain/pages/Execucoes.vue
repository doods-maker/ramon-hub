<script setup>
// Tela Execuções: o log auditável do que a IA executou — ferramenta, dados, o
// que voltou, duração — com o caso, a conversa e o assistente de cada linha
// (I-EX2). Leitura pura.
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import CaptainToolRunsAPI from 'dashboard/api/captainToolRuns';
import {
  CARTAO,
  CHIP,
  SELECT,
  TITULO,
  TOM,
} from 'dashboard/routes/dashboard/ramon/helpers/ui';
import { ferramentaInfo } from 'dashboard/routes/dashboard/ramon/helpers/ferramentas';
import { LINK, STATUS_TOM, fmtHora, rotuloCaso, useAbrir } from './execucoes';

defineOptions({ name: 'CaptainExecucoes' });

const { t } = useI18n();
const { abrirCaso, abrirConversa } = useAbrir();

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
const catalogo = computed(() => data.value?.catalogo ?? []);
const ferramenta = id => ferramentaInfo(id, catalogo.value);
const nivelLabel = nivel =>
  ({
    consulta: t('CAPTAIN_RAMON.NIVEL.consulta'),
    sugestao: t('CAPTAIN_RAMON.NIVEL.sugestao'),
    rascunho: t('CAPTAIN_RAMON.NIVEL.rascunho'),
    interna: t('CAPTAIN_RAMON.NIVEL.interna'),
  })[nivel];

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
        class="mt-4 text-sm"
        :class="CARTAO"
      >
        <p class="text-n-ruby-11">{{ t('CAPTAIN_RAMON.LOAD_ERROR') }}</p>
        <button type="button" class="mt-1" :class="LINK" @click="fetchData">
          {{ t('CAPTAIN_RAMON.RETRY') }}
        </button>
      </div>

      <template v-else>
        <div class="grid grid-cols-2 gap-3 mt-5 sm:grid-cols-3">
          <div :class="CARTAO">
            <p :class="TITULO">{{ t('CAPTAIN_RAMON.EXECUCOES.TOTAL_24H') }}</p>
            <p class="mt-1 text-2xl font-semibold text-n-slate-12">
              {{ resumo.total_24h ?? 0 }}
            </p>
          </div>
          <div :class="CARTAO">
            <p :class="TITULO">{{ t('CAPTAIN_RAMON.EXECUCOES.ERROS_24H') }}</p>
            <p
              class="mt-1 text-2xl font-semibold"
              :class="resumo.erros_24h ? 'text-n-ruby-11' : 'text-n-slate-12'"
            >
              {{ resumo.erros_24h ?? 0 }}
            </p>
          </div>
          <div :class="CARTAO">
            <p :class="TITULO">
              {{ t('CAPTAIN_RAMON.EXECUCOES.TOOLS_USADAS') }}
            </p>
            <p class="mt-1 text-2xl font-semibold text-n-slate-12">
              {{ Object.keys(resumo.por_tool || {}).length }}
            </p>
          </div>
        </div>

        <div class="flex flex-wrap gap-2 mt-5">
          <select
            v-model="filtroTool"
            data-testid="execucoes-filtro-tool"
            class="!w-60"
            :class="SELECT"
            @change="fetchData"
          >
            <option value="">
              {{ t('CAPTAIN_RAMON.EXECUCOES.ALL_TOOLS') }}
            </option>
            <option v-for="tool in tools" :key="tool" :value="tool">
              {{ ferramenta(tool).title }}
            </option>
          </select>
          <select
            v-model="filtroStatus"
            class="!w-44"
            :class="SELECT"
            @change="fetchData"
          >
            <option value="">
              {{ t('CAPTAIN_RAMON.EXECUCOES.ALL_STATUS') }}
            </option>
            <option value="ok">{{ t('INTEL.EXECUCOES.STATUS.ok') }}</option>
            <option value="erro">{{ t('INTEL.EXECUCOES.STATUS.erro') }}</option>
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

        <ul v-else class="flex flex-col gap-2 mt-4 list-none">
          <li
            v-for="run in items"
            :key="run.id"
            data-testid="execucoes-linha"
            :class="CARTAO"
          >
            <div class="flex flex-wrap items-center gap-2">
              <span :class="[CHIP, STATUS_TOM[run.status] || TOM.slate]">
                {{ t(`INTEL.EXECUCOES.STATUS.${run.status}`) }}
              </span>
              <span class="text-sm font-medium text-n-slate-12">
                {{ ferramenta(run.tool_name).title }}
              </span>
              <span
                v-if="ferramenta(run.tool_name).nivel"
                data-testid="execucoes-nivel"
                :class="[CHIP, ferramenta(run.tool_name).tom]"
              >
                {{ nivelLabel(ferramenta(run.tool_name).nivel) }}
              </span>
              <span
                v-if="run.assistente_nome"
                data-testid="execucoes-assistente"
                :class="[CHIP, TOM.slate]"
              >
                {{ run.assistente_nome }}
              </span>
              <span class="ml-auto text-[11px] text-n-slate-10">
                {{ linhaTempo(run) }}
              </span>
            </div>
            <p class="mt-1 text-xs text-n-slate-11">{{ paramsResumo(run) }}</p>
            <div class="flex flex-wrap items-center gap-3 mt-1">
              <button
                v-if="run.lead_id"
                type="button"
                data-testid="execucoes-caso"
                :class="LINK"
                @click="abrirCaso(run.lead_id)"
              >
                {{ rotuloCaso(t, run) }}
              </button>
              <button
                v-if="run.conversa_display_id"
                type="button"
                data-testid="execucoes-conversa"
                :class="LINK"
                @click="abrirConversa(run.conversa_display_id)"
              >
                {{
                  t('INTEL.EXECUCOES.CONVERSA', { id: run.conversa_display_id })
                }}
              </button>
              <button type="button" :class="LINK" @click="toggle(run.id)">
                {{
                  aberto === run.id
                    ? t('CAPTAIN_RAMON.EXECUCOES.HIDE_RESULT')
                    : t('CAPTAIN_RAMON.EXECUCOES.SHOW_RESULT')
                }}
              </button>
            </div>
            <div
              v-if="aberto === run.id"
              class="p-2 mt-2 overflow-auto font-mono text-[11px] whitespace-pre-wrap rounded-lg bg-n-alpha-2 text-n-slate-11 max-h-64"
            >
              {{ run.resultado }}
            </div>
          </li>
        </ul>
      </template>
    </div>
  </section>
</template>
