<script setup>
// Gatilho: quando roda + filtros que o Disparo.filtro_ok? da B1 entende
// (caixa_ids, de_etapa_ids, para_etapa_ids) + cancelar se sair da etapa.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import {
  CAMPO,
  ROTULO,
  SELECT,
} from 'dashboard/routes/dashboard/ramon/helpers/ui';
import { GATILHOS, REGRAS_ADVBOX, gatilhoInfo } from './fluxo';
import ListaMarcar from './ListaMarcar.vue';
import ConfigHorarioConta from './ConfigHorarioConta.vue';

const props = defineProps({ config: { type: Object, required: true } });
const emit = defineEmits(['update:config']);
const K = 'CAPTAIN_RAMON.FLUXOS.PAINEL';
const { t } = useI18n();
const etapas = useMapGetter('leadConfig/getStages');
const caixas = useMapGetter('inboxes/getInboxes');
const teses = useMapGetter('theses/getTheses');
const pessoas = useMapGetter('agents/getAgents');

const opcoesEtapas = computed(() =>
  etapas.value.map(e => ({ id: e.id, nome: e.name }))
);
const opcoesCaixas = computed(() =>
  caixas.value.map(c => ({ id: c.id, nome: c.name }))
);
const opcoesTeses = computed(() =>
  teses.value.map(x => ({ id: x.id, nome: x.name }))
);
const opcoesPessoas = computed(() =>
  pessoas.value.map(x => ({ id: x.id, nome: x.name }))
);
const opcoesRegras = computed(() =>
  REGRAS_ADVBOX.map(r => ({
    id: r,
    nome: t(`CAPTAIN_RAMON.FLUXOS.REGRAS_ADVBOX.${r}`),
  }))
);
const relogio = computed(() =>
  ['relogio', 'lead_parado'].includes(props.config.tipo)
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
    ...(tipo === 'horario_conta' ? { hora: '08:00' } : {}),
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

    <label v-if="relogio" :class="ROTULO">
      {{ t(`${K}.HORA`) }}
      <input
        data-testid="gatilho-hora"
        :class="CAMPO"
        type="time"
        :value="config.hora || (config.tipo === 'lead_parado' ? '11:00' : '')"
        @input="muda('hora', $event.target.value)"
      />
    </label>

    <label v-if="config.tipo === 'lead_parado'" :class="ROTULO">
      {{ t(`${K}.DIAS_PARADO`) }}
      <input
        :class="CAMPO"
        type="number"
        min="1"
        :value="config.dias ?? ''"
        @change="
          muda(
            'dias',
            $event.target.value === '' ? null : Number($event.target.value)
          )
        "
      />
      <span>{{ t(`${K}.DIAS_PARADO_AJUDA`) }}</span>
    </label>

    <template v-if="config.tipo === 'lead_parado'">
      <label class="flex items-center gap-2 text-[13px] text-n-slate-12">
        <input
          data-testid="gatilho-retomada"
          type="checkbox"
          class="reset-base"
          :checked="!!config.retomada"
          @change="muda('retomada', $event.target.checked || undefined)"
        />
        {{ t(`${K}.RETOMADA`) }}
      </label>
      <p class="text-xs text-n-slate-10">{{ t(`${K}.RETOMADA_AJUDA`) }}</p>
    </template>

    <template v-if="config.tipo === 'relogio'">
      <div :class="ROTULO">
        {{ t(`${K}.GRUPO_ETAPAS`) }}
        <ListaMarcar
          :opcoes="opcoesEtapas"
          :model-value="config.etapa_ids || []"
          @update:model-value="v => muda('etapa_ids', v)"
        />
      </div>
      <div :class="ROTULO">
        {{ t(`${K}.GRUPO_TESES`) }}
        <ListaMarcar
          :opcoes="opcoesTeses"
          :model-value="config.tese_ids || []"
          @update:model-value="v => muda('tese_ids', v)"
        />
      </div>
      <div :class="ROTULO">
        {{ t(`${K}.GRUPO_RESPONSAVEIS`) }}
        <ListaMarcar
          :opcoes="opcoesPessoas"
          :model-value="config.responsavel_ids || []"
          @update:model-value="v => muda('responsavel_ids', v)"
        />
        <span>{{ t(`${K}.GRUPO_AJUDA`) }}</span>
      </div>
    </template>

    <div v-if="config.tipo === 'evento_advbox'" :class="ROTULO">
      {{ t(`${K}.REGRAS`) }}
      <ListaMarcar
        :opcoes="opcoesRegras"
        :model-value="config.regras || []"
        @update:model-value="v => muda('regras', v)"
      />
      <span>{{ t(`${K}.REGRAS_AJUDA`) }}</span>
    </div>

    <p
      v-if="['reuniao_marcada', 'reuniao_cancelada'].includes(config.tipo)"
      class="text-xs text-n-slate-10"
    >
      {{ t(`${K}.REUNIAO_AJUDA`) }}
    </p>
    <p
      v-if="config.tipo === 'documento_recebido'"
      class="text-xs text-n-slate-10"
    >
      {{ t(`${K}.DOCUMENTO_AJUDA`) }}
    </p>

    <ConfigHorarioConta
      v-if="config.tipo === 'horario_conta'"
      :config="config"
      @update:config="c => emit('update:config', c)"
    />

    <p v-if="config.tipo === 'manual'" class="text-xs text-n-slate-10">
      {{ t(`${K}.MANUAL_AJUDA`) }}
    </p>

    <div
      v-if="alvo !== 'conta'"
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
