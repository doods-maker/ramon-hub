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

// ramon_piloto = { perfil, alvo, etapa, handoff, em } (Ramon::PerfilIa#carimbo)
const piloto = computed(() => contentAttributes.value?.ramonPiloto || null);
const pausando = ref(false);
const jaPausada = computed(
  () => !!currentChat.value?.custom_attributes?.ia_pausa
);

const pausar = async () => {
  if (pausando.value) return;
  pausando.value = true;
  try {
    await store.dispatch('updateCustomAttributes', {
      conversationId: currentChat.value.id,
      customAttributes: {
        ...(currentChat.value.custom_attributes || {}),
        ia_pausa: 'rascunho',
      },
    });
    // updateCustomAttributes engole erro de PATCH sem rejeitar a Promise — só a
    // mutation confirma sucesso. Ler o estado ao vivo em vez de assumir.
    useAlert(
      t(`RAMON.IA_CONVERSA.${jaPausada.value ? 'PAUSADO' : 'PAUSA_FALHOU'}`)
    );
  } finally {
    pausando.value = false;
  }
};
</script>

<template>
  <div
    v-if="piloto"
    data-testid="piloto-carimbo"
    class="inline-flex items-center gap-2 rounded-full bg-n-iris-9/10 px-2.5 py-0.5 text-[10.5px] font-medium text-n-iris-11"
  >
    <!-- eslint-disable vue/no-bare-strings-in-template -->
    <span
      >✦ {{ t('RAMON.IA_CONVERSA.CARIMBO', { perfil: piloto.perfil }) }}</span
    >
    <!-- eslint-enable vue/no-bare-strings-in-template -->
    <button
      v-if="!jaPausada"
      type="button"
      data-testid="piloto-pausar"
      class="font-semibold underline disabled:opacity-50"
      :disabled="pausando"
      @click="pausar"
    >
      {{ t('RAMON.IA_CONVERSA.PAUSAR_CARIMBO') }}
    </button>
  </div>
</template>
