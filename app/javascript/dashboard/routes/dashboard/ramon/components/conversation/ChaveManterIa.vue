<script setup>
import { computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useQuemAtende } from '../../composables/useQuemAtende';

// Intervenção pontual (decisão Eduardo 20/10): com a IA na conversa, a mensagem da equipe pode sair SEM tirar a IA
// (content_attributes.ramon_manter_ia — Enterprise::Message não abre a conversa). Padrão: ligada quando a IA atende
// sozinha, desligada no Só rascunho (lá o rascunho ajuda o humano a assumir). Não fica lembrada: volta ao padrão a cada
// conversa/estado.
const manter = defineModel({ type: Boolean, default: false });
defineOptions({ name: 'ChaveManterIa' });
const { t } = useI18n();
const { chat, estado } = useQuemAtende();

const visivel = computed(() => ['ia', 'rascunho'].includes(estado.value));

watch(
  () => [chat.value?.id, estado.value],
  () => {
    manter.value = estado.value === 'ia';
  },
  { immediate: true }
);
</script>

<!-- eslint-disable-next-line vue/no-root-v-if -->
<template>
  <label
    v-if="visivel"
    data-testid="chave-manter-ia"
    class="flex cursor-pointer items-center gap-2 px-4 pb-1 text-xs text-n-slate-11"
  >
    <input
      v-model="manter"
      type="checkbox"
      class="accent-n-teal-9"
      data-testid="chave-manter-ia-input"
    />
    {{ t('RAMON.IA_CONVERSA.MANTER_IA') }}
  </label>
</template>
