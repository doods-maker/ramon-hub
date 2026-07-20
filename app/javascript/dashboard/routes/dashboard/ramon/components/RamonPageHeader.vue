<script setup>
// Cabeçalho padrão das telas da Intranet: eyebrow + título Cormorant +
// subtítulo, com slot de ações à direita. `compact` para páginas de conteúdo
// (Dossiê, Linha da Vida) que vivem dentro de um pane menor.
defineProps({
  eyebrow: { type: String, default: '' },
  title: { type: String, required: true },
  subtitle: { type: String, default: '' },
  compact: { type: Boolean, default: false },
});
</script>

<template>
  <header
    class="flex flex-wrap items-start justify-between gap-x-4 gap-y-2"
    :class="compact ? 'mb-6' : 'mb-8'"
  >
    <div class="min-w-0">
      <p
        v-if="eyebrow"
        class="text-xs tracking-[0.2em] uppercase text-n-slate-11"
      >
        {{ eyebrow }}
      </p>
      <h1
        class="font-cormorant font-semibold text-n-slate-12"
        :class="compact ? 'text-2xl' : 'text-4xl'"
      >
        {{ title }}
      </h1>
      <p v-if="subtitle" class="mt-0.5 text-sm text-n-slate-11">
        {{ subtitle }}
      </p>
    </div>
    <div v-if="$slots.actions" class="flex flex-wrap items-center gap-2 pt-1">
      <slot name="actions" />
    </div>
  </header>
</template>
