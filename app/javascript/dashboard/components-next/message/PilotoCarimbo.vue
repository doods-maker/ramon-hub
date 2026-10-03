<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { copilotoModoDe } from 'dashboard/routes/dashboard/ramon/helpers/copilotoModo';
import { useMessageContext } from './provider.js';

defineOptions({ name: 'PilotoCarimbo' });
const { t } = useI18n();
const store = useStore();
const currentChat = useMapGetter('getSelectedChat');
const { contentAttributes } = useMessageContext();

const piloto = computed(() => contentAttributes.value?.ramonPiloto || null);
const pausando = ref(false);
const aindaEmPiloto = computed(() =>
  copilotoModoDe(currentChat.value).startsWith('piloto_')
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
    // updateCustomAttributes engole erro de PATCH sem rejeitar a Promise — só a
    // mutation confirma sucesso. Ler o estado ao vivo em vez de assumir que o
    // dispatch funcionou.
    if (aindaEmPiloto.value) {
      useAlert(t('RAMON.COPILOTO.PAUSA_FALHOU'));
    } else {
      useAlert(t('RAMON.COPILOTO.PAUSADO'));
    }
  } finally {
    pausando.value = false;
  }
};
</script>

<template>
  <div
    v-if="piloto"
    data-testid="piloto-carimbo"
    class="flex items-center gap-2 text-[10.5px] text-n-teal-11"
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
