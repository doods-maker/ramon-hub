<script setup>
import { ref, computed, onMounted } from 'vue';
import { onKeyStroke } from '@vueuse/core';
import { formatBrl, parseBrlInput } from '../../helpers/currency';
import Button from 'dashboard/components-next/button/Button.vue';
import {
  CAMPO,
  ROTULO,
  FUNDO_JANELA,
  JANELA,
  TITULO_JANELA,
  RODAPE_JANELA,
} from '../../helpers/ui';

const props = defineProps({
  initialValue: { type: [Number, String], default: null },
});
const emit = defineEmits(['confirmValue', 'cancelValue']);

// Ganho sem confirmação humana vira valor de contrato em silêncio: o modal
// SEMPRE abre no movimento pra etapa ganha, pré-preenchido quando o lead já
// tem valor — confirmar (1 clique/Enter) é a confirmação humana que faltava.
const value = ref(formatBrl(props.initialValue));
const valueInput = ref(null);
onMounted(() => valueInput.value?.focus());

// texto inválido não-vazio desabilita Salvar (senão viraria "Pular" silencioso)
const isInvalid = computed(
  () => value.value.trim() !== '' && parseBrlInput(value.value) === null
);

// Salvar envia o valor; Pular move sem valor; o clique fora cancela (reverte).
const save = () => {
  if (isInvalid.value) return;
  emit('confirmValue', { value: parseBrlInput(value.value) });
};
const skip = () => emit('confirmValue', { value: null });
const cancel = () => emit('cancelValue');

// Esc cancela (reverte o drag), igual ao clique no backdrop.
onKeyStroke('Escape', cancel);
</script>

<template>
  <div :class="FUNDO_JANELA" @click.self="cancel">
    <div :class="JANELA">
      <h3 :class="TITULO_JANELA">
        {{ $t('RAMON.FUNIL.WON.TITLE') }}
      </h3>
      <label :class="ROTULO">
        {{ $t('RAMON.FUNIL.WON.VALUE_LABEL') }}
        <input
          ref="valueInput"
          v-model="value"
          data-testid="won-value-input"
          type="text"
          inputmode="decimal"
          class="font-mono"
          :class="[CAMPO, { '!outline-n-ruby-8': isInvalid }]"
          @keyup.enter="save"
        />
      </label>
      <p
        v-if="isInvalid"
        data-testid="won-value-error"
        class="mt-1 mb-0 text-xs text-n-ruby-11"
      >
        {{ $t('RAMON.FUNIL.WON.INVALID') }}
      </p>
      <div :class="RODAPE_JANELA">
        <Button
          data-testid="won-value-skip"
          sm
          faded
          slate
          :label="$t('RAMON.FUNIL.WON.SKIP')"
          @click="skip"
        />
        <Button
          data-testid="won-value-save"
          sm
          :label="$t('RAMON.FUNIL.WON.SAVE')"
          :disabled="isInvalid"
          @click="save"
        />
      </div>
    </div>
  </div>
</template>
