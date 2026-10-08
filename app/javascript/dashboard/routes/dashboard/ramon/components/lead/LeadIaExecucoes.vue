<script setup>
// "O que a IA fez neste caso" (I-X8): as ferramentas que a IA rodou e os pedidos ao agente Claude com este
// lead — as mesmas trilhas das Execuções, filtradas pelo caso (as 10 mais novas). Leitura pura.
import { onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import CaptainToolRunsAPI from 'dashboard/api/captainToolRuns';
import RamonAgenteExecucoesAPI from 'dashboard/api/ramonAgenteExecucoes';
import { CHIP, SECAO, TITULO, TOM } from '../../helpers/ui';
import { ferramentaInfo } from '../../helpers/ferramentas';
import {
  STATUS_TOM,
  fmtHora,
} from 'dashboard/routes/dashboard/captain/pages/execucoes';

const props = defineProps({
  leadId: { type: Number, required: true },
});

const VISIVEIS = 10;
const { t } = useI18n();
const linhas = ref([]);
const carregando = ref(true);
const erro = ref(false);

const carregar = async () => {
  carregando.value = true;
  erro.value = false;
  try {
    const [fer, age] = await Promise.allSettled([
      CaptainToolRunsAPI.list({ lead_id: props.leadId }),
      RamonAgenteExecucoesAPI.list({ lead_id: props.leadId }),
    ]);
    // uma fonte pode falhar (ex.: agente é só de admin); erro só se as duas falham
    erro.value = fer.status === 'rejected' && age.status === 'rejected';
    const catalogo = fer.value?.data.catalogo || [];
    linhas.value = [
      ...(fer.value?.data.items || []).map(run => ({
        id: `f${run.id}`,
        em: run.created_at,
        status: run.status,
        texto: ferramentaInfo(run.tool_name, catalogo).title,
      })),
      ...(age.value?.data.items || []).map(item => ({
        id: `a${item.id}`,
        em: item.created_at,
        status: item.status,
        texto: t('INTEL.CASO_IA.AGENTE', { nome: item.pedido }),
      })),
    ]
      .sort((x, y) => new Date(y.em) - new Date(x.em))
      .slice(0, VISIVEIS);
  } catch (e) {
    erro.value = true;
  } finally {
    carregando.value = false;
  }
};
onMounted(carregar);
watch(() => props.leadId, carregar);
</script>

<template>
  <section data-testid="caso-ia" :class="SECAO">
    <h3 :class="TITULO">{{ t('INTEL.CASO_IA.TITULO') }}</h3>
    <p v-if="erro" class="mt-2 text-xs text-n-ruby-11">
      {{ t('INTEL.CASO_IA.ERRO') }}
    </p>
    <p
      v-else-if="!carregando && !linhas.length"
      class="mt-2 text-xs text-n-slate-10"
    >
      {{ t('INTEL.CASO_IA.VAZIO') }}
    </p>
    <ul v-else class="flex flex-col gap-1.5 mt-2 list-none">
      <li
        v-for="linha in linhas"
        :key="linha.id"
        data-testid="caso-ia-linha"
        class="flex items-center gap-2 text-xs"
      >
        <span :class="[CHIP, STATUS_TOM[linha.status] || TOM.slate]">
          {{ t(`INTEL.EXECUCOES.STATUS.${linha.status}`) }}
        </span>
        <span class="flex-1 min-w-0 truncate text-n-slate-12">
          {{ linha.texto }}
        </span>
        <span class="shrink-0 text-[11px] text-n-slate-10">
          {{ fmtHora(linha.em) }}
        </span>
      </li>
    </ul>
  </section>
</template>
