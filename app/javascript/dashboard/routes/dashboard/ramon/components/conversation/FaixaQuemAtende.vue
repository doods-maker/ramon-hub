<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import Button from 'dashboard/components-next/button/Button.vue';
import { CHIP } from '../../helpers/ui';
import { useQuemAtende } from '../../composables/useQuemAtende';

// Faixa no topo do painel do lead (conversa): quem atende agora — a IA, uma pessoa ou ninguém — e o atalho
// Devolver à IA / Assumir (o mesmo do botão da IA no cabeçalho).
defineOptions({ name: 'FaixaQuemAtende' });
const { t } = useI18n();
const store = useStore();
const currentUser = useMapGetter('getCurrentUser');
const { chat, pessoa, estado, visual, podeDevolver, devolver } =
  useQuemAtende();
const ocupado = ref(false);

const texto = computed(() =>
  estado.value === 'pessoa'
    ? t('RAMON.IA_CONVERSA.ESTADO.PESSOA', { nome: pessoa.value })
    : t(`RAMON.IA_CONVERSA.FAIXA.${estado.value}`)
);

const agir = async acao => {
  if (ocupado.value) return;
  ocupado.value = true;
  try {
    await acao();
  } finally {
    ocupado.value = false;
  }
};

// Assumir: atribui a mim, pausa a IA e abre a conversa (igual ao botão da IA).
const assumir = async () => {
  const id = chat.value.id;
  await store.dispatch('assignAgent', {
    conversationId: id,
    agentId: currentUser.value.id,
  });
  await store.dispatch('updateCustomAttributes', {
    conversationId: id,
    customAttributes: {
      ...(chat.value.custom_attributes || {}),
      ia_pausa: 'pausada',
    },
  });
  if (chat.value?.status === 'pending')
    await store.dispatch('toggleStatus', {
      conversationId: id,
      status: 'open',
    });
};
</script>

<!-- eslint-disable-next-line vue/no-root-v-if -->
<template>
  <div
    v-if="chat?.id"
    data-testid="faixa-quem-atende"
    :data-estado="estado"
    class="flex items-center gap-2 border-b border-n-weak px-3 py-2"
  >
    <span :class="[CHIP, visual.classe]">
      <span :class="visual.icone" class="size-3.5" />
      {{ texto }}
    </span>
    <Button
      v-if="podeDevolver"
      data-testid="faixa-devolver"
      xs
      faded
      teal
      class="ml-auto"
      :label="t('RAMON.IA_CONVERSA.DEVOLVER')"
      :disabled="ocupado"
      @click="agir(devolver)"
    />
    <Button
      v-else
      data-testid="faixa-assumir"
      xs
      faded
      blue
      class="ml-auto"
      :label="t('RAMON.IA_CONVERSA.ASSUMIR')"
      :disabled="ocupado"
      @click="agir(assumir)"
    />
  </div>
</template>
