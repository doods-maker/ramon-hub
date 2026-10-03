<script setup>
import { computed, ref } from 'vue';
import { useIntervalFn } from '@vueuse/core';
import { useI18n } from 'vue-i18n';
import Selo from './Selo.vue';

// Prazo de 1ª resposta: cinza → âmbar (≤ 2 min) → vermelho (+m:ss). Mockup v2.
const props = defineProps({ prazoEm: { type: String, required: true } });

const { t } = useI18n();
// ref próprio (não o do useNow): o ref do vueuse não re-renderiza nos testes.
const agora = ref(Date.now());
useIntervalFn(() => {
  agora.value = Date.now();
}, 1000);
const segundos = computed(() =>
  Math.round((new Date(props.prazoEm) - agora.value) / 1000)
);
const mmss = s =>
  `${Math.floor(Math.abs(s) / 60)}:${String(Math.abs(s) % 60).padStart(2, '0')}`;
const tom = computed(() => {
  if (segundos.value < 0) return 'bad';
  if (segundos.value <= 120) return 'warn';
  return 'neutro';
});
</script>

<template>
  <Selo
    :tom="tom"
    :title="
      segundos < 0
        ? t('RAMON.HOJE.PRAZO_PASSOU')
        : t('RAMON.HOJE.PRAZO_RESTANTE')
    "
  >
    <span class="i-lucide-clock size-3" />
    {{ segundos < 0 ? `+${mmss(segundos)}` : mmss(segundos) }}
  </Selo>
</template>
