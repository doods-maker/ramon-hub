<script setup>
import { computed } from 'vue';

const props = defineProps({
  stages: { type: Array, default: () => [] },
  currentId: { type: Number, default: null },
});
defineOptions({ name: 'MiniEsteira' });

// Perdido fica fora da trilha (mockup: caminho linear até o ganho).
// Preenchido na cor da etapa (--stage herdado do bloco Etapa; sem ela, azul).
const trilha = computed(() =>
  [...props.stages]
    .filter(s => !s.is_lost)
    .sort((a, b) => (a.position ?? 0) - (b.position ?? 0))
);
const currentIndex = computed(() =>
  trilha.value.findIndex(s => s.id === props.currentId)
);
</script>

<template>
  <div class="my-2 flex gap-1" data-testid="mini-esteira">
    <i
      v-for="(stage, index) in trilha"
      :key="stage.id"
      :title="stage.name"
      data-testid="mini-esteira-barra"
      class="h-[3px] flex-1 rounded-sm"
      :class="
        currentIndex >= 0 && index <= currentIndex
          ? 'bg-[color:var(--stage,rgb(var(--blue-9)))]'
          : 'bg-n-alpha-2'
      "
    />
  </div>
</template>
