<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { brlCompact } from '../../helpers/currency';
import { DEFAULT_STAGE_COLOR } from '../../helpers/stage';

// "Funil · conversão" (mock 1b): barra segmentada por etapa aberta +
// "↳ N% avançam" entre etapas, usando o bloco `conversion` do payload.
const props = defineProps({
  stages: { type: Array, default: () => [] },
  conversion: { type: Array, default: () => [] },
});
const emit = defineEmits(['stageSelect']);

const { t } = useI18n();

const openStages = computed(() =>
  props.stages.filter(stage => !stage.is_won && !stage.is_lost)
);
const wonStage = computed(() => props.stages.find(stage => stage.is_won));
const segments = computed(() =>
  openStages.value.filter(stage => Number(stage.count) > 0)
);

const rateByStage = computed(() =>
  Object.fromEntries(props.conversion.map(row => [row.stage_id, row]))
);
// Só mostra a linha de conversão quando alguém de fato entrou na etapa (90d).
const rateFor = stage => {
  const row = rateByStage.value[stage.stage_id];
  return row && row.entered > 0 ? row.rate : null;
};

const color = stage => stage.color || DEFAULT_STAGE_COLOR;
</script>

<template>
  <div
    v-if="stages.length"
    data-testid="funnel-conversion"
    class="flex flex-col gap-2.5 p-4 rounded-[14px] border border-n-weak bg-n-solid-2"
  >
    <div
      v-if="segments.length"
      data-testid="funnel-bar"
      class="flex h-[34px] gap-0.5 overflow-hidden rounded-lg"
    >
      <button
        v-for="stage in segments"
        :key="stage.stage_id"
        type="button"
        data-testid="funnel-bar-segment"
        :title="`${stage.name} · ${stage.count}`"
        :style="{
          flex: `${stage.count} 1 0%`,
          backgroundColor: color(stage),
        }"
        class="opacity-90 hover:opacity-100"
        @click="emit('stageSelect', stage.stage_id)"
      />
    </div>
    <div class="flex flex-col gap-1">
      <template v-for="stage in openStages" :key="stage.stage_id">
        <button
          type="button"
          data-testid="funnel-stage"
          class="flex items-center w-full gap-2 px-1 py-0.5 text-left rounded hover:bg-n-alpha-2"
          @click="emit('stageSelect', stage.stage_id)"
        >
          <span
            class="flex-none size-2 rounded-[2px]"
            :style="{ backgroundColor: color(stage) }"
          />
          <span class="text-[12.5px] truncate text-n-slate-12">
            {{ stage.name }}
          </span>
          <span class="ml-auto text-[12.5px] tabular-nums text-n-slate-10">
            {{ stage.count }} · {{ brlCompact(stage.weighted_value) }}
          </span>
        </button>
        <p
          v-if="rateFor(stage) !== null"
          data-testid="funnel-rate"
          class="pl-4 text-[11px] text-n-slate-9"
        >
          {{ t('RAMON.COMMAND.FUNNEL.ADVANCE', { rate: rateFor(stage) }) }}
        </p>
      </template>
      <button
        v-if="wonStage"
        type="button"
        data-testid="funnel-won"
        class="flex items-center w-full gap-2 px-1 py-0.5 text-left rounded hover:bg-n-alpha-2"
        @click="emit('stageSelect', wonStage.stage_id)"
      >
        <span
          class="flex-none size-2 rounded-[2px]"
          :style="{ backgroundColor: color(wonStage) }"
        />
        <span class="text-[12.5px] truncate text-n-slate-12">
          {{ wonStage.name }}
        </span>
        <span class="ml-auto text-[12.5px] tabular-nums text-n-teal-11">
          {{ wonStage.count }} · {{ brlCompact(wonStage.total_value) }}
        </span>
      </button>
    </div>
  </div>
  <p v-else class="text-sm text-n-slate-10">
    {{ t('RAMON.COMMAND.FUNNEL.EMPTY') }}
  </p>
</template>
