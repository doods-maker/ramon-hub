<script setup>
defineProps({
  label: { type: String, required: true },
  value: { type: [Number, String], default: 0 },
  danger: { type: Boolean, default: false },
});
</script>

<template>
  <div
    class="flex flex-col p-4 border rounded-xl border-n-weak bg-n-solid-2 min-h-[120px]"
  >
    <p
      class="text-3xl font-cormorant font-semibold"
      :class="danger ? 'text-n-ruby-11' : 'text-n-slate-12'"
    >
      {{ value }}
    </p>
    <p class="mt-1 text-xs tracking-wide uppercase text-n-slate-11">
      {{ label }}
    </p>
    <!-- max-h dá teto ao slot: sem ele o grow nunca ativa o scroll e listas
         longas estouram o layout da página -->
    <div class="mt-2 -mx-1 max-h-48 overflow-y-auto grow">
      <slot />
    </div>
  </div>
</template>
