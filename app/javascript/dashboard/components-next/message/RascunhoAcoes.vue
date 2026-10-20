<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import { useMessageContext } from './provider.js';

// Nota-rascunho da IA/automação na conversa: 1ª linha "RASCUNHO (revisar antes de enviar)…", texto nas seguintes.
// Enviar = aprovação de quem clica (o hub carimba "enviado como estava"); Editar põe o texto na caixa; Copiar copia.
// Quem decide se é rascunho: Message.vue (nota privada que começa com o prefixo).
defineOptions({ name: 'RascunhoAcoes' });
const { t } = useI18n();
const store = useStore();
const { content, conversationId } = useMessageContext();

const texto = computed(() =>
  (content.value || '').split('\n').slice(1).join('\n').trim()
);
const enviando = ref(false);
const enviado = ref(false);

const enviar = async () => {
  if (enviando.value || enviado.value) return;
  enviando.value = true;
  try {
    await store.dispatch('createPendingMessageAndSend', {
      conversationId: conversationId.value,
      message: texto.value,
      private: false,
    });
    enviado.value = true;
    emitter.emit(BUS_EVENTS.SCROLL_TO_MESSAGE);
  } catch {
    useAlert(t('RAMON.RASCUNHO_ACOES.FALHOU'));
  } finally {
    enviando.value = false;
  }
};

const editar = () =>
  emitter.emit(BUS_EVENTS.INSERT_INTO_NORMAL_EDITOR, texto.value);

const copiar = async () => {
  await copyTextToClipboard(texto.value);
  useAlert(t('RAMON.RASCUNHO_ACOES.COPIADO'));
};
</script>

<!-- eslint-disable-next-line vue/no-root-v-if -->
<template>
  <div
    v-if="texto"
    data-testid="rascunho-acoes"
    class="inline-flex items-center gap-3 text-xs font-medium"
  >
    <span v-if="enviado" class="text-n-teal-11">
      {{ t('RAMON.RASCUNHO_ACOES.ENVIADO') }}
    </span>
    <button
      v-else
      type="button"
      data-testid="rascunho-enviar"
      class="rounded-full bg-n-brand px-2.5 py-0.5 text-white disabled:opacity-50"
      :disabled="enviando"
      @click="enviar"
    >
      {{ t('RAMON.RASCUNHO_ACOES.ENVIAR') }}
    </button>
    <button
      type="button"
      data-testid="rascunho-editar"
      class="text-n-slate-11 underline"
      @click="editar"
    >
      {{ t('RAMON.RASCUNHO_ACOES.EDITAR') }}
    </button>
    <button
      type="button"
      data-testid="rascunho-copiar"
      class="text-n-slate-11 underline"
      @click="copiar"
    >
      {{ t('RAMON.RASCUNHO_ACOES.COPIAR') }}
    </button>
  </div>
</template>
