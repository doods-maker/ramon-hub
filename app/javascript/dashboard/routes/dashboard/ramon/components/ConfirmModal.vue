<script setup>
// Substituto do window.confirm para ações destrutivas, no padrão da casa.
import { ref, onMounted } from 'vue';
import { onKeyStroke } from '@vueuse/core';

defineProps({
  title: { type: String, required: true },
  message: { type: String, default: '' },
  confirmLabel: { type: String, required: true },
});
const emit = defineEmits(['confirm', 'cancel']);

// Foco no confirmar ao abrir: Enter confirma, Esc cancela.
const confirmButton = ref(null);
onMounted(() => confirmButton.value?.focus());

onKeyStroke('Escape', () => emit('cancel'));
</script>

<template>
  <div
    class="fixed inset-0 z-50 flex items-center justify-center bg-black/50"
    @click.self="emit('cancel')"
  >
    <div
      class="w-80 max-w-[92vw] p-5 rounded-xl bg-n-solid-2 border border-n-weak"
    >
      <h3 class="mb-2 text-sm text-n-slate-12">{{ title }}</h3>
      <p v-if="message" class="mb-3 text-sm text-n-slate-11">{{ message }}</p>
      <div class="flex justify-end gap-2 mt-1">
        <button
          data-testid="confirm-modal-cancel"
          class="px-3 py-1.5 text-sm rounded-lg text-n-slate-11 hover:text-n-slate-12"
          @click="emit('cancel')"
        >
          {{ $t('RAMON.MODAL.CANCEL') }}
        </button>
        <button
          ref="confirmButton"
          data-testid="confirm-modal-confirm"
          class="px-3 py-1.5 text-sm rounded-lg bg-n-ruby-9 text-white hover:bg-n-ruby-10 disabled:opacity-50"
          @click="emit('confirm')"
        >
          {{ confirmLabel }}
        </button>
      </div>
    </div>
  </div>
</template>
