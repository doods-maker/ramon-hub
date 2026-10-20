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
// modo 'enviar' = botão embaixo da nota; 'icones' = lápis (Editar) e copiar no canto da nota (decisão Eduardo 20/10).
const props = defineProps({
  modo: { type: String, default: 'enviar' },
});
defineOptions({ name: 'RascunhoAcoes' });
const { t } = useI18n();
const store = useStore();
const { content, conversationId } = useMessageContext();

const texto = computed(() =>
  (content.value || '').split('\n').slice(1).join('\n').trim()
);
const enviando = ref(false);
const enviado = ref(false);

// manterIa: "Enviar, IA segue" (a conversa continua com a IA); senão "Enviar e assumir" (resposta humana abre a conversa).
const enviar = async manterIa => {
  if (enviando.value || enviado.value) return;
  enviando.value = true;
  try {
    await store.dispatch('createPendingMessageAndSend', {
      conversationId: conversationId.value,
      message: texto.value,
      private: false,
      ...(manterIa && { contentAttributes: { ramon_manter_ia: true } }),
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
    v-if="texto && props.modo === 'icones'"
    data-testid="rascunho-icones"
    class="flex items-center gap-0.5"
  >
    <button
      type="button"
      data-testid="rascunho-editar"
      class="rounded-md p-1 text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
      :title="t('RAMON.RASCUNHO_ACOES.EDITAR')"
      :aria-label="t('RAMON.RASCUNHO_ACOES.EDITAR')"
      @click="editar"
    >
      <span class="i-lucide-pencil size-3.5 block" />
    </button>
    <button
      type="button"
      data-testid="rascunho-copiar"
      class="rounded-md p-1 text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
      :title="t('RAMON.RASCUNHO_ACOES.COPIAR')"
      :aria-label="t('RAMON.RASCUNHO_ACOES.COPIAR')"
      @click="copiar"
    >
      <span class="i-lucide-copy size-3.5 block" />
    </button>
  </div>
  <div
    v-else-if="texto"
    data-testid="rascunho-acoes"
    class="inline-flex items-center gap-3 text-xs font-medium"
  >
    <span v-if="enviado" class="text-n-teal-11">
      {{ t('RAMON.RASCUNHO_ACOES.ENVIADO') }}
    </span>
    <template v-else>
      <button
        type="button"
        data-testid="rascunho-enviar"
        class="rounded-full bg-n-brand px-2.5 py-0.5 text-white disabled:opacity-50"
        :disabled="enviando"
        @click="enviar(false)"
      >
        {{ t('RAMON.RASCUNHO_ACOES.ENVIAR') }}
      </button>
      <button
        type="button"
        data-testid="rascunho-enviar-ia-segue"
        class="rounded-full bg-n-teal-9/15 px-2.5 py-0.5 text-n-teal-11 disabled:opacity-50"
        :disabled="enviando"
        @click="enviar(true)"
      >
        {{ t('RAMON.RASCUNHO_ACOES.ENVIAR_IA_SEGUE') }}
      </button>
    </template>
  </div>
</template>
