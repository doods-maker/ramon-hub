<script setup>
// Seção da tela Hoje (mockup v2 .bloco): título + contagem mono, dica, fila com
// linha fina em cima (fila=false tira a linha); total 0 com `vazio` mostra o texto.
defineProps({
  titulo: { type: String, required: true },
  total: { type: Number, default: null },
  dica: { type: String, default: '' },
  vazio: { type: String, default: '' },
  fila: { type: Boolean, default: true },
});
</script>

<template>
  <section class="mb-8">
    <div class="mb-1 flex items-baseline gap-2.5">
      <h2 class="text-[14.5px] font-semibold text-n-slate-12">{{ titulo }}</h2>
      <span v-if="total !== null" class="font-mono text-xs text-n-slate-9">
        {{ total }}
      </span>
      <div class="ml-auto"><slot name="acao" /></div>
    </div>
    <p v-if="dica" class="mb-2 text-[12.5px] text-n-slate-9">{{ dica }}</p>
    <div
      v-if="total === 0 && vazio"
      class="border-n-weak py-4 text-[13px] text-n-slate-9"
      :class="{ 'border-t': fila }"
    >
      {{ vazio }}
    </div>
    <div v-else class="border-n-weak" :class="{ 'border-t': fila }">
      <slot />
    </div>
  </section>
</template>
