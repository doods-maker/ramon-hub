<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMessageContext } from './provider.js';

defineOptions({ name: 'RascunhoCarimbo' });
const { t } = useI18n();
const { contentAttributes } = useMessageContext();
const desfecho = computed(
  () => contentAttributes.value?.ramonRascunhoIa?.desfecho || 'editado'
);
</script>

<template>
  <!-- eslint-disable vue/no-bare-strings-in-template -->
  <span class="text-xs text-n-slate-10 italic"
    >✦ {{ t(`RAMON.COPILOTO.RASCUNHO_IA.${desfecho}`) }}</span
  >
  <!-- eslint-enable vue/no-bare-strings-in-template -->
</template>
