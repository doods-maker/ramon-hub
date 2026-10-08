<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import NextButton from 'dashboard/components-next/button/Button.vue';
import MessageList from './MessageList.vue';
import CaptainAssistant from 'dashboard/api/captain/assistant';
import {
  conversaDe,
  garantirConversa,
  limparConversa,
} from './testarConversas';

const { assistantId } = defineProps({
  assistantId: {
    type: Number,
    required: true,
  },
});

const { t } = useI18n();
// I-PG3: a conversa é do assistente, guardada fora do componente (não some ao trocar de tela).
watch(
  () => assistantId,
  id => garantirConversa(id),
  { immediate: true }
);
const messages = computed(() => conversaDe(assistantId));
const newMessage = ref('');
const isLoading = ref(false);

const formatMessagesForApi = () => {
  return messages.value.map(message => {
    const payload = {
      role: message.sender,
      content: message.content,
    };

    if (message.sender === 'assistant' && message.agentName) {
      payload.agent_name = message.agentName;
    }

    return payload;
  });
};

const resetConversation = () => {
  limparConversa(assistantId);
  newMessage.value = '';
};

const sendMessage = async () => {
  if (!newMessage.value.trim() || isLoading.value) return;

  const userMessage = {
    content: newMessage.value,
    sender: 'user',
    timestamp: new Date().toISOString(),
  };
  const conversa = conversaDe(assistantId);
  conversa.push(userMessage);
  const historico = formatMessagesForApi();
  const currentMessage = newMessage.value;
  newMessage.value = '';

  try {
    isLoading.value = true;
    const { data } = await CaptainAssistant.playground({
      assistantId,
      messageContent: currentMessage,
      messageHistory: historico,
    });

    conversa.push({
      content: data.response,
      sender: 'assistant',
      agentName: data.agent_name,
      ferramentas: data.ferramentas || [],
      timestamp: new Date().toISOString(),
    });
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error('Error getting assistant response:', error);
  } finally {
    isLoading.value = false;
  }
};

const handleEnterKey = event => {
  if (event.isComposing) return;
  event.preventDefault();
  sendMessage();
};

// A página do Testar põe a fala de uma skill (escrever) ou o nº do caso (anexar) — nada é enviado sozinho (N7).
const escrever = texto => {
  newMessage.value = texto;
};
const anexar = texto => {
  newMessage.value = [newMessage.value.trim(), texto].filter(Boolean).join(' ');
};
defineExpose({ escrever, anexar });
</script>

<template>
  <div
    class="flex flex-col h-full rounded-xl border py-6 border-n-weak text-n-slate-11"
  >
    <div class="mb-8 px-6">
      <div class="flex justify-between items-center mb-1">
        <h3 class="text-lg font-medium">
          {{ t('CAPTAIN.PLAYGROUND.HEADER') }}
        </h3>
        <NextButton
          ghost
          sm
          slate
          icon="i-lucide-rotate-ccw"
          @click="resetConversation"
        />
      </div>
      <p class="text-sm text-n-slate-11">
        {{ t('CAPTAIN.PLAYGROUND.DESCRIPTION') }}
      </p>
    </div>

    <MessageList :messages="messages" :is-loading="isLoading" />

    <div
      class="flex items-center mx-6 bg-n-background outline outline-1 outline-n-weak rounded-xl p-3"
    >
      <input
        v-model="newMessage"
        class="flex-1 bg-transparent border-none focus:outline-none text-sm mb-0 text-n-slate-12 placeholder:text-n-slate-10"
        :placeholder="t('CAPTAIN.PLAYGROUND.MESSAGE_PLACEHOLDER')"
        @keydown.enter.exact="handleEnterKey"
      />
      <NextButton
        ghost
        sm
        :disabled="!newMessage.trim()"
        icon="i-lucide-send"
        @click="sendMessage"
      />
    </div>
  </div>
</template>
