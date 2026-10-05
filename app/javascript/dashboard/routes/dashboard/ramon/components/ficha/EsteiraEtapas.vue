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
const currentIsLost = computed(
  () => props.stages[currentIndex.value]?.is_lost === true
);
const currentIsWon = computed(
  () => props.stages[currentIndex.value]?.is_won === true
);
// cor da etapa atual: perda = ruby, ganho = teal, andamento = azul
const tomAtual = computed(() => {
  if (currentIsLost.value) return 'ruby';
  return currentIsWon.value ? 'teal' : 'blue';
});
const SELO_ATUAL = {
  blue: 'bg-n-blue-9 text-white ring-4 ring-n-blue-9/15',
  teal: 'bg-n-teal-9 text-white ring-4 ring-n-teal-9/15',
  ruby: 'bg-n-ruby-9 text-white ring-4 ring-n-ruby-9/15',
};
const NOME_ATUAL = {
  blue: 'font-semibold text-n-blue-11',
  teal: 'font-semibold text-n-teal-11',
  ruby: 'font-semibold text-n-ruby-11',
};
const decorated = computed(() =>
  props.stages.map((stage, index) => ({
    ...stage,
    done:
      currentIndex.value >= 0 &&
      index < currentIndex.value &&
      !(currentIsLost.value && stage.is_won),
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
  <ol class="flex items-start w-full pt-2 list-none">
    <li
      v-for="(stage, index) in decorated"
      :key="stage.id"
      data-testid="esteira-etapa"
      class="relative flex-1 text-center"
    >
      <div
        v-if="index > 0"
        class="absolute top-[13px] h-0.5 w-full -translate-x-1/2"
        :class="stage.done || stage.current ? 'bg-n-blue-9' : 'bg-n-weak'"
      />
      <!-- passada = contorno azul com ✓; atual = cheia na cor de tomAtual -->
      <div
        data-testid="esteira-selo"
        class="relative z-10 mx-auto mb-1.5 flex size-7 items-center justify-center rounded-full font-mono text-xs font-medium"
        :class="[
          stage.current
            ? SELO_ATUAL[tomAtual]
            : stage.done
              ? 'bg-n-solid-1 text-n-blue-11 outline outline-1 outline-n-blue-9'
              : 'bg-n-solid-1 text-n-slate-10 outline outline-1 outline-n-weak',
        ]"
      >
        <span v-if="stage.done" class="i-lucide-check size-3.5" />
        <span v-else>{{ index + 1 }}</span>
      </div>
      <p
        class="text-xs"
        :class="
          stage.current ? NOME_ATUAL[tomAtual] : 'font-medium text-n-slate-10'
        "
        :data-testid="stage.current ? 'esteira-atual' : undefined"
      >
        {{ stage.name }}
      </p>
      <p
        v-if="stage.entered_at"
        class="mt-0.5 font-mono text-[11px] tabular-nums text-n-slate-9"
      >
        {{ fmtDate(stage.entered_at) }}
      </p>
    </li>
  </ol>
</template>
