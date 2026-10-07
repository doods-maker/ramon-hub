<script setup>
// Aba "Agente Claude" das Execuções (I-EX4): a trilha que o runner da VPS grava
// em agente_execucoes a cada pedido numa nota — pedido, resposta, ações,
// duração — e o uso do teto do dia. Leitura pura; o custo fica em Uso e custo.
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import RamonAgenteExecucoesAPI from 'dashboard/api/ramonAgenteExecucoes';
import {
  CARTAO,
  CHIP,
  TITULO,
  TOM,
} from 'dashboard/routes/dashboard/ramon/helpers/ui';
import { LINK, STATUS_TOM, fmtHora, rotuloCaso, useAbrir } from './execucoes';

defineOptions({ name: 'CaptainExecucoesAgente' });

const { t } = useI18n();
const { abrirCaso, abrirConversa } = useAbrir();

const data = ref(null);
const loading = ref(true);
const error = ref(false);
const aberto = ref(null);

const fetchData = async () => {
  loading.value = true;
  error.value = false;
  try {
    const response = await RamonAgenteExecucoesAPI.list();
    data.value = response.data;
  } catch (e) {
    error.value = true;
  } finally {
    loading.value = false;
  }
};
onMounted(fetchData);

const resumo = computed(
  () => data.value?.resumo ?? { hoje: 0, teto: 0, problemas_hoje: 0 }
);
const items = computed(() => data.value?.items ?? []);

// texto montado no script: o template não aceita string crua (eslint i18n)
const meta = item =>
  [
    fmtHora(item.created_at),
    item.duracao_ms == null ? null : `${Math.round(item.duracao_ms / 1000)} s`,
    [item.modelo, item.esforco].filter(Boolean).join(' · ') || null,
  ]
    .filter(Boolean)
    .join(' · ');
const acaoTexto = acao => `${acao.tipo} → ${acao.ref}`;
const toggle = id => {
  aberto.value = aberto.value === id ? null : id;
};
</script>

<template>
  <div>
    <p class="text-sm text-n-slate-10">
      {{ t('INTEL.EXECUCOES.AGENTE.SUBTITULO') }}
    </p>

    <div
      v-if="error"
      data-testid="agente-erro"
      class="mt-4 text-sm"
      :class="CARTAO"
    >
      <p class="text-n-ruby-11">{{ t('CAPTAIN_RAMON.LOAD_ERROR') }}</p>
      <button type="button" class="mt-1" :class="LINK" @click="fetchData">
        {{ t('CAPTAIN_RAMON.RETRY') }}
      </button>
    </div>
    <p v-else-if="loading" class="mt-4 text-sm text-n-slate-10">
      {{ t('CAPTAIN_RAMON.LOADING') }}
    </p>

    <template v-else>
      <div class="flex flex-wrap gap-1.5 mt-4">
        <span data-testid="agente-hoje" :class="[CHIP, TOM.blue]">
          {{
            t('INTEL.EXECUCOES.AGENTE.HOJE', {
              n: resumo.hoje,
              teto: resumo.teto,
            })
          }}
        </span>
        <span v-if="resumo.problemas_hoje" :class="[CHIP, TOM.ruby]">
          {{
            t('INTEL.EXECUCOES.AGENTE.PROBLEMAS', { n: resumo.problemas_hoje })
          }}
        </span>
      </div>

      <p
        v-if="!items.length"
        data-testid="agente-vazio"
        class="mt-4 text-sm text-n-slate-10"
      >
        {{ t('INTEL.EXECUCOES.AGENTE.VAZIO') }}
      </p>
      <ul v-else class="flex flex-col gap-2 mt-4 list-none">
        <li
          v-for="item in items"
          :key="item.id"
          data-testid="agente-linha"
          :class="CARTAO"
        >
          <div class="flex flex-wrap items-center gap-2">
            <span :class="[CHIP, STATUS_TOM[item.status] || TOM.slate]">
              {{ t(`INTEL.EXECUCOES.STATUS.${item.status}`) }}
            </span>
            <span class="ml-auto text-[11px] text-n-slate-10">
              {{ meta(item) }}
            </span>
          </div>
          <p
            class="mt-1 text-sm text-n-slate-12 whitespace-pre-line line-clamp-3"
          >
            {{ item.pedido }}
          </p>
          <div class="flex flex-wrap items-center gap-3 mt-1">
            <button
              v-if="item.lead_id"
              type="button"
              data-testid="execucoes-caso"
              :class="LINK"
              @click="abrirCaso(item.lead_id)"
            >
              {{ rotuloCaso(t, item) }}
            </button>
            <button
              v-if="item.conversa_display_id"
              type="button"
              data-testid="execucoes-conversa"
              :class="LINK"
              @click="abrirConversa(item.conversa_display_id)"
            >
              {{
                t('INTEL.EXECUCOES.CONVERSA', { id: item.conversa_display_id })
              }}
            </button>
            <button
              type="button"
              data-testid="agente-ver"
              :class="LINK"
              @click="toggle(item.id)"
            >
              {{
                aberto === item.id
                  ? t('INTEL.EXECUCOES.AGENTE.ESCONDER')
                  : t('INTEL.EXECUCOES.AGENTE.VER_RESULTADO')
              }}
            </button>
          </div>
          <div
            v-if="aberto === item.id"
            data-testid="agente-detalhe"
            class="flex flex-col gap-2 mt-2"
          >
            <p
              class="p-2 overflow-auto text-xs whitespace-pre-wrap rounded-lg bg-n-alpha-2 text-n-slate-11 max-h-64"
            >
              {{ item.resumo || t('INTEL.EXECUCOES.AGENTE.SEM_RESUMO') }}
            </p>
            <p :class="TITULO">{{ t('INTEL.EXECUCOES.AGENTE.ACOES') }}</p>
            <ul
              v-if="(item.acoes || []).length"
              class="flex flex-col gap-1 list-none"
            >
              <li
                v-for="(acao, posicao) in item.acoes"
                :key="posicao"
                class="text-xs break-all text-n-slate-11"
              >
                {{ acaoTexto(acao) }}
              </li>
            </ul>
            <p v-else class="text-xs text-n-slate-10">
              {{ t('INTEL.EXECUCOES.AGENTE.NENHUMA_ACAO') }}
            </p>
          </div>
        </li>
      </ul>
    </template>
  </div>
</template>
