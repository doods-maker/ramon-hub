<script setup>
import { ref } from 'vue';
import { parseBrlInput } from '../../helpers/currency';

const emit = defineEmits(['confirmValue', 'cancelValue']);

const value = ref('');

// Salvar envia o valor; Pular move sem valor; o clique fora cancela (reverte).
const save = () => emit('confirmValue', { value: parseBrlInput(value.value) });
const skip = () => emit('confirmValue', { value: null });
const cancel = () => emit('cancelValue');
</script>

<template>
  <div
    class="fixed inset-0 z-50 flex items-center justify-center bg-black/50"
    @click.self="cancel"
  >
    <div class="w-80 p-4 rounded-xl bg-n-solid-2 border border-n-weak">
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
          class="px-3 py-1.5 text-sm rounded text-n-slate-11"
          @click="skip"
        >
          {{ $t('RAMON.FUNIL.WON.SKIP') }}
        </button>
        <button
          data-testid="won-value-save"
          class="px-3 py-1.5 text-sm rounded bg-n-iris-9 text-white"
          @click="save"
        >
          {{ $t('RAMON.FUNIL.WON.SAVE') }}
        </button>
      </div>
    </div>
  </div>
</template>
