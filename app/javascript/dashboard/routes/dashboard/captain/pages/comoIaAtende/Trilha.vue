<script setup>
// Trilha das Etapas abertas com o Marcador (até onde a IA vai sozinha). O Marcador é um
// <input type="range"> nativo: arrastar, clicar e teclado de graça; encaixa entre as Etapas.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { CARTAO, CHIP } from 'dashboard/routes/dashboard/ramon/helpers/ui';
import {
  COR_DO_ESTADO,
  TOM_DO_ESTADO,
  estadoDaEtapa,
  frase,
  marcadorDaPosicao,
  posicaoDoMarcador,
} from 'dashboard/routes/dashboard/ramon/helpers/perfilIa';

const props = defineProps({
  etapas: { type: Array, required: true },
  marcador: { type: String, required: true },
  selecionada: { type: String, default: '' },
  travada: { type: Boolean, default: false },
});
const emit = defineEmits(['update:marcador', 'update:selecionada']);
const { t } = useI18n();
const K = 'RAMON.COMO_IA.TRILHA';

// Pino de 6px: as barras e as colunas ficam recuadas 3px (px-[3px]) para o centro do pino
// cair exatamente na divisa entre as Etapas.
const PINO =
  'reset-base relative block h-8 w-full cursor-grab appearance-none rounded-md bg-transparent active:cursor-grabbing disabled:cursor-not-allowed focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-blue-9 [&::-webkit-slider-thumb]:h-7 [&::-webkit-slider-thumb]:w-1.5 [&::-webkit-slider-thumb]:appearance-none [&::-webkit-slider-thumb]:rounded-full [&::-webkit-slider-thumb]:bg-n-slate-12 [&::-moz-range-thumb]:h-7 [&::-moz-range-thumb]:w-1.5 [&::-moz-range-thumb]:rounded-full [&::-moz-range-thumb]:border-0 [&::-moz-range-thumb]:bg-n-slate-12 [&::-moz-range-track]:bg-transparent';

const total = computed(() => props.etapas.length);
const posicao = computed(() => posicaoDoMarcador(props.marcador, props.etapas));
const estados = computed(() =>
  props.etapas.map(e => estadoDaEtapa(e.chave, props.marcador, props.etapas))
);
const rotulo = computed(() => {
  if (posicao.value === 0) return t(`${K}.NADA`);
  if (posicao.value === total.value) return t(`${K}.FIM`);
  return t(`${K}.ATE_AQUI`);
});
// O rótulo do Marcador mora na coluna logo depois dele (na última, quando vai até o fim).
const colunaDoRotulo = computed(() => Math.min(posicao.value, total.value - 1));
const ancora = computed(() => {
  if (posicao.value === 0) return 'left-0';
  if (posicao.value === total.value) return 'right-0';
  return 'left-0 -translate-x-1/2';
});
const valorTexto = computed(() =>
  posicao.value ? props.etapas[posicao.value - 1].nome : t(`${K}.NENHUMA`)
);

const irPara = nova => {
  const limitada = Math.max(0, Math.min(total.value, nova));
  if (limitada !== posicao.value)
    emit('update:marcador', marcadorDaPosicao(limitada, props.etapas));
};
// Setas: uma Etapa por toque, igual em todo navegador (o resto do teclado fica com o nativo).
const PASSO = { ArrowLeft: -1, ArrowRight: 1 };
const tecla = ev => {
  if (!(ev.key in PASSO)) return;
  ev.preventDefault();
  irPara(posicao.value + PASSO[ev.key]);
};
</script>

<template>
  <div>
    <div :class="CARTAO" class="!px-5 !pb-0 !pt-5">
      <div class="flex h-7 px-[3px]" aria-hidden="true">
        <span v-for="(e, i) in etapas" :key="e.chave" class="relative flex-1">
          <span
            v-if="i === colunaDoRotulo"
            class="absolute bottom-1.5 flex items-center gap-1 whitespace-nowrap rounded-full bg-n-slate-12 px-2 py-1 text-[11.5px] font-medium leading-none text-n-solid-1"
            :class="ancora"
          >
            <span class="i-lucide-bot size-3" />
            {{ rotulo }}
          </span>
        </span>
      </div>
      <div class="relative h-8">
        <div
          class="pointer-events-none absolute inset-x-[3px] top-1/2 flex h-1 -translate-y-1/2 gap-0.5"
          aria-hidden="true"
        >
          <span
            v-for="(e, i) in etapas"
            :key="e.chave"
            class="flex-1 rounded-full"
            :class="COR_DO_ESTADO[estados[i]]"
          />
        </div>
        <input
          type="range"
          min="0"
          :max="total"
          step="1"
          :value="posicao"
          :disabled="travada"
          :aria-label="t(`${K}.ROTULO`)"
          :aria-valuetext="valorTexto"
          data-testid="marcador"
          :class="PINO"
          @input="irPara(Number($event.target.value))"
          @keydown="tecla"
        />
      </div>
      <div class="mt-1 flex px-[3px]">
        <button
          v-for="(e, i) in etapas"
          :key="e.chave"
          type="button"
          :data-testid="`etapa-${e.chave}`"
          :aria-pressed="e.chave === selecionada"
          class="min-w-0 flex-1 border-b-2 border-solid px-1 pb-3.5 pt-2 text-center"
          :class="
            e.chave === selecionada
              ? 'border-n-slate-12'
              : 'border-transparent hover:border-n-weak'
          "
          @click="emit('update:selecionada', e.chave)"
        >
          <span
            class="block truncate text-[13px] text-n-slate-12"
            :class="e.chave === selecionada ? 'font-semibold' : 'font-medium'"
          >
            {{ e.nome }}
          </span>
          <span class="mt-1.5" :class="[CHIP, TOM_DO_ESTADO[estados[i]]]">
            <span class="size-1.5 rounded-full bg-current" />
            {{ t(`RAMON.COMO_IA.ESTADO.${estados[i]}`) }}
          </span>
        </button>
      </div>
    </div>
    <p
      data-testid="frase"
      class="mt-3 flex gap-2.5 text-[13.5px] leading-relaxed text-n-slate-11"
    >
      <span
        class="i-lucide-message-square-text mt-0.5 size-4 shrink-0 text-n-slate-10"
        aria-hidden="true"
      />
      {{ frase(marcador, etapas, t) }}
    </p>
  </div>
</template>
