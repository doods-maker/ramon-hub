<script setup>
// Substituto do window.confirm para ações destrutivas, no padrão da casa.
import { ref, onMounted } from 'vue';
import { onKeyStroke } from '@vueuse/core';
import Button from 'dashboard/components-next/button/Button.vue';
import {
  FUNDO_JANELA,
  JANELA,
  TITULO_JANELA,
  RODAPE_JANELA,
} from '../helpers/ui';

defineProps({
  title: { type: String, required: true },
  message: { type: String, default: '' },
  confirmLabel: { type: String, required: true },
  // ruby = destrutivo (padrão); blue = ação consequente mas não destrutiva.
  confirmColor: { type: String, default: 'ruby' },
});
const emit = defineEmits(['confirm', 'cancel']);

// Foco no confirmar ao abrir: Enter confirma, Esc cancela.
const confirmButton = ref(null);
onMounted(() => confirmButton.value?.$el?.focus());

onKeyStroke('Escape', () => emit('cancel'));
</script>

<template>
  <div :class="FUNDO_JANELA" @click.self="emit('cancel')">
    <div :class="JANELA">
      <h3 :class="TITULO_JANELA">{{ title }}</h3>
      <p v-if="message" class="text-sm text-n-slate-11">{{ message }}</p>
      <div :class="RODAPE_JANELA">
        <Button
          data-testid="confirm-modal-cancel"
          sm
          faded
          slate
          :label="$t('RAMON.MODAL.CANCEL')"
          @click="emit('cancel')"
        />
        <Button
          ref="confirmButton"
          data-testid="confirm-modal-confirm"
          sm
          :color="confirmColor"
          :label="confirmLabel"
          @click="emit('confirm')"
        />
      </div>
    </div>
  </div>
</template>
