<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  camposEditaveis,
  definirTexto,
} from 'dashboard/routes/dashboard/ramon/helpers/planejamentoTextos';
import {
  AVISO,
  TEXTAREA,
  TITULO,
  TOM,
} from 'dashboard/routes/dashboard/ramon/helpers/ui';

// `dados` é o objeto reativo do pai; editado no lugar (sem evento).
const props = defineProps({ dados: { type: Object, required: true } });
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

const grupos = computed(() => {
  const porSecao = new Map();
  camposEditaveis(props.dados).forEach(c => {
    if (!porSecao.has(c.secao)) porSecao.set(c.secao, []);
    porSecao.get(c.secao).push({ ...c, id: c.caminho.join('.') });
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
      class="flex flex-col gap-2"
      :data-testid="`planejamento-secao-${g.secao}`"
    >
      <h4 :class="TITULO">
        {{ TITULOS[g.secao] }}
      </h4>
      <p v-if="g.secao === SO_ADVOGADO" :class="[AVISO, TOM.amber]">
        {{ t('RAMON.SIMULADOR.PLANEJAMENTO_SO_ADVOGADO') }}
      </p>
      <textarea
        v-for="c in g.campos"
        :key="c.id"
        :class="TEXTAREA"
        :rows="linhas(c.valor)"
        :value="c.valor"
        :data-testid="`planejamento-texto-${c.id}`"
        @input="definirTexto(dados, c.caminho, $event.target.value)"
      />
    </section>
  </div>
</template>
