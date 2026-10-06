<script setup>
// Célula do gatilho, a mesma nas duas abas da lista (rótulo do sistema, se houver, vence o do tipo).
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { gatilhoInfo } from './fluxo';

const props = defineProps({ fluxo: { type: Object, required: true } });
const { t } = useI18n();
const texto = computed(
  () =>
    props.fluxo.gatilho_rotulo ||
    (props.fluxo.gatilho_tipo
      ? t(`CAPTAIN_RAMON.FLUXOS.GATILHOS.${props.fluxo.gatilho_tipo}`)
      : '—')
);
</script>

<template>
  <span class="inline-flex items-center gap-1.5 text-[12.5px] text-n-slate-11">
    <i
      v-if="fluxo.gatilho_tipo"
      :class="gatilhoInfo(fluxo.gatilho_tipo)?.icone"
      class="size-3.5 text-n-blue-11"
    />
    {{ texto }}
  </span>
</template>
