<script setup>
// Se: lista de condições com E/OU (Ramon::Fluxos::Condicao.teste). Valores
// comparam sem acento e sem caixa; as sugestões vêm do que existe no hub.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import Button from 'dashboard/components-next/button/Button.vue';
import {
  CAMPO,
  ROTULO,
  SELECT,
} from 'dashboard/routes/dashboard/ramon/helpers/ui';
import { CAMPOS, OPERADORES, SEM_VALOR } from './fluxo';
import JanelaHorario from './JanelaHorario.vue';

const props = defineProps({ config: { type: Object, required: true } });
const emit = defineEmits(['update:config']);
const K = 'CAPTAIN_RAMON.FLUXOS';
const { t } = useI18n();
const etapas = useMapGetter('leadConfig/getStages');
const teses = useMapGetter('theses/getTheses');
const caixas = useMapGetter('inboxes/getInboxes');
const pessoas = useMapGetter('agents/getAgents');
const etiquetas = useMapGetter('labels/getLabels');
const prioridades = useMapGetter('leadConfig/getPriorities');

const sugestoes = computed(() => ({
  etapa: etapas.value.map(x => x.name),
  tese: teses.value.map(x => x.name),
  caixa: caixas.value.map(x => x.name),
  responsavel: pessoas.value.map(x => x.name),
  etiquetas: etiquetas.value.map(x => x.title),
  prioridade: prioridades.value.map(x => x.name),
  status: ['open', 'resolved', 'pending', 'snoozed'],
}));
const condicoes = computed(() => props.config.condicoes || []);

const muda = (chave, valor) =>
  emit('update:config', { ...props.config, [chave]: valor });
const mudaCondicao = (i, chave, valor) =>
  muda(
    'condicoes',
    condicoes.value.map((c, j) => (j === i ? { ...c, [chave]: valor } : c))
  );
const trocaCondicao = (i, nova) =>
  muda(
    'condicoes',
    condicoes.value.map((c, j) => (j === i ? nova : c))
  );
const adicionar = () =>
  muda('condicoes', [
    ...condicoes.value,
    { campo: 'etapa', operador: 'igual', valor: '' },
  ]);
const remover = i =>
  muda(
    'condicoes',
    condicoes.value.filter((_c, j) => j !== i)
  );
</script>

<template>
  <div class="flex flex-col gap-4">
    <label :class="ROTULO">
      {{ t(`${K}.PAINEL.JUNCAO`) }}
      <select
        :class="SELECT"
        :value="config.juncao || 'e'"
        @change="muda('juncao', $event.target.value)"
      >
        <option value="e">{{ t(`${K}.PAINEL.JUNCAO_E`) }}</option>
        <option value="ou">{{ t(`${K}.PAINEL.JUNCAO_OU`) }}</option>
      </select>
    </label>

    <div
      v-for="(c, i) in condicoes"
      :key="i"
      class="flex flex-col gap-2 border-t border-n-weak pt-3"
    >
      <div class="grid grid-cols-2 gap-2">
        <select
          :class="SELECT"
          :aria-label="t(`${K}.PAINEL.CAMPO`)"
          :value="c.campo"
          @change="mudaCondicao(i, 'campo', $event.target.value)"
        >
          <option v-for="campo in CAMPOS" :key="campo" :value="campo">
            {{ t(`${K}.CAMPOS.${campo}`) }}
          </option>
        </select>
        <select
          :class="SELECT"
          :aria-label="t(`${K}.PAINEL.OPERADOR`)"
          :value="c.operador"
          @change="mudaCondicao(i, 'operador', $event.target.value)"
        >
          <option v-for="op in OPERADORES" :key="op" :value="op">
            {{ t(`${K}.OPERADORES.${op}`) }}
          </option>
        </select>
      </div>
      <input
        v-if="!SEM_VALOR.includes(c.operador)"
        :class="CAMPO"
        :aria-label="t(`${K}.PAINEL.VALOR`)"
        :placeholder="t(`${K}.PAINEL.VALOR`)"
        :list="`sug-${i}`"
        :value="c.valor"
        @input="mudaCondicao(i, 'valor', $event.target.value)"
      />
      <datalist :id="`sug-${i}`">
        <option v-for="s in sugestoes[c.campo] || []" :key="s" :value="s" />
      </datalist>
      <JanelaHorario
        v-if="c.operador === 'em_horario_comercial'"
        :config="c"
        @update:config="nova => trocaCondicao(i, nova)"
      />
      <Button
        class="self-end"
        link
        ruby
        xs
        :label="t(`${K}.PAINEL.REMOVER`)"
        @click="remover(i)"
      />
    </div>

    <Button
      class="self-start"
      faded
      slate
      xs
      icon="i-lucide-plus"
      :label="t(`${K}.PAINEL.ADD_CONDICAO`)"
      @click="adicionar"
    />
  </div>
</template>
