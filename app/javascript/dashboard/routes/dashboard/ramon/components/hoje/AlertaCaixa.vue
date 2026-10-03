<script setup>
// Aviso translúcido do "Precisa de você" (mockup v2 .alerta-cx).
defineProps({
  nivel: { type: String, required: true },
  icone: { type: String, required: true },
  titulo: { type: String, required: true },
  texto: { type: String, default: '' },
  acao: { type: Object, default: null },
});

const CAIXA = {
  bad: 'bg-n-ruby-9/10 text-n-ruby-11',
  warn: 'bg-n-amber-9/15 text-n-amber-11',
  act: 'bg-n-blue-9/[0.08] text-n-blue-11 dark:bg-n-blue-9/[0.16]',
};
</script>

<template>
  <div
    class="mb-2 flex items-start gap-3 rounded-[10px] px-3.5 py-3"
    :class="CAIXA[nivel]"
  >
    <span :class="icone" class="mt-0.5 size-[17px] flex-shrink-0" />
    <div class="min-w-0">
      <b class="block text-[13.5px] font-semibold">{{ titulo }}</b>
      <span v-if="texto" class="text-[12.5px] text-n-slate-12">
        {{ texto }}
      </span>
    </div>
    <router-link
      v-if="acao"
      :to="acao.to"
      class="ml-auto self-center whitespace-nowrap rounded-[7px] border border-n-strong px-2.5 py-[5px] text-[12.5px] text-n-slate-12 hover:bg-n-slate-3"
    >
      {{ acao.label }}
    </router-link>
  </div>
</template>
