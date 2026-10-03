<script setup>
// Linha recolhível do painel do lead (mockup v2 .recolhe). Atributos (ex.:
// data-testid) vão pro botão, pra clicar direto nos testes e no teclado.
defineProps({
  titulo: { type: String, required: true },
  contagem: { type: String, default: null },
  ponto: { type: String, default: null },
  aberta: { type: Boolean, default: false },
});
defineEmits(['alternar']);
defineOptions({ name: 'SecaoRecolhivel', inheritAttrs: false });
</script>

<template>
  <div class="border-b border-n-weak">
    <button
      type="button"
      class="flex w-full items-center px-[18px] py-3 text-left text-[13px] text-n-slate-11 hover:bg-n-slate-3 hover:text-n-slate-12"
      :aria-expanded="aberta"
      v-bind="$attrs"
      @click="$emit('alternar')"
    >
      {{ titulo }}
      <span v-if="ponto" class="ml-1.5 size-1.5 rounded-full" :class="ponto" />
      <span
        v-if="contagem"
        class="ml-auto mr-2 font-mono text-[12.5px] text-n-slate-9"
      >
        {{ contagem }}
      </span>
      <span
        class="i-lucide-chevron-right size-4 flex-shrink-0 transition-transform motion-reduce:transition-none"
        :class="{ 'rotate-90': aberta, 'ml-auto': !contagem }"
      />
    </button>
    <div v-if="aberta" class="min-w-0 px-[18px] pb-4">
      <slot />
    </div>
  </div>
</template>
