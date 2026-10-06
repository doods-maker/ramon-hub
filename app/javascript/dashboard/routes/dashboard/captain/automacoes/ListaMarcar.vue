<script setup>
// Lista de caixinhas (caixas, etapas, pessoas, etiquetas, times).
import { CAMPO } from 'dashboard/routes/dashboard/ramon/helpers/ui';

const props = defineProps({
  opcoes: { type: Array, required: true },
  modelValue: { type: Array, default: () => [] },
});
const emit = defineEmits(['update:modelValue']);

const alterna = id =>
  emit(
    'update:modelValue',
    props.modelValue.includes(id)
      ? props.modelValue.filter(x => x !== id)
      : [...props.modelValue, id]
  );
</script>

<template>
  <div :class="CAMPO" class="!h-auto max-h-40 overflow-y-auto py-1.5">
    <label
      v-for="opcao in opcoes"
      :key="opcao.id"
      class="flex items-center gap-2 py-0.5 text-sm text-n-slate-12"
    >
      <input
        type="checkbox"
        class="reset-base"
        :checked="modelValue.includes(opcao.id)"
        @change="alterna(opcao.id)"
      />
      {{ opcao.nome }}
    </label>
  </div>
</template>
