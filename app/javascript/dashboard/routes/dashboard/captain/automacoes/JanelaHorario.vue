<script setup>
// Janela de horário do próprio passo (B4.2, Ramon::Fluxos::Horario.janela): dias da semana + das/até, em São Paulo.
// Sem as chaves vale o padrão (seg–sex, 8h–18h). Serve ao "Se → agora é horário comercial" e ao "Esperar até o horário".
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { ROTULO, SELECT } from 'dashboard/routes/dashboard/ramon/helpers/ui';
import { JANELA_PADRAO } from './fluxo';

const props = defineProps({ config: { type: Object, required: true } });
const emit = defineEmits(['update:config']);
const K = 'CAPTAIN_RAMON.FLUXOS.PAINEL';
const { t } = useI18n();
const DIAS = [0, 1, 2, 3, 4, 5, 6];
const INICIOS = [...Array(24).keys()]; // 0–23
const FINS = INICIOS.map(h => h + 1); // 1–24 (24 = até a meia-noite)

const dias = computed(() => props.config.dias ?? JANELA_PADRAO.dias);
const inicio = computed(() => props.config.inicio ?? JANELA_PADRAO.inicio);
const fim = computed(() => props.config.fim ?? JANELA_PADRAO.fim);

// grava a janela inteira assim que algo muda: o JSON diz exatamente o que vale
const muda = (chave, valor) =>
  emit('update:config', {
    ...props.config,
    dias: dias.value,
    inicio: inicio.value,
    fim: fim.value,
    [chave]: valor,
  });
const marcaDia = (d, ligado) =>
  muda(
    'dias',
    ligado
      ? [...dias.value, d].sort((a, b) => a - b)
      : dias.value.filter(x => x !== d)
  );
</script>

<template>
  <div class="flex flex-col gap-2">
    <span :class="ROTULO">{{ t(`${K}.JANELA_DIAS`) }}</span>
    <div class="flex flex-wrap gap-3 text-[13px] text-n-slate-12">
      <label v-for="d in DIAS" :key="d" class="flex items-center gap-1">
        <input
          type="checkbox"
          class="reset-base"
          :data-testid="`janela-dia-${d}`"
          :checked="dias.includes(d)"
          @change="marcaDia(d, $event.target.checked)"
        />
        {{ t(`${K}.DIA_${d}`) }}
      </label>
    </div>
    <div class="grid grid-cols-2 gap-2">
      <label :class="ROTULO">
        {{ t(`${K}.JANELA_INICIO`) }}
        <select
          data-testid="janela-inicio"
          :class="SELECT"
          :value="inicio"
          @change="muda('inicio', Number($event.target.value))"
        >
          <option v-for="h in INICIOS" :key="h" :value="h">
            {{ t(`${K}.HORA_N`, { h }) }}
          </option>
        </select>
      </label>
      <label :class="ROTULO">
        {{ t(`${K}.JANELA_FIM`) }}
        <select
          data-testid="janela-fim"
          :class="SELECT"
          :value="fim"
          @change="muda('fim', Number($event.target.value))"
        >
          <option v-for="h in FINS" :key="h" :value="h">
            {{ t(`${K}.HORA_N`, { h }) }}
          </option>
        </select>
      </label>
    </div>
    <p class="text-xs text-n-slate-10">{{ t(`${K}.JANELA_AJUDA`) }}</p>
  </div>
</template>
