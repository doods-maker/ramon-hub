<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import {
  camposEditaveis,
  definirTexto,
} from 'dashboard/routes/dashboard/ramon/helpers/planejamentoTextos';
import {
  CHIP,
  TEXTAREA,
  TITULO,
  TOM,
} from 'dashboard/routes/dashboard/ramon/helpers/ui';

// `dados` é o objeto reativo do pai; editado no lugar (sem evento).
// Abre em leitura (como sai no PDF); "Editar" troca só aquela seção por caixas.
const props = defineProps({
  dados: { type: Object, required: true },
  secoes: { type: Array, default: null }, // null = todas as editáveis
  editavel: { type: Boolean, default: true },
});
const { t } = useI18n();

const SO_ADVOGADO = 'observacoes_internas';
// chaves literais (sem chave dinâmica no i18n), uma por SECOES_EDITAVEIS
const TITULOS = computed(() => ({
  pendencias: t('RAMON.SIMULADOR.PLANEJAMENTO_SECAO_PENDENCIAS'),
  observacoes_internas: t(
    'RAMON.SIMULADOR.PLANEJAMENTO_SECAO_OBSERVACOES_INTERNAS'
  ),
  pode: t('RAMON.SIMULADOR.PLANEJAMENTO_SECAO_PODE'),
  nao_pode: t('RAMON.SIMULADOR.PLANEJAMENTO_SECAO_NAO_PODE'),
  sugestao: t('RAMON.SIMULADOR.PLANEJAMENTO_SECAO_SUGESTAO'),
  cenarios: t('RAMON.SIMULADOR.PLANEJAMENTO_SECAO_CENARIOS'),
  melhorias: t('RAMON.SIMULADOR.PLANEJAMENTO_SECAO_MELHORIAS'),
  passos: t('RAMON.SIMULADOR.PLANEJAMENTO_SECAO_PASSOS'),
  conferir: t('RAMON.SIMULADOR.PLANEJAMENTO_SECAO_CONFERIR'),
  documentos: t('RAMON.SIMULADOR.PLANEJAMENTO_SECAO_DOCUMENTOS'),
}));

const editando = ref(new Set());
const alternar = secao => {
  if (editando.value.has(secao)) editando.value.delete(secao);
  else editando.value.add(secao);
};

// rótulo do motor ao lado do título (impacto da pendência: "pode tirar tempo")
const rotulo = c => {
  if (c.caminho.at(-1) !== 't') return null;
  const item = c.caminho.slice(0, -1).reduce((no, k) => no?.[k], props.dados);
  return typeof item?.imp === 'string' ? item.imp : null;
};

const grupos = computed(() => {
  const porSecao = new Map();
  camposEditaveis(props.dados).forEach(c => {
    if (props.secoes && !props.secoes.includes(c.secao)) return;
    if (!porSecao.has(c.secao)) porSecao.set(c.secao, []);
    porSecao.get(c.secao).push({
      ...c,
      id: c.caminho.join('.'),
      destaque: ['t', 'titulo'].includes(c.caminho.at(-1)),
      rotulo: rotulo(c),
    });
  });
  return [...porSecao].map(([secao, campos]) => ({ secao, campos }));
});

const linhas = valor => Math.min(8, Math.max(2, Math.ceil(valor.length / 70)));
</script>

<template>
  <div class="flex flex-col gap-4">
    <section
      v-for="g in grupos"
      :key="g.secao"
      class="flex flex-col gap-1.5"
      :data-testid="`planejamento-secao-${g.secao}`"
    >
      <div class="flex items-center justify-between gap-2">
        <h4 class="mb-0" :class="TITULO">
          {{ TITULOS[g.secao] }}
          <span
            v-if="g.secao === SO_ADVOGADO"
            class="normal-case tracking-normal font-normal"
          >
            {{ `· ${t('RAMON.SIMULADOR.PLANEJAMENTO_SO_ADVOGADO')}` }}
          </span>
        </h4>
        <Button
          v-if="editavel"
          link
          xs
          :data-testid="`planejamento-editar-${g.secao}`"
          :label="
            editando.has(g.secao)
              ? t('RAMON.SIMULADOR.PLANEJAMENTO_EDITAR_PRONTO')
              : t('RAMON.SIMULADOR.PLANEJAMENTO_EDITAR')
          "
          @click="alternar(g.secao)"
        />
      </div>
      <template v-if="editando.has(g.secao)">
        <textarea
          v-for="c in g.campos"
          :key="c.id"
          :class="TEXTAREA"
          :rows="linhas(c.valor)"
          :value="c.valor"
          :data-testid="`planejamento-texto-${c.id}`"
          @input="definirTexto(dados, c.caminho, $event.target.value)"
        />
      </template>
      <div v-else class="flex flex-col gap-1">
        <p
          v-for="c in g.campos"
          :key="c.id"
          class="mb-0 whitespace-pre-line text-sm"
          :class="
            c.destaque
              ? 'mt-1 font-medium text-n-slate-12 first:mt-0'
              : 'text-n-slate-11'
          "
        >
          {{ c.valor }}
          <span
            v-if="c.rotulo"
            class="ms-1 align-middle"
            :class="[CHIP, TOM.amber]"
          >
            {{ c.rotulo }}
          </span>
        </p>
      </div>
    </section>
  </div>
</template>
