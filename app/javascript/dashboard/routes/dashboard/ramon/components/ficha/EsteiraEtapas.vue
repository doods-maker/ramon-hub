<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { DEFAULT_STAGE_COLOR } from '../../helpers/stage';
import { desde } from '../hoje/hoje';

const props = defineProps({
  stages: { type: Array, default: () => [] },
});

defineOptions({ name: 'EsteiraEtapas' });

const { t } = useI18n();

// Etapas "feitas" = anteriores à atual na ordem de position. Lead perdido:
// a etapa de ganho que ficou pra trás nunca conta como feita.
const currentIndex = computed(() =>
  props.stages.findIndex(stage => stage.current)
);
const currentIsLost = computed(
  () => props.stages[currentIndex.value]?.is_lost === true
);
const decorated = computed(() =>
  props.stages.map((stage, index) => ({
    ...stage,
    done:
      currentIndex.value >= 0 &&
      index < currentIndex.value &&
      !(currentIsLost.value && stage.is_won),
  }))
);

const barra = stage => {
  if (stage.current && currentIsLost.value) return 'bg-n-ruby-9';
  return stage.done || stage.current ? 'bg-[var(--stage)]' : 'bg-n-slate-4';
};
const nome = stage => {
  if (!stage.current) return 'text-n-slate-11';
  return currentIsLost.value
    ? 'font-semibold text-n-ruby-11'
    : 'font-semibold ramon-stage-text';
};
// atual: "há N dias"; passadas: dd/mm
const quando = stage => {
  if (!stage.entered_at) return '';
  if (stage.current) {
    const { key, count } = desde(stage.entered_at);
    return t('RAMON.FICHA.HA', {
      tempo: t(`RAMON.HOJE.${key}`, { count }, count),
    });
  }
  return new Date(stage.entered_at).toLocaleDateString('pt-BR', {
    day: '2-digit',
    month: '2-digit',
  });
};
</script>

<template>
  <!-- mockup v2: barrinha de 3 px por etapa, nome e data embaixo -->
  <ol class="flex w-full gap-1.5">
    <li
      v-for="stage in decorated"
      :key="stage.id"
      data-testid="esteira-etapa"
      class="flex-1 min-w-0"
      :style="{ '--stage': stage.color || DEFAULT_STAGE_COLOR }"
    >
      <div
        data-testid="esteira-selo"
        class="h-[3px] rounded-full"
        :class="barra(stage)"
      />
      <p
        class="mt-2 truncate text-[12.5px]"
        :class="nome(stage)"
        :data-testid="stage.current ? 'esteira-atual' : undefined"
      >
        {{ stage.name }}
      </p>
      <p class="font-mono text-[11.5px] text-n-slate-9">
        {{ quando(stage) }}
      </p>
    </li>
  </ol>
</template>
