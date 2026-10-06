<script setup>
// Gatilho: quando roda + filtros que o Disparo.filtro_ok? da B1 entende
// (caixa_ids, de_etapa_ids, para_etapa_ids) + cancelar se sair da etapa.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import { ROTULO, SELECT } from 'dashboard/routes/dashboard/ramon/helpers/ui';
import { GATILHOS, gatilhoInfo } from './fluxo';
import ListaMarcar from './ListaMarcar.vue';

const props = defineProps({ config: { type: Object, required: true } });
const emit = defineEmits(['update:config']);
const K = 'CAPTAIN_RAMON.FLUXOS.PAINEL';
const { t } = useI18n();
const etapas = useMapGetter('leadConfig/getStages');
const caixas = useMapGetter('inboxes/getInboxes');

const opcoesEtapas = computed(() =>
  etapas.value.map(e => ({ id: e.id, nome: e.name }))
);
const opcoesCaixas = computed(() =>
  caixas.value.map(c => ({ id: c.id, nome: c.name }))
);
const alvo = computed(() => gatilhoInfo(props.config.tipo)?.alvo);
const cancelar = computed(
  () => props.config.cancelar_se_sair_da_etapa !== false
);

const muda = (chave, valor) =>
  emit('update:config', { ...props.config, [chave]: valor });
// trocar o tipo zera os filtros que não valem mais
const trocaTipo = tipo =>
  emit('update:config', {
    tipo,
    ...(props.config.rotulo ? { rotulo: props.config.rotulo } : {}),
    ...(props.config.cancelar_se_sair_da_etapa === false
      ? { cancelar_se_sair_da_etapa: false }
      : {}),
  });
</script>

<template>
  <div class="flex flex-col gap-4">
    <label :class="ROTULO">
      {{ t(`${K}.GATILHO_TIPO`) }}
      <select
        :class="SELECT"
        :value="config.tipo"
        @change="trocaTipo($event.target.value)"
      >
        <option v-for="g in GATILHOS" :key="g.tipo" :value="g.tipo">
          {{ t(`CAPTAIN_RAMON.FLUXOS.GATILHOS.${g.tipo}`) }}
        </option>
      </select>
    </label>

    <div v-if="alvo === 'conversa'" :class="ROTULO">
      {{ t(`${K}.CAIXAS`) }}
      <ListaMarcar
        :opcoes="opcoesCaixas"
        :model-value="config.caixa_ids || []"
        @update:model-value="v => muda('caixa_ids', v)"
      />
      <span>{{ t(`${K}.CAIXAS_AJUDA`) }}</span>
    </div>

    <template v-if="config.tipo === 'lead_mudou_etapa'">
      <div :class="ROTULO">
        {{ t(`${K}.DE_ETAPAS`) }}
        <ListaMarcar
          :opcoes="opcoesEtapas"
          :model-value="config.de_etapa_ids || []"
          @update:model-value="v => muda('de_etapa_ids', v)"
        />
      </div>
      <div :class="ROTULO">
        {{ t(`${K}.PARA_ETAPAS`) }}
        <ListaMarcar
          :opcoes="opcoesEtapas"
          :model-value="config.para_etapa_ids || []"
          @update:model-value="v => muda('para_etapa_ids', v)"
        />
        <span>{{ t(`${K}.ETAPAS_AJUDA`) }}</span>
      </div>
    </template>

    <p v-if="config.tipo === 'manual'" class="text-xs text-n-slate-10">
      {{ t(`${K}.MANUAL_AJUDA`) }}
    </p>

    <div
      class="flex items-center justify-between border-t border-n-weak py-2 text-[13px] text-n-slate-12"
    >
      {{ t(`${K}.CANCELAR_ETAPA`) }}
      <Switch
        :model-value="cancelar"
        @update:model-value="v => muda('cancelar_se_sair_da_etapa', v)"
      />
    </div>
  </div>
</template>
