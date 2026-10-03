<script setup>
import { ref, computed } from 'vue';
import { onKeyStroke } from '@vueuse/core';
import Button from 'dashboard/components-next/button/Button.vue';
import {
  SELECT,
  AVISO,
  TOM,
  FUNDO_JANELA,
  JANELA,
  TITULO_JANELA,
  RODAPE_JANELA,
} from '../../helpers/ui';

const props = defineProps({
  stage: { type: Object, required: true },
  stages: { type: Array, default: () => [] },
  // Leads VISÍVEIS na etapa (o board pode estar filtrado — o backend move
  // todos, então o destino é sempre escolha do usuário).
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
  if (noTarget.value || !targetId.value) return;
  emit('confirm', { id: props.stage.id, moveToStageId: targetId.value });
};

onKeyStroke('Escape', () => emit('cancel'));
</script>

<template>
  <div :class="FUNDO_JANELA" @click.self="emit('cancel')">
    <div :class="JANELA">
      <h3 :class="TITULO_JANELA">
        {{ $t('RAMON.FUNIL.STAGE.REMOVE_TITLE', { name: stage.name }) }}
      </h3>
      <div class="flex flex-col gap-3">
        <p
          v-if="leadsCount > 0"
          data-testid="remove-count"
          class="mb-0 text-xs text-n-slate-11"
        >
          {{ $t('RAMON.FUNIL.STAGE.REMOVE_COUNT', { count: leadsCount }) }}
        </p>
        <p
          v-else
          data-testid="remove-empty"
          class="mb-0 text-xs text-n-slate-11"
        >
          {{ $t('RAMON.FUNIL.STAGE.REMOVE_EMPTY') }}
        </p>
        <p
          v-if="noTarget"
          data-testid="remove-no-target"
          class="mb-0"
          :class="[AVISO, TOM.amber]"
        >
          {{ $t('RAMON.FUNIL.STAGE.REMOVE_NO_TARGET') }}
        </p>
        <select
          v-if="options.length"
          v-model="targetId"
          data-testid="remove-target"
          :class="SELECT"
        >
          <option :value="null" disabled>
            {{ $t('RAMON.FUNIL.STAGE.REMOVE_PICK') }}
          </option>
          <option v-for="s in options" :key="s.id" :value="s.id">
            {{ s.name }}
          </option>
        </select>
      </div>
      <div :class="RODAPE_JANELA">
        <Button
          sm
          faded
          slate
          :label="$t('RAMON.FUNIL.STAGE.CANCEL')"
          @click="emit('cancel')"
        />
        <Button
          data-testid="remove-confirm"
          sm
          ruby
          :label="$t('RAMON.FUNIL.STAGE.REMOVE_CONFIRM')"
          :disabled="noTarget || !targetId"
          @click="confirm"
        />
      </div>
    </div>
  </div>
</template>
