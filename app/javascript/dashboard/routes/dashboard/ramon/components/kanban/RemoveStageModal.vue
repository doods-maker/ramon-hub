<script setup>
import { ref, computed } from 'vue';
import { onKeyStroke } from '@vueuse/core';

const props = defineProps({
  stage: { type: Object, required: true },
  stages: { type: Array, default: () => [] },
  // Quantos leads estão na etapa (vem do board): 0 = remoção direta.
  leadsCount: { type: Number, default: 0 },
});
const emit = defineEmits(['confirm', 'cancel']);

const targetId = ref(null);
const options = computed(() =>
  props.stages.filter(s => s.id !== props.stage.id)
);

// Sem destino possível (funil de 1 etapa): o backend exige move_to_stage_id,
// então não dá pra remover nem etapa vazia.
const noTarget = computed(() => !options.value.length);

const confirm = () => {
  if (noTarget.value) return;
  // Etapa vazia: nada a mover — remove direto usando o primeiro destino
  // disponível (o backend exige um destino mesmo sem leads).
  const moveToStageId =
    props.leadsCount > 0 ? targetId.value : options.value[0].id;
  if (!moveToStageId) return;
  emit('confirm', { id: props.stage.id, moveToStageId });
};

onKeyStroke('Escape', () => emit('cancel'));
</script>

<template>
  <div
    class="fixed inset-0 z-50 flex items-center justify-center bg-black/50"
    @click.self="emit('cancel')"
  >
    <div
      class="w-80 max-w-[92vw] p-5 rounded-xl bg-n-solid-2 border border-n-weak"
    >
      <h3 class="mb-3 text-sm text-n-slate-12">
        {{
          leadsCount > 0
            ? $t('RAMON.FUNIL.STAGE.REMOVE_TITLE', { name: stage.name })
            : $t('RAMON.FUNIL.STAGE.REMOVE_TITLE_EMPTY', { name: stage.name })
        }}
      </h3>
      <p
        v-if="leadsCount > 0"
        data-testid="remove-count"
        class="mb-3 text-xs text-n-slate-11"
      >
        {{ $t('RAMON.FUNIL.STAGE.REMOVE_COUNT', { count: leadsCount }) }}
      </p>
      <p v-else data-testid="remove-empty" class="mb-3 text-xs text-n-slate-11">
        {{ $t('RAMON.FUNIL.STAGE.REMOVE_EMPTY') }}
      </p>
      <p
        v-if="noTarget"
        data-testid="remove-no-target"
        class="mb-3 text-xs text-n-amber-11"
      >
        {{ $t('RAMON.FUNIL.STAGE.REMOVE_NO_TARGET') }}
      </p>
      <select
        v-if="leadsCount > 0 && options.length"
        v-model="targetId"
        data-testid="remove-target"
        class="w-full px-2 py-1.5 mb-3 text-sm rounded-lg bg-n-alpha-2 text-n-slate-12 border border-transparent focus:border-n-slate-8 outline-none"
      >
        <option :value="null" disabled>
          {{ $t('RAMON.FUNIL.STAGE.REMOVE_PICK') }}
        </option>
        <option v-for="s in options" :key="s.id" :value="s.id">
          {{ s.name }}
        </option>
      </select>
      <div class="flex justify-end gap-2">
        <button
          class="px-3 py-1.5 text-sm rounded-lg text-n-slate-11 hover:text-n-slate-12"
          @click="emit('cancel')"
        >
          {{ $t('RAMON.FUNIL.STAGE.CANCEL') }}
        </button>
        <button
          data-testid="remove-confirm"
          class="px-3 py-1.5 text-sm rounded-lg bg-n-ruby-9 text-white disabled:opacity-50"
          :disabled="noTarget || (leadsCount > 0 && !targetId)"
          @click="confirm"
        >
          {{ $t('RAMON.FUNIL.STAGE.REMOVE_CONFIRM') }}
        </button>
      </div>
    </div>
  </div>
</template>
