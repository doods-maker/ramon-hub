<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { MODOS, copilotoModoDe } from '../../helpers/copilotoModo';
import Button from 'dashboard/components-next/button/Button.vue';
import { CARTAO, LINHA } from '../../helpers/ui';

defineOptions({ name: 'CopilotoModoSelector' });
const { t } = useI18n();
const store = useStore();
const currentChat = useMapGetter('getSelectedChat');

const open = ref(false);
const saving = ref(false);

const modo = computed(() => copilotoModoDe(currentChat.value));

const escolher = async novoModo => {
  // Comparar com o valor CRU (não normalizado) — com um valor inválido salvo
  // (ex.: "xablau"), modo.value já cai pra 'rascunho' e clicar em Rascunho
  // viraria no-op, deixando o lixo salvo.
  if (
    saving.value ||
    novoModo === currentChat.value?.custom_attributes?.copiloto_modo
  )
    return;
  saving.value = true;
  try {
    // backend SUBSTITUI o hash: mandar sempre o merge completo
    await store.dispatch('updateCustomAttributes', {
      conversationId: currentChat.value.id,
      customAttributes: {
        ...(currentChat.value.custom_attributes || {}),
        copiloto_modo: novoModo,
      },
    });
    // Manual desliga a IA sem handoff — conversa pendente ficaria parada com o
    // robô. Abre na hora pra cair na fila humana (decisão Eduardo 24/08).
    // Guard lê o store: updateCustomAttributes engole erro e só comita no sucesso.
    if (
      novoModo === 'manual' &&
      currentChat.value?.custom_attributes?.copiloto_modo === 'manual' &&
      currentChat.value?.status === 'pending'
    ) {
      await store.dispatch('toggleStatus', {
        conversationId: currentChat.value.id,
        status: 'open',
      });
    }
    open.value = false;
  } finally {
    saving.value = false;
  }
};
</script>

<template>
  <div class="relative">
    <Button
      data-testid="copiloto-modo-btn"
      sm
      faded
      slate
      icon="i-lucide-sparkles"
      @click="open = !open"
    >
      <span class="min-w-0 truncate">{{
        t('RAMON.COPILOTO.BTN', {
          modo: t(`RAMON.COPILOTO.MODOS.${modo}.NOME`),
        })
      }}</span>
      <span class="i-lucide-chevron-down size-3.5 shrink-0" />
    </Button>
    <div v-if="open" class="fixed inset-0 z-40" @click="open = false" />
    <div
      v-if="open"
      class="absolute right-0 top-9 z-50 w-80 shadow-lg"
      :class="CARTAO"
    >
      <p class="text-xs font-medium text-n-slate-11 mb-2">
        {{ t('RAMON.COPILOTO.TITULO') }}
      </p>
      <button
        v-for="m in MODOS"
        :key="m"
        type="button"
        :data-testid="`copiloto-modo-opcao-${m}`"
        :class="[LINHA, { 'bg-n-alpha-2': m === modo }]"
        @click="escolher(m)"
      >
        <p class="text-sm font-medium text-n-slate-12">
          {{ t(`RAMON.COPILOTO.MODOS.${m}.NOME`) }}
        </p>
        <p class="text-xs text-n-slate-11">
          {{ t(`RAMON.COPILOTO.MODOS.${m}.DESC`) }}
        </p>
        <p v-if="m === 'piloto_limitado'" class="text-xs text-n-slate-10 mt-1">
          {{ t('RAMON.COPILOTO.MODOS.piloto_limitado.NOTA') }}
        </p>
      </button>
    </div>
  </div>
</template>
