<script setup>
import { ref, computed } from 'vue';
import { onKeyStroke } from '@vueuse/core';
import { useI18n } from 'vue-i18n';
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
const { t } = useI18n();

// "Outro": texto livre obrigatório quando nenhum motivo da lista serve.
const OUTRO = 'outro';
const reasonId = ref(null);
const detail = ref('');

const isOutro = computed(() => reasonId.value === OUTRO);
const reasonName = computed(() =>
  isOutro.value
    ? t('RAMON.FUNIL.LOST.OTHER')
    : props.lostReasons.find(r => r.id === reasonId.value)?.name
);
// Sem motivo, não confirma (regra 06/10: perdido sempre com motivo).
const canConfirm = computed(
  () => !!reasonName.value && (!isOutro.value || !!detail.value.trim())
);

const confirm = () => {
  if (!canConfirm.value) return;
  // Concatena "Motivo — detalhe" quando há um detalhe livre.
  const text = detail.value.trim()
    ? `${reasonName.value} — ${detail.value.trim()}`
    : reasonName.value;
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
      <!-- sem motivos cadastrados: aponta pra Config; o "Outro" segue valendo -->
      <div v-if="!lostReasons.length" class="mb-3">
        <p data-testid="lost-no-reasons" class="mb-1 text-sm text-n-slate-11">
          {{ $t('RAMON.FUNIL.LOST.NO_REASONS') }}
        </p>
        <router-link
          :to="{ name: 'ramon_funil_config' }"
          class="text-sm font-medium text-n-blue-11 hover:underline"
        >
          {{ $t('RAMON.FUNIL.LOST.CONFIG_LINK') }}
        </router-link>
      </div>
      <div class="flex flex-col gap-3">
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
          <option :value="OUTRO">{{ $t('RAMON.FUNIL.LOST.OTHER') }}</option>
        </select>
        <textarea
          v-model="detail"
          data-testid="lost-reason-detail"
          rows="2"
          maxlength="500"
          :placeholder="
            isOutro
              ? $t('RAMON.FUNIL.LOST.OTHER_PLACEHOLDER')
              : $t('RAMON.FUNIL.LOST.DETAIL_PLACEHOLDER')
          "
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
          data-testid="lost-reason-confirm"
          sm
          ruby
          :label="$t('RAMON.FUNIL.LOST.CONFIRM')"
          :disabled="!canConfirm"
          @click="confirm"
        />
      </div>
    </div>
  </div>
</template>
