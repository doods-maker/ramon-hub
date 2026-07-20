<script setup>
import { ref, computed, onMounted } from 'vue';
import { onKeyStroke } from '@vueuse/core';
import { parseBrlInput } from '../../helpers/currency';

const emit = defineEmits(['confirmValue', 'cancelValue']);

const value = ref('');
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
        ref="valueInput"
        v-model="value"
        data-testid="won-value-input"
        type="text"
        inputmode="decimal"
        class="w-full px-3 py-2 text-sm rounded-lg bg-n-alpha-2 text-n-slate-12 border outline-none"
        :class="
          isInvalid
            ? 'border-n-ruby-8'
            : 'border-transparent focus:border-n-slate-8'
        "
        @keyup.enter="save"
      />
      <p
        v-if="isInvalid"
        data-testid="won-value-error"
        class="mt-1 text-xs text-n-ruby-11"
      >
        {{ $t('RAMON.FUNIL.WON.INVALID') }}
      </p>
      <div class="flex justify-end gap-2 mt-3">
        <button
          data-testid="won-value-skip"
          class="px-3 py-1.5 text-sm rounded-lg text-n-slate-11 hover:text-n-slate-12"
          @click="skip"
        >
          {{ $t('RAMON.FUNIL.WON.SKIP') }}
        </button>
        <button
          data-testid="won-value-save"
          class="px-3 py-1.5 text-sm rounded-lg bg-n-iris-9 text-white hover:bg-n-iris-10 disabled:opacity-50"
          :disabled="isInvalid"
          @click="save"
        >
          {{ $t('RAMON.FUNIL.WON.SAVE') }}
        </button>
      </div>
    </div>
  </div>
</template>
