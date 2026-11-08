<script setup>
// Ganho de tese que passa por Documentos numa coluna que não é Documentos
// (teste de 07/11): o padrão é ir para Documentos (o assistente junta os
// documentos); ficar na coluna escolhida pede o motivo, que vira nota do lead
// (composables/usePulaDocumentos.js).
import { ROTULO, TEXTAREA } from '../helpers/ui';

const motivo = defineModel({ type: String, default: '' });
const ficar = defineModel('ficar', { type: Boolean, default: false });
</script>

<template>
  <fieldset class="flex flex-col gap-2">
    <legend :class="ROTULO">
      {{ $t('RAMON.FUNIL.WON.PERGUNTA_DOCUMENTOS') }}
    </legend>
    <label class="flex items-center gap-2 text-sm text-n-slate-12">
      <input
        v-model="ficar"
        type="radio"
        :value="false"
        data-testid="pula-documentos-ir"
      />
      {{ $t('RAMON.FUNIL.WON.IR_PARA_DOCUMENTOS') }}
    </label>
    <label class="flex items-center gap-2 text-sm text-n-slate-12">
      <input
        v-model="ficar"
        type="radio"
        :value="true"
        data-testid="pula-documentos-ficar"
      />
      {{ $t('RAMON.FUNIL.WON.FICAR_SEM_DOCUMENTOS') }}
    </label>
    <label v-if="ficar" :class="ROTULO">
      {{ $t('RAMON.FUNIL.WON.MOTIVO_PULA_DOCUMENTOS') }}
      <textarea
        v-model="motivo"
        data-testid="motivo-pula-documentos"
        rows="3"
        :class="TEXTAREA"
      />
    </label>
  </fieldset>
</template>
