<script setup>
import { computed, ref } from 'vue';
import { vOnClickOutside } from '@vueuse/components';

// Chip de filtro do cabeçalho do funil (mockup v2 .filtro): tracejado com "+"
// quando vazio; sólido azul translúcido com o valor e "×" quando escolhido.
const props = defineProps({
  label: { type: String, required: true },
  // [{ id, name }]
  options: { type: Array, default: () => [] },
  modelValue: { type: [String, Number], default: null },
});
const emit = defineEmits(['update:modelValue']);

const open = ref(false);
const chosen = computed(() =>
  props.options.find(o => String(o.id) === String(props.modelValue))
);
const pick = id => {
  open.value = false;
  emit('update:modelValue', id);
};
</script>

<template>
  <div v-on-click-outside="() => (open = false)" class="relative">
    <button
      v-if="modelValue"
      type="button"
      data-testid="filtro-chip-on"
      :title="$t('RAMON.FUNIL.CHIP.LIMPAR')"
      class="inline-flex items-center gap-1.5 rounded-[7px] border border-transparent bg-n-blue-9/[0.08] px-2.5 py-1.5 text-[12.5px] font-medium text-n-blue-11 dark:bg-n-blue-9/[0.16]"
      @click="pick(null)"
    >
      {{ `${label}: ${chosen?.name || modelValue}` }}
      <span class="i-lucide-x size-3.5" />
    </button>
    <button
      v-else
      type="button"
      data-testid="filtro-chip-off"
      class="inline-flex items-center gap-1.5 rounded-[7px] border border-dashed border-n-strong px-2.5 py-1.5 text-[12.5px] text-n-slate-11 hover:bg-n-slate-3"
      @click="open = !open"
    >
      <span class="i-lucide-plus size-3.5" />{{ label }}
    </button>
    <ul
      v-if="open"
      class="absolute z-40 mt-1 max-h-72 w-56 overflow-y-auto rounded-lg border border-n-weak bg-n-background p-1 shadow-lg"
    >
      <li v-for="option in options" :key="option.id">
        <button
          type="button"
          class="w-full truncate rounded-md px-2 py-1.5 text-left text-[13px] text-n-slate-12 hover:bg-n-slate-3"
          @click="pick(option.id)"
        >
          {{ option.name }}
        </button>
      </li>
    </ul>
  </div>
</template>
