<script setup>
import { ref, computed, onMounted, onBeforeUnmount } from 'vue';
import { parseBrlInput } from '../../helpers/currency';

const emit = defineEmits(['confirmValue', 'cancelValue']);

const value = ref('');

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
const onDocKeydown = e => {
  if (e.key === 'Escape') cancel();
};
onMounted(() => document.addEventListener('keydown', onDocKeydown));
onBeforeUnmount(() => document.removeEventListener('keydown', onDocKeydown));
</script>

<template>
  <div
    class="fixed inset-0 z-50 flex items-center justify-center bg-black/50"
    @click.self="cancel"
  >
    <div
      class="w-80 max-w-[92vw] p-5 rounded-xl bg-n-solid-2 border border-n-weak"
    >
      <h3 class="mb-3 text-sm text-n-slate-12">
        {{ $t('RAMON.FUNIL.WON.TITLE') }}
      </h3>
      <label class="block mb-1 text-xs text-n-slate-10">{{
        $t('RAMON.FUNIL.WON.VALUE_LABEL')
      }}</label>
      <input
        v-model="value"
        data-testid="won-value-input"
        type="text"
        inputmode="decimal"
        class="w-full px-3 py-2 mb-3 text-sm rounded-lg bg-n-alpha-1 text-n-slate-12 border border-n-weak"
        @keyup.enter="save"
      />
      <div class="flex justify-end gap-2">
        <button
          data-testid="won-value-skip"
          class="px-3 py-1.5 text-sm rounded-lg text-n-slate-11 hover:text-n-slate-12"
          @click="skip"
        >
          {{ $t('RAMON.FUNIL.WON.SKIP') }}
        </button>
        <button
          data-testid="won-value-save"
          class="px-3 py-1.5 text-sm rounded-lg bg-n-iris-9 text-white disabled:opacity-50"
          :disabled="isInvalid"
          @click="save"
        >
          {{ $t('RAMON.FUNIL.WON.SAVE') }}
        </button>
      </div>
    </div>
  </div>
</template>
