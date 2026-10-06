<script setup>
// Ação da conversa = ações nativas das regras do Chatwoot (mesma execução,
// AcaoChatwootService). action_params no formato do ActionService.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import Button from 'dashboard/components-next/button/Button.vue';
import {
  ROTULO,
  SELECT,
  TEXTAREA,
} from 'dashboard/routes/dashboard/ramon/helpers/ui';
import { ACOES_CHATWOOT, PRIORIDADES } from './fluxo';
import ListaMarcar from './ListaMarcar.vue';

const props = defineProps({ config: { type: Object, required: true } });
const emit = defineEmits(['update:config']);
const K = 'CAPTAIN_RAMON.FLUXOS';
const { t } = useI18n();
const pessoas = useMapGetter('agents/getAgents');
const times = useMapGetter('teams/getTeams');
const etiquetas = useMapGetter('labels/getLabels');

const opcoesEtiquetas = computed(() =>
  etiquetas.value.map(l => ({ id: l.title, nome: l.title }))
);
const opcoesTimes = computed(() =>
  times.value.map(x => ({ id: x.id, nome: x.name }))
);
const acoes = computed(() => props.config.acoes || []);
const parametro = nome => ACOES_CHATWOOT.find(a => a.nome === nome)?.parametro;
const conhecida = nome => ACOES_CHATWOOT.some(a => a.nome === nome);

const salvar = lista =>
  emit('update:config', { ...props.config, acoes: lista });
const mudaAcao = (i, mudanca) =>
  salvar(acoes.value.map((a, j) => (j === i ? { ...a, ...mudanca } : a)));
const trocaNome = (i, nome) =>
  mudaAcao(i, {
    action_name: nome,
    action_params:
      parametro(nome) === 'email_time' ? [{ message: '', team_ids: [] }] : [],
  });
const adicionar = () =>
  salvar([...acoes.value, { action_name: 'add_label', action_params: [] }]);
const remover = i => salvar(acoes.value.filter((_a, j) => j !== i));
const email = a => a.action_params?.[0] || { message: '', team_ids: [] };
</script>

<template>
  <div class="flex flex-col gap-4">
    <div
      v-for="(acao, i) in acoes"
      :key="i"
      class="flex flex-col gap-2 border-t border-n-weak pt-3 first:border-0 first:pt-0"
    >
      <label :class="ROTULO">
        {{ t(`${K}.PAINEL.ACAO`) }}
        <select
          :class="SELECT"
          :value="acao.action_name"
          @change="trocaNome(i, $event.target.value)"
        >
          <option v-if="!conhecida(acao.action_name)" :value="acao.action_name">
            {{ acao.action_name }}
          </option>
          <option v-for="a in ACOES_CHATWOOT" :key="a.nome" :value="a.nome">
            {{ t(`${K}.ACOES_CHATWOOT.${a.nome}`) }}
          </option>
        </select>
      </label>

      <div v-if="parametro(acao.action_name) === 'etiquetas'" :class="ROTULO">
        {{ t(`${K}.PAINEL.ETIQUETAS`) }}
        <ListaMarcar
          :opcoes="opcoesEtiquetas"
          :model-value="acao.action_params || []"
          @update:model-value="v => mudaAcao(i, { action_params: v })"
        />
      </div>
      <label
        v-else-if="parametro(acao.action_name) === 'pessoa'"
        :class="ROTULO"
      >
        {{ t(`${K}.PAINEL.PESSOA`) }}
        <select
          :class="SELECT"
          :value="acao.action_params?.[0] ?? ''"
          @change="
            mudaAcao(i, { action_params: [Number($event.target.value)] })
          "
        >
          <option value="" disabled>{{ t(`${K}.PAINEL.ESCOLHA`) }}</option>
          <option v-for="p in pessoas" :key="p.id" :value="p.id">
            {{ p.name }}
          </option>
        </select>
      </label>
      <label v-else-if="parametro(acao.action_name) === 'time'" :class="ROTULO">
        {{ t(`${K}.PAINEL.TIME`) }}
        <select
          :class="SELECT"
          :value="acao.action_params?.[0] ?? ''"
          @change="
            mudaAcao(i, { action_params: [Number($event.target.value)] })
          "
        >
          <option value="" disabled>{{ t(`${K}.PAINEL.ESCOLHA`) }}</option>
          <option v-for="x in times" :key="x.id" :value="x.id">
            {{ x.name }}
          </option>
        </select>
      </label>
      <label
        v-else-if="parametro(acao.action_name) === 'prioridade'"
        :class="ROTULO"
      >
        {{ t(`${K}.PAINEL.PRIORIDADE`) }}
        <select
          :class="SELECT"
          :value="acao.action_params?.[0] ?? ''"
          @change="mudaAcao(i, { action_params: [$event.target.value] })"
        >
          <option value="" disabled>{{ t(`${K}.PAINEL.ESCOLHA`) }}</option>
          <option v-for="p in PRIORIDADES" :key="p" :value="p">
            {{ t(`${K}.PRIORIDADES.${p}`) }}
          </option>
        </select>
      </label>
      <template v-else-if="parametro(acao.action_name) === 'email_time'">
        <label :class="ROTULO">
          {{ t(`${K}.PAINEL.MENSAGEM_EMAIL`) }}
          <textarea
            :class="TEXTAREA"
            rows="3"
            :value="email(acao).message"
            @input="
              mudaAcao(i, {
                action_params: [
                  { ...email(acao), message: $event.target.value },
                ],
              })
            "
          />
        </label>
        <div :class="ROTULO">
          {{ t(`${K}.PAINEL.TIMES`) }}
          <ListaMarcar
            :opcoes="opcoesTimes"
            :model-value="email(acao).team_ids"
            @update:model-value="
              v =>
                mudaAcao(i, {
                  action_params: [{ ...email(acao), team_ids: v }],
                })
            "
          />
        </div>
      </template>

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
      :label="t(`${K}.PAINEL.ADD_ACAO`)"
      @click="adicionar"
    />
  </div>
</template>
