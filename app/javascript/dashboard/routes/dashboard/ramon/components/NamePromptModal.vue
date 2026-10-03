<script setup>
// Substituto do window.prompt: pergunta um nome no padrão visual da casa.
import { ref, nextTick, onMounted } from 'vue';
import { onKeyStroke } from '@vueuse/core';
import Button from 'dashboard/components-next/button/Button.vue';
import {
  CAMPO,
  FUNDO_JANELA,
  JANELA,
  TITULO_JANELA,
  RODAPE_JANELA,
} from '../helpers/ui';

defineProps({
  title: { type: String, required: true },
  placeholder: { type: String, default: '' },
  confirmLabel: { type: String, required: true },
});
const emit = defineEmits(['confirm', 'cancel']);

const name = ref('');
const input = ref(null);

const confirm = () => {
  const value = name.value.trim();
  if (!value) return;
  emit('confirm', value);
};

onKeyStroke('Escape', () => emit('cancel'));
onMounted(() => {
  nextTick(() => input.value?.focus());
});
</script>

<template>
  <div :class="FUNDO_JANELA" @click.self="emit('cancel')">
    <div :class="JANELA">
      <h3 :class="TITULO_JANELA">{{ title }}</h3>
      <input
        ref="input"
        v-model="name"
        data-testid="name-prompt-input"
        :class="CAMPO"
        :placeholder="placeholder"
        @keyup.enter="confirm"
      />
      <div :class="RODAPE_JANELA">
        <Button
          data-testid="name-prompt-cancel"
          sm
          faded
          slate
          :label="$t('RAMON.MODAL.CANCEL')"
          @click="emit('cancel')"
        />
        <Button
          data-testid="name-prompt-confirm"
          sm
          :label="confirmLabel"
          :disabled="!name.trim()"
          @click="confirm"
        />
      </div>
    </div>
  </div>
</template>
