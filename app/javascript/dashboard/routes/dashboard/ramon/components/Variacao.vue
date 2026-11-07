<script setup>
// "▲ 12 p.p. vs 01/10–18/10": variação de um número contra o período anterior
// (helpers/variacao). Seta + número + texto, nunca só a cor.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { variacao, rotuloAnterior } from '../helpers/variacao';

const props = defineProps({
  atual: { type: Number, default: null },
  anterior: { type: Number, default: null },
  unidade: { type: String, default: '' },
  sentido: { type: String, default: 'min' },
  // { inicio, fim } do período anterior, como o backend manda
  periodo: { type: Object, default: null },
});

const { t } = useI18n();

const COR = {
  teal: 'text-n-teal-11',
  ruby: 'text-n-ruby-11',
  slate: 'text-n-slate-11',
};
const SETA = { sobe: '▲', desce: '▼', igual: '=' };

const dado = computed(() =>
  variacao(props.atual, props.anterior, {
    unidade: props.unidade,
    sentido: props.sentido,
  })
);
const numero = computed(() => {
  const v = dado.value;
  if (v.seta === 'igual') return t('RAMON.VARIACAO.IGUAL');
  if (v.absoluto) return `${SETA[v.seta]} ${v.n}`;
  return `${SETA[v.seta]} ${t(v.pontos ? 'RAMON.VARIACAO.PONTOS' : 'RAMON.VARIACAO.PORCENTO', { n: v.n })}`;
});
const vs = computed(() => {
  const r = rotuloAnterior(props.periodo);
  return r ? t(`RAMON.VARIACAO.${r.chave}`, r.params) : '';
});
</script>

<template>
  <span
    v-if="dado"
    class="inline-flex items-baseline gap-1 text-[11.5px]"
    data-testid="variacao"
    :data-seta="dado.seta"
  >
    <span class="font-mono font-medium tabular-nums" :class="COR[dado.tom]">
      {{ numero }}
    </span>
    <span v-if="vs" class="text-n-slate-10">{{ vs }}</span>
  </span>
</template>
