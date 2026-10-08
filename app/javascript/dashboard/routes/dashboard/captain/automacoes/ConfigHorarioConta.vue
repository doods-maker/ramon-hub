<script setup>
// Gatilho "Horário da conta" (B5-conta, Ramon::Fluxos::HorarioConta): uma vez por dia a partir de HH:MM ou a cada N
// minutos, nos dias marcados (sem a chave = todos). Fuso de São Paulo. O alvo é a conta toda, não um lead.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  CAMPO,
  ROTULO,
  SELECT,
} from 'dashboard/routes/dashboard/ramon/helpers/ui';

const props = defineProps({ config: { type: Object, required: true } });
const emit = defineEmits(['update:config']);
const K = 'CAPTAIN_RAMON.FLUXOS.PAINEL';
const { t } = useI18n();
const DIAS = [0, 1, 2, 3, 4, 5, 6];

const modo = computed(() =>
  props.config.a_cada_minutos ? 'intervalo' : 'dia'
);
const dias = computed(() => props.config.dias ?? DIAS);

const muda = (chave, valor) =>
  emit('update:config', { ...props.config, [chave]: valor });
// a outra chave sai: o back lê 'a_cada_minutos' antes de 'hora'
const semModo = () =>
  Object.fromEntries(
    Object.entries(props.config).filter(
      ([k]) => !['hora', 'a_cada_minutos'].includes(k)
    )
  );
const trocaModo = novo =>
  emit(
    'update:config',
    novo === 'intervalo'
      ? { ...semModo(), a_cada_minutos: 1 }
      : { ...semModo(), hora: '08:00' }
  );
const marcaDia = (d, ligado) =>
  muda(
    'dias',
    ligado
      ? [...dias.value, d].sort((a, b) => a - b)
      : dias.value.filter(x => x !== d)
  );
</script>

<template>
  <div class="flex flex-col gap-3">
    <label :class="ROTULO">
      {{ t(`${K}.CONTA_QUANDO`) }}
      <select
        data-testid="conta-modo"
        :class="SELECT"
        :value="modo"
        @change="trocaModo($event.target.value)"
      >
        <option value="dia">{{ t(`${K}.CONTA_UMA_VEZ`) }}</option>
        <option value="intervalo">{{ t(`${K}.CONTA_INTERVALO`) }}</option>
      </select>
    </label>
    <label v-if="modo === 'dia'" :class="ROTULO">
      {{ t(`${K}.HORA`) }}
      <input
        data-testid="conta-hora"
        :class="CAMPO"
        type="time"
        :value="config.hora || ''"
        @input="muda('hora', $event.target.value)"
      />
    </label>
    <label v-else :class="ROTULO">
      {{ t(`${K}.CONTA_MINUTOS`) }}
      <input
        data-testid="conta-minutos"
        :class="CAMPO"
        type="number"
        min="1"
        max="1440"
        :value="config.a_cada_minutos"
        @change="muda('a_cada_minutos', Number($event.target.value) || 1)"
      />
    </label>
    <span :class="ROTULO">{{ t(`${K}.CONTA_DIAS`) }}</span>
    <div class="flex flex-wrap gap-3 text-[13px] text-n-slate-12">
      <label v-for="d in DIAS" :key="d" class="flex items-center gap-1">
        <input
          type="checkbox"
          class="reset-base"
          :data-testid="`conta-dia-${d}`"
          :checked="dias.includes(d)"
          @change="marcaDia(d, $event.target.checked)"
        />
        {{ t(`${K}.DIA_${d}`) }}
      </label>
    </div>
    <p class="text-xs text-n-slate-10">{{ t(`${K}.CONTA_AJUDA`) }}</p>
  </div>
</template>
