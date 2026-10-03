<script setup>
import { computed } from 'vue';

// Métrica da caixa lateral (mockup v2 .met): rótulo, valor mono "/ meta" e barra.
const props = defineProps({
  rotulo: { type: String, required: true },
  valor: { type: [Number, String], required: true },
  meta: { type: Number, default: null },
  barra: { type: String, default: null },
});

const pct = computed(() =>
  props.meta
    ? Math.min(100, Math.round((Number(props.valor) / props.meta) * 100))
    : 0
);
</script>

<template>
  <div class="mb-3.5 last:mb-0">
    <div
      class="flex items-baseline justify-between text-[13px] text-n-slate-12"
    >
      {{ rotulo }}
      <b class="font-mono text-sm font-medium">
        {{ valor }}
        <small v-if="meta" class="text-xs font-normal text-n-slate-9">
          {{ `/ ${meta}` }}
        </small>
      </b>
    </div>
    <div
      v-if="barra && meta"
      class="mt-1.5 h-1.5 overflow-hidden rounded-full bg-n-slate-4"
    >
      <i
        class="block h-full rounded-full"
        :class="barra === 'ok' ? 'bg-n-teal-9' : 'bg-n-blue-9'"
        :style="{ width: `${pct}%` }"
      />
    </div>
  </div>
</template>
