<script setup>
// Passo ADVBOX: tarefa ou movimentação FIXA no processo do lead (criado no fechamento).
// IDs vêm de advbox_configuracoes via GET ramon_fluxos/opcoes_advbox (admin).
import { onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import RamonFluxosAPI from 'dashboard/api/ramonFluxos';
import {
  AVISO,
  CAMPO,
  ROTULO,
  SELECT,
  TOM,
} from 'dashboard/routes/dashboard/ramon/helpers/ui';
import CampoTexto from './CampoTexto.vue';

const props = defineProps({ config: { type: Object, required: true } });
const emit = defineEmits(['update:config']);
const K = 'CAPTAIN_RAMON.FLUXOS.PAINEL';
const ACOES = ['tarefa', 'movimentacao'];
const { t } = useI18n();
const usuarios = ref([]);
const tipos = ref([]);
const indisponivel = ref(false);

const muda = (chave, valor) =>
  emit('update:config', { ...props.config, [chave]: valor });
const numeroOuNada = v => (v === '' ? null : Number(v));

onMounted(async () => {
  try {
    const { data } = await RamonFluxosAPI.opcoesAdvbox();
    usuarios.value = data.usuarios || [];
    tipos.value = data.tipos_tarefa || [];
  } catch {
    indisponivel.value = true;
  }
});
</script>

<template>
  <div class="flex flex-col gap-4">
    <p :class="[AVISO, TOM.amber]">{{ t(`${K}.ADVBOX_AVISO`) }}</p>
    <div class="flex flex-col gap-1.5 text-[13px] text-n-slate-12">
      <label v-for="acao in ACOES" :key="acao" class="flex items-center gap-2">
        <input
          type="radio"
          class="reset-base"
          :checked="config.acao === acao"
          @change="muda('acao', acao)"
        />
        {{ t(`${K}.ADVBOX_ACOES.${acao}`) }}
      </label>
    </div>
    <p
      v-if="indisponivel"
      data-testid="advbox-indisponivel"
      :class="[AVISO, TOM.ruby]"
    >
      {{ t(`${K}.ADVBOX_INDISPONIVEL`) }}
    </p>

    <template v-if="config.acao === 'tarefa'">
      <label :class="ROTULO">
        {{ t(`${K}.ADVBOX_TIPO`) }}
        <select
          data-testid="advbox-tipo"
          :class="SELECT"
          :value="config.tipo_tarefa_id ?? ''"
          @change="muda('tipo_tarefa_id', numeroOuNada($event.target.value))"
        >
          <option value="" disabled>{{ t(`${K}.ESCOLHA`) }}</option>
          <option v-for="o in tipos" :key="o.id" :value="o.id">
            {{ o.nome }}
          </option>
        </select>
      </label>
      <label :class="ROTULO">
        {{ t(`${K}.ADVBOX_RESPONSAVEL`) }}
        <select
          data-testid="advbox-responsavel"
          :class="SELECT"
          :value="config.responsavel_id ?? ''"
          @change="muda('responsavel_id', numeroOuNada($event.target.value))"
        >
          <option value="" disabled>{{ t(`${K}.ESCOLHA`) }}</option>
          <option v-for="u in usuarios" :key="u.id" :value="u.id">
            {{ u.nome }}
          </option>
        </select>
      </label>
      <label :class="ROTULO">
        {{ t(`${K}.ADVBOX_PRAZO`) }}
        <input
          :class="CAMPO"
          type="number"
          min="0"
          :value="config.prazo_dias ?? ''"
          @change="muda('prazo_dias', numeroOuNada($event.target.value))"
        />
      </label>
    </template>

    <CampoTexto
      v-if="config.acao"
      :rotulo="t(`${K}.ADVBOX_DESCRICAO`)"
      :linhas="3"
      :model-value="config.descricao || ''"
      @update:model-value="v => muda('descricao', v)"
    />
  </div>
</template>
