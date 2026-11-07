<script setup>
// Motivo de entrar no ganho sem passar por Documentos (obrigatório; vira nota
// do lead — composables/usePulaDocumentos.js).
import { ROTULO, TEXTAREA } from '../helpers/ui';

const motivo = defineModel({ type: String, default: '' });
</script>

<template>
  <label :class="ROTULO">
    {{ $t('RAMON.FUNIL.WON.MOTIVO_PULA_DOCUMENTOS') }}
    <textarea
      v-model="motivo"
      data-testid="motivo-pula-documentos"
      rows="3"
      :class="TEXTAREA"
    />
  </label>
</template>
