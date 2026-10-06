<script setup>
// Um passo no quadro (mockup .no): ícone colorido por categoria, título,
// detalhe, selo "sai como rascunho"; porta de entrada em cima e uma porta de
// saída por saída possível (sim/não, um por caso + outro) embaixo.
import { computed, nextTick, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { Handle, Position, useVueFlow } from '@vue-flow/core';
import { useMapGetter } from 'dashboard/composables/store';
import { CHIP, TOM } from 'dashboard/routes/dashboard/ramon/helpers/ui';
import { PASSOS, gatilhoInfo, saidasDe } from './fluxo';

const props = defineProps({
  id: { type: String, required: true },
  tipo: { type: String, required: true },
  config: { type: Object, default: () => ({}) },
  estado: { type: String, default: '' },
  somenteLeitura: { type: Boolean, default: false },
  folha: { type: Boolean, default: false },
  saidaTomada: { type: String, default: null },
});
const emit = defineEmits(['adicionar']);

const K = 'CAPTAIN_RAMON.FLUXOS';
const { t } = useI18n();
const etapas = useMapGetter('leadConfig/getStages');
const caixas = useMapGetter('inboxes/getInboxes');

const MOLDURA = {
  '': 'border-n-weak hover:border-n-slate-8',
  selecionado: 'border-n-blue-9 ring-4 ring-n-blue-9/10',
  erro: 'border-n-ruby-9 ring-4 ring-n-ruby-9/10',
  aceso: 'border-n-teal-9',
  atual: 'border-n-amber-9 ring-4 ring-n-amber-9/10',
  apagado: 'border-n-weak opacity-40',
};
const PORTA =
  '!h-2.5 !w-2.5 !min-h-0 !min-w-0 !rounded-full !border-2 !border-n-slate-7 !bg-n-solid-1';

const gatilho = computed(() => props.tipo === 'gatilho');
const info = computed(() => PASSOS[props.tipo] || PASSOS.parar);
const icone = computed(() =>
  gatilho.value
    ? gatilhoInfo(props.config.tipo)?.icone || info.value.icone
    : info.value.icone
);
const saidas = computed(() => saidasDe(props.tipo, props.config));
// porta nova/apagada (casos do escolha): o Vue Flow remede as portas do passo
const { updateNodeInternals } = useVueFlow();
watch(
  () => saidas.value.join(),
  () => nextTick(() => updateNodeInternals([props.id]))
);
const titulo = computed(() => {
  if (props.config.rotulo) return props.config.rotulo;
  if (gatilho.value)
    return props.config.tipo
      ? t(`${K}.GATILHOS.${props.config.tipo}`)
      : t(`${K}.PASSOS.gatilho`);
  return t(`${K}.PASSOS.${props.tipo}`);
});

const nomes = (lista, ids, campo = 'name') =>
  lista
    .filter(x => (ids || []).includes(x.id))
    .map(x => x[campo])
    .join(', ');
const curto = texto =>
  texto && texto.length > 48 ? `${texto.slice(0, 47)}…` : texto || '';

const detalhe = computed(() => {
  const c = props.config;
  switch (props.tipo) {
    case 'gatilho':
      if (['relogio', 'lead_parado'].includes(c.tipo))
        return t(`${K}.NO.AS_HORA`, {
          quando: c.hora || (c.tipo === 'lead_parado' ? '11:00' : '—'),
        });
      if (c.tipo === 'evento_advbox')
        return (
          (c.regras || []).map(r => t(`${K}.REGRAS_ADVBOX.${r}`)).join(', ') ||
          t(`${K}.NO.QUALQUER_EVENTO`)
        );
      if (c.tipo === 'lead_mudou_etapa') {
        return c.para_etapa_ids?.length
          ? t(`${K}.NO.PARA`, { etapas: nomes(etapas.value, c.para_etapa_ids) })
          : t(`${K}.NO.QUALQUER_ETAPA`);
      }
      return c.caixa_ids?.length
        ? t(`${K}.NO.CAIXAS`, { caixas: nomes(caixas.value, c.caixa_ids) })
        : '';
    case 'se':
      return t(`${K}.NO.CONDICOES`, { n: (c.condicoes || []).length });
    case 'escolha':
      return c.campo ? t(`${K}.CAMPOS.${c.campo}`) : '';
    case 'mover_etapa':
      return nomes(etapas.value, [c.etapa_id]);
    case 'criar_tarefa':
      return curto(c.titulo);
    case 'esperar':
      return c.ate === 'horario_comercial'
        ? t(`${K}.PAINEL.ESPERAR_HORARIO`)
        : `${c.quantidade ?? ''} ${c.unidade ? t(`${K}.UNIDADES.${c.unidade}`) : ''}`;
    case 'acao_chatwoot':
      return (c.acoes || [])
        .map(a => t(`${K}.ACOES_CHATWOOT.${a.action_name}`, a.action_name))
        .join(', ');
    case 'perguntar_ia':
      return curto(c.pergunta);
    case 'rascunho_ia':
    case 'rodar_skill':
      return curto(c.instrucao);
    case 'advbox':
      return c.acao ? t(`${K}.PAINEL.ADVBOX_ACOES.${c.acao}`) : '';
    case 'webhook':
      // só o host: o caminho/query pode levar token do hook
      return c.url?.match(/^https?:\/\/([^/?#]+)/)?.[1] || '';
    case 'trocar_responsavel':
      return c.papel ? t(`${K}.PAPEIS.${c.papel}`) : '';
    case 'preencher_campo':
      return c.chave || '';
    case 'parar':
      return '';
    default:
      return curto(c.texto);
  }
});

const rotuloSaida = saida => {
  if (['sim', 'nao', 'outro'].includes(saida)) return t(`${K}.SAIDAS.${saida}`);
  return (
    (props.config.casos || []).find(c => c.chave === saida)?.rotulo || saida
  );
};
</script>

<template>
  <div
    class="relative w-[212px] rounded-xl border bg-n-solid-1 px-3 py-2.5 shadow-sm"
    :class="[MOLDURA[estado], gatilho ? 'border-l-4 !border-l-n-blue-9' : '']"
    :data-testid="`no-${id}`"
  >
    <Handle
      v-if="!gatilho"
      id="e"
      type="target"
      :position="Position.Top"
      :connectable="!somenteLeitura"
      :class="PORTA"
    />
    <div class="mb-1.5 flex items-center gap-2 text-[11.5px] text-n-slate-10">
      <span
        class="grid size-6 shrink-0 place-items-center rounded-md"
        :class="TOM[info.tom]"
      >
        <i :class="icone" class="size-3.5" />
      </span>
      {{ t(`${K}.CABECALHO.${tipo}`, tipo) }}
      <i
        v-if="estado === 'aceso'"
        class="i-lucide-check ml-auto size-3.5 text-n-teal-11"
      />
    </div>
    <b class="block text-[13.5px] font-medium leading-snug text-n-slate-12">
      {{ titulo }}
    </b>
    <span v-if="detalhe" class="mt-0.5 block truncate text-xs text-n-slate-11">
      {{ detalhe }}
    </span>
    <span
      v-if="info.rascunho"
      :class="[CHIP, TOM.amber]"
      class="mt-1.5 font-mono"
    >
      {{ t(`${K}.NO.SAI_RASCUNHO`) }}
    </span>

    <div
      v-if="saidas.length"
      class="absolute inset-x-0 top-full flex justify-around"
    >
      <div
        v-for="saida in saidas"
        :key="saida"
        class="flex flex-col items-center"
      >
        <Handle
          :id="saida"
          type="source"
          :position="Position.Bottom"
          :connectable="!somenteLeitura"
          :class="PORTA"
          class="!static !-mt-[5px] !transform-none"
        />
        <span
          v-if="saidas.length > 1"
          class="mt-0.5 max-w-[64px] truncate font-mono text-[10.5px]"
          :class="
            estado === 'aceso' && saida === saidaTomada
              ? 'text-n-teal-11'
              : 'text-n-slate-10'
          "
        >
          {{ rotuloSaida(saida) }}
        </span>
      </div>
    </div>
    <!-- mockup .mais: "+" tracejado embaixo do passo que ainda não leva a nada -->
    <button
      v-if="folha && saidas.length && !somenteLeitura"
      type="button"
      class="nodrag absolute left-1/2 top-full mt-6 grid size-5 -translate-x-1/2 place-items-center rounded-md border border-dashed border-n-slate-7 bg-n-solid-1 text-n-slate-10 hover:border-n-blue-9 hover:text-n-blue-11"
      :title="t(`${K}.EDITOR.ADICIONAR`)"
      :data-testid="`no-${id}-mais`"
      @click="emit('adicionar')"
    >
      <i class="i-lucide-plus size-3" />
    </button>
  </div>
</template>
