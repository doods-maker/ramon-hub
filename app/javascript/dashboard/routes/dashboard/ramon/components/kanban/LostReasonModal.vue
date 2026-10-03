<script setup>
import { ref, computed } from 'vue';
import { onKeyStroke } from '@vueuse/core';
import Button from 'dashboard/components-next/button/Button.vue';
import {
  SELECT,
  TEXTAREA,
  FUNDO_JANELA,
  JANELA,
  TITULO_JANELA,
  RODAPE_JANELA,
} from '../../helpers/ui';

const props = defineProps({
  lostReasons: { type: Array, default: () => [] },
});
const emit = defineEmits(['confirmMove', 'cancelMove']);

const reasonId = ref(null);
const detail = ref('');

const selectedReason = computed(() =>
  props.lostReasons.find(r => r.id === reasonId.value)
);

const confirm = () => {
  if (!selectedReason.value) return;
  // Concatena "Motivo — detalhe" quando há um detalhe livre.
  const text = detail.value.trim()
    ? `${selectedReason.value.name} — ${detail.value.trim()}`
    : selectedReason.value.name;
  emit('confirmMove', { lostReason: text });
};

// Esc cancela (reverte o drag), igual ao clique no backdrop — exceto com o
// textarea focado e com texto: Esc por reflexo não descarta o detalhe digitado.
onKeyStroke('Escape', () => {
  if (
    document.activeElement?.tagName === 'TEXTAREA' &&
    detail.value.trim() !== ''
  )
    return;
  emit('cancelMove');
});
</script>

<template>
  <div :class="FUNDO_JANELA" @click.self="emit('cancelMove')">
    <div :class="JANELA">
      <h3 :class="TITULO_JANELA">
        {{ $t('RAMON.FUNIL.LOST.TITLE') }}
      </h3>
      <!-- sem motivos cadastrados: aponta pra Config em vez do beco sem saída -->
      <template v-if="!lostReasons.length">
        <p data-testid="lost-no-reasons" class="mb-2 text-sm text-n-slate-11">
          {{ $t('RAMON.FUNIL.LOST.NO_REASONS') }}
        </p>
        <router-link
          :to="{ name: 'ramon_funil_config' }"
          class="text-sm font-medium text-n-blue-11 hover:underline"
        >
          {{ $t('RAMON.FUNIL.LOST.CONFIG_LINK') }}
        </router-link>
      </template>
      <div v-else class="flex flex-col gap-3">
        <select
          v-model="reasonId"
          data-testid="lost-reason-select"
          :class="SELECT"
        >
          <option :value="null" disabled>
            {{ $t('RAMON.FUNIL.LOST.PICK') }}
          </option>
          <option v-for="r in lostReasons" :key="r.id" :value="r.id">
            {{ r.name }}
          </option>
        </select>
        <textarea
          v-model="detail"
          data-testid="lost-reason-detail"
          rows="2"
          maxlength="500"
          :placeholder="$t('RAMON.FUNIL.LOST.DETAIL_PLACEHOLDER')"
          class="resize-none"
          :class="TEXTAREA"
        />
      </div>
      <div :class="RODAPE_JANELA">
        <Button
          sm
          faded
          slate
          :label="$t('RAMON.FUNIL.LOST.CANCEL')"
          @click="emit('cancelMove')"
        />
        <Button
          v-if="lostReasons.length"
          data-testid="lost-reason-confirm"
          sm
          ruby
          :label="$t('RAMON.FUNIL.LOST.CONFIRM')"
          :disabled="!selectedReason"
          @click="confirm"
        />
      </div>
    </div>
  </div>
</template>
