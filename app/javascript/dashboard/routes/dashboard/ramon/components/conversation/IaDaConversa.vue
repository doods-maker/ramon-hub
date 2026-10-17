<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import RamonIaConversasAPI from 'dashboard/api/ramonIaConversas';
import Button from 'dashboard/components-next/button/Button.vue';
import { CARTAO, LINHA } from '../../helpers/ui';

defineOptions({ name: 'IaDaConversa' });
const { t } = useI18n();
const store = useStore();
const router = useRouter();
const currentChat = useMapGetter('getSelectedChat');
const currentUser = useMapGetter('getCurrentUser');

const open = ref(false);
const saving = ref(false);
const info = ref(null);

const pausa = computed(
  () => currentChat.value?.custom_attributes?.ia_pausa || null
);

// Refaz a leitura ao trocar de conversa e quando a pausa muda (aqui ou por outro agente).
watch(
  () => [currentChat.value?.id, pausa.value],
  async ([id]) => {
    info.value = null;
    if (!id) return;
    try {
      const { data } = await RamonIaConversasAPI.get(id);
      if (id === currentChat.value?.id) info.value = data;
    } catch (e) {
      // sem rótulo: o botão some até a próxima leitura
    }
  },
  { immediate: true }
);

const rotulo = computed(() => {
  if (pausa.value === 'pausada') return t('RAMON.IA_CONVERSA.PAUSADA');
  if (pausa.value === 'rascunho') return t('RAMON.IA_CONVERSA.RASCUNHO');
  const { perfil, origem, etapa } = info.value;
  const params = { perfil, origem: t(`RAMON.IA_CONVERSA.ORIGEM.${origem}`) };
  return etapa
    ? t('RAMON.IA_CONVERSA.BTN', { ...params, etapa })
    : t('RAMON.IA_CONVERSA.BTN_SEM_ETAPA', params);
});

// O backend SUBSTITUI o hash: manda sempre o merge completo; valor null tira a chave.
const gravar = async valor => {
  const { ia_pausa: _antes, ...resto } =
    currentChat.value.custom_attributes || {};
  await store.dispatch('updateCustomAttributes', {
    conversationId: currentChat.value.id,
    customAttributes: valor ? { ...resto, ia_pausa: valor } : resto,
  });
  // updateCustomAttributes engole erro e só comita no sucesso: confirma lendo o store.
  return (currentChat.value?.custom_attributes?.ia_pausa || null) === valor;
};

const escolher = async (valor, { assumir = false } = {}) => {
  if (saving.value) return;
  saving.value = true;
  try {
    if (assumir) {
      await store.dispatch('assignAgent', {
        conversationId: currentChat.value.id,
        agentId: currentUser.value.id,
      });
    }
    const gravou = await gravar(valor);
    // Pausada deixa a conversa pendente parada com o robô: abre pra cair na fila humana.
    if (
      gravou &&
      valor === 'pausada' &&
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

const verNaTrilha = () => {
  open.value = false;
  router.push({
    name: 'captain_como_ia_atende_index',
    query: { alvo: info.value.alvo },
  });
};
</script>

<template>
  <div v-if="info" class="relative">
    <Button
      data-testid="ia-conversa-btn"
      sm
      faded
      slate
      icon="i-lucide-sparkles"
      @click="open = !open"
    >
      <span class="min-w-0 truncate">{{ rotulo }}</span>
      <span class="i-lucide-chevron-down size-3.5 shrink-0" />
    </Button>
    <div v-if="open" class="fixed inset-0 z-40" @click="open = false" />
    <div
      v-if="open"
      class="absolute right-0 top-9 z-50 w-72 shadow-lg"
      :class="CARTAO"
    >
      <p class="text-xs font-medium text-n-slate-11 mb-2">
        {{ t('RAMON.IA_CONVERSA.TITULO') }}
      </p>
      <button
        v-if="pausa !== 'pausada'"
        type="button"
        data-testid="ia-conversa-pausar"
        :class="LINHA"
        @click="escolher('pausada')"
      >
        {{ t('RAMON.IA_CONVERSA.PAUSAR') }}
      </button>
      <button
        v-if="pausa !== 'rascunho'"
        type="button"
        data-testid="ia-conversa-rascunho"
        :class="LINHA"
        @click="escolher('rascunho')"
      >
        {{ t('RAMON.IA_CONVERSA.SO_RASCUNHO') }}
      </button>
      <button
        v-if="pausa"
        type="button"
        data-testid="ia-conversa-voltar"
        :class="LINHA"
        @click="escolher(null)"
      >
        {{ t('RAMON.IA_CONVERSA.VOLTAR') }}
      </button>
      <button
        type="button"
        data-testid="ia-conversa-assumir"
        :class="LINHA"
        @click="escolher('pausada', { assumir: true })"
      >
        {{ t('RAMON.IA_CONVERSA.ASSUMIR') }}
      </button>
      <button
        type="button"
        data-testid="ia-conversa-trilha"
        :class="LINHA"
        @click="verNaTrilha"
      >
        {{ t('RAMON.IA_CONVERSA.TRILHA') }}
      </button>
    </div>
  </div>
</template>
