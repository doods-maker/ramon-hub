<script setup>
import { computed } from 'vue';

const props = defineProps({
  stages: { type: Array, default: () => [] },
});

defineOptions({ name: 'EsteiraEtapas' });

// Etapas "passadas" = anteriores à atual na ordem de position.
const currentIndex = computed(() =>
  props.stages.findIndex(stage => stage.current)
);
const decorated = computed(() =>
  props.stages.map((stage, index) => ({
    ...stage,
    done: currentIndex.value >= 0 && index < currentIndex.value,
  }))
);

const fmtDate = value => {
  if (!value) return '';
  return new Date(value).toLocaleDateString('pt-BR', {
    day: '2-digit',
    month: '2-digit',
  });
};
</script>

<template>
  <ol class="flex items-start w-full pt-2">
    <li
      v-for="(stage, index) in decorated"
      :key="stage.id"
      data-testid="esteira-etapa"
      class="relative flex-1 text-center"
    >
      <div
        v-if="index > 0"
        class="absolute top-[13px] h-0.5 w-full -translate-x-1/2"
        :class="stage.done || stage.current ? 'bg-n-iris-9' : 'bg-n-weak'"
      />
      <div
        data-testid="esteira-selo"
        class="relative z-10 mx-auto mb-1.5 flex size-7 items-center justify-center rounded-full border-2 text-xs font-semibold"
        :class="[
          stage.done || stage.current
            ? 'bg-n-iris-9 border-n-iris-9 text-white'
            : 'bg-n-solid-1 border-n-weak text-n-slate-10',
          stage.current ? 'ring-4 ring-n-iris-9/15' : '',
        ]"
      >
        <span v-if="stage.done" class="i-lucide-check size-3.5" />
        <span v-else>{{ index + 1 }}</span>
      </div>
      <p
        class="text-xs font-semibold"
        :class="stage.current ? 'text-n-iris-11' : 'text-n-slate-10'"
        :data-testid="stage.current ? 'esteira-atual' : undefined"
      >
        {{ stage.name }}
      </p>
      <p
        v-if="stage.entered_at"
        class="text-[11px] tabular-nums text-n-slate-9"
      >
        {{ fmtDate(stage.entered_at) }}
      </p>
    </li>
  </ol>
</template>
