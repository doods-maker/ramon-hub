<script setup>
// Selo do mockup v2: pílula mono pequena, fundo translúcido com significado.
const props = defineProps({ tom: { type: String, default: 'neutro' } });

const TONS = {
  ok: 'bg-n-teal-9/15 text-n-teal-11',
  warn: 'bg-n-amber-9/15 text-n-amber-11',
  bad: 'bg-n-ruby-9/10 text-n-ruby-11',
  act: 'bg-n-blue-9/[0.08] text-n-blue-11 dark:bg-n-blue-9/[0.16]',
  neutro: 'bg-n-slate-3 text-n-slate-11',
};
</script>

<template>
  <span
    class="inline-flex items-center gap-1 whitespace-nowrap rounded-full px-2 py-1 font-mono text-[11.5px] font-medium leading-none"
    :class="TONS[props.tom]"
  >
    <slot />
  </span>
</template>
