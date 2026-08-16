<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useMessageContext } from './provider.js';

defineOptions({ name: 'PilotoCarimbo' });
const { t } = useI18n();
const store = useStore();
const currentChat = useMapGetter('getSelectedChat');
const { contentAttributes } = useMessageContext();

const piloto = computed(() => contentAttributes.value?.ramonPiloto || null);
const pausando = ref(false);
const aindaEmPiloto = computed(() =>
  (currentChat.value?.custom_attributes?.copiloto_modo || '').startsWith(
    'piloto_'
  )
);

const pausar = async () => {
  if (pausando.value) return;
  pausando.value = true;
  try {
    await store.dispatch('updateCustomAttributes', {
      conversationId: currentChat.value.id,
      customAttributes: {
        ...(currentChat.value.custom_attributes || {}),
        copiloto_modo: 'rascunho',
      },
    });
    useAlert(t('RAMON.COPILOTO.PAUSADO'));
  } finally {
    pausando.value = false;
  }
};
</script>

<template>
  <div
    v-if="piloto"
    data-testid="piloto-carimbo"
    class="mt-0.5 flex items-center gap-2 self-end text-[10.5px] text-n-teal-11"
  >
    <!-- eslint-disable vue/no-bare-strings-in-template -->
    <span
      >✦
      {{
        t('RAMON.COPILOTO.CARIMBO', {
          modo: t(`RAMON.COPILOTO.MODOS.${piloto.modo}.NOME`),
        })
      }}</span
    >
    <!-- eslint-enable vue/no-bare-strings-in-template -->
    <button
      v-if="aindaEmPiloto"
      type="button"
      data-testid="piloto-pausar"
      class="font-semibold underline disabled:opacity-50"
      :disabled="pausando"
      @click="pausar"
    >
      {{ t('RAMON.COPILOTO.PAUSAR') }}
    </button>
  </div>
</template>
