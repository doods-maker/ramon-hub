<script setup>
import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useMessageContext } from '../provider.js';
import { useDocSugestao } from 'dashboard/routes/dashboard/ramon/composables/useDocSugestao';

const { content, contentAttributes } = useMessageContext();

const currentChat = useMapGetter('getSelectedChat');
const leadByConv = useMapGetter('leads/getLeadByConversationId');
const lead = computed(() => {
  const id = currentChat.value?.id;
  return id ? leadByConv.value(Number(id)) : undefined;
});

const isDocMatch = computed(
  () => contentAttributes.value?.ramonEvent === 'doc_match'
);

// Ações só enquanto a MESMA sugestão (mesmo anexo) segue pendente no lead —
// evento antigo vira registro estático.
const sugestaoAtiva = computed(() => {
  if (!isDocMatch.value) return false;
  const s = lead.value?.custom_attributes?.doc_sugestao;
  const itemId = contentAttributes.value?.itemId;
  const jaRecebido =
    lead.value?.custom_attributes?.doc_status?.[itemId] === 'recebido';
  return (
    !!s &&
    !s.resolvida &&
    !jaRecebido &&
    Number(s.attachment_id) === Number(contentAttributes.value?.attachmentId)
  );
});

const { pending, resolver } = useDocSugestao(lead);
const responder = aceitar =>
  resolver(aceitar, {
    itemId: contentAttributes.value?.itemId,
    attachmentId: contentAttributes.value?.attachmentId,
  });
</script>

<template>
  <div
    data-bubble-name="ramon-event"
    class="mx-auto max-w-[78%] rounded-xl border border-dashed border-n-iris-9/50 bg-n-iris-9/10 px-4 py-2 text-center text-xs text-n-iris-11"
  >
    <span v-dompurify-html="content" />
    <div
      v-if="sugestaoAtiva"
      class="mt-1.5 flex items-center justify-center gap-4"
    >
      <button
        type="button"
        data-testid="ramon-event-confirm"
        class="font-semibold underline disabled:opacity-60"
        :disabled="pending"
        @click="responder(true)"
      >
        {{ $t('RAMON.DOCS.SUGESTAO.CONFIRMAR') }}
      </button>
      <button
        type="button"
        data-testid="ramon-event-dismiss"
        class="underline opacity-70 disabled:opacity-40"
        :disabled="pending"
        @click="responder(false)"
      >
        {{ $t('RAMON.DOCS.SUGESTAO.DISPENSAR') }}
      </button>
    </div>
  </div>
</template>
