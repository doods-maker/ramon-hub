<script setup>
import { useI18n } from 'vue-i18n';
import { ref, watch, nextTick } from 'vue';
import { useMessageFormatter } from 'shared/composables/useMessageFormatter';
import { CHIP, TOM } from 'dashboard/routes/dashboard/ramon/helpers/ui';
import { NIVEL_TOM } from 'dashboard/routes/dashboard/ramon/helpers/ferramentas';

const props = defineProps({
  messages: {
    type: Array,
    required: true,
  },
  isLoading: {
    type: Boolean,
    default: false,
  },
});

const messageContainer = ref(null);

const { t } = useI18n();
const { formatMessage } = useMessageFormatter();

const isUserMessage = sender => sender === 'user';

const getMessageAlignment = sender =>
  isUserMessage(sender) ? 'justify-end' : 'justify-start';

const getMessageDirection = sender =>
  isUserMessage(sender) ? 'flex-row-reverse' : 'flex-row';

// Inicial com o tom do kit: o Avatar colore pelo tamanho do nome e "Você" e
// "Assistente" caem no índigo (roxo), fora da paleta da área.
const AVATAR = 'size-6 shrink-0 rounded-full grid place-items-center text-xs';
const avatarInicial = sender =>
  (isUserMessage(sender)
    ? t('CAPTAIN.PLAYGROUND.USER')
    : t('CAPTAIN.PLAYGROUND.ASSISTANT')
  ).charAt(0);
const avatarTom = sender => (isUserMessage(sender) ? TOM.blue : TOM.slate);

const getMessageStyle = sender =>
  isUserMessage(sender)
    ? 'bg-n-blue-9/[0.08] dark:bg-n-blue-9/[0.16] text-n-slate-12 rounded-br-sm rounded-bl-xl rounded-t-xl'
    : 'bg-n-alpha-2 text-n-slate-12 rounded-bl-sm rounded-br-xl rounded-t-xl';

// I-PG2: cor do nível (consulta azul, sugestão âmbar, rascunho verde, interna cinza); erro sempre vermelho.
const tomFerramenta = ferramenta =>
  ferramenta.status === 'erro'
    ? TOM.ruby
    : NIVEL_TOM[ferramenta.nivel] || TOM.slate;
const rotuloFerramenta = ferramenta =>
  ferramenta.status === 'erro'
    ? t('INTEL.TESTAR.FERRAMENTA_ERRO', { nome: ferramenta.title })
    : ferramenta.title;

const scrollToBottom = async () => {
  await nextTick();
  if (messageContainer.value) {
    messageContainer.value.scrollTop = messageContainer.value.scrollHeight;
  }
};

watch(() => props.messages.length, scrollToBottom);
</script>

<template>
  <div
    ref="messageContainer"
    class="flex-1 overflow-y-auto mb-4 px-6 space-y-6"
  >
    <div
      v-for="(message, index) in messages"
      :key="index"
      class="flex"
      :class="getMessageAlignment(message.sender)"
    >
      <div
        class="flex items-end gap-1.5 max-w-[90%] md:max-w-[60%]"
        :class="getMessageDirection(message.sender)"
      >
        <span :class="[AVATAR, avatarTom(message.sender)]">
          {{ avatarInicial(message.sender) }}
        </span>
        <div class="flex flex-col gap-1 min-w-0">
          <div
            class="px-4 py-3 text-sm [overflow-wrap:break-word]"
            :class="getMessageStyle(message.sender)"
          >
            <div v-html="formatMessage(message.content)" />
          </div>
          <div
            v-if="message.ferramentas?.length"
            data-testid="testar-ferramentas"
            class="flex flex-wrap items-center gap-1"
          >
            <span class="text-[11px] text-n-slate-10">
              {{ t('INTEL.TESTAR.FERRAMENTAS') }}
            </span>
            <span
              v-for="(ferramenta, i) in message.ferramentas"
              :key="i"
              data-testid="testar-ferramenta"
              :class="[CHIP, tomFerramenta(ferramenta)]"
            >
              {{ rotuloFerramenta(ferramenta) }}
            </span>
          </div>
        </div>
      </div>
    </div>
    <div v-if="isLoading" class="flex justify-start">
      <div class="flex items-start gap-1.5">
        <span :class="[AVATAR, avatarTom('assistant')]">
          {{ avatarInicial('assistant') }}
        </span>
        <div
          class="max-w-sm rounded-lg p-3 text-sm bg-n-alpha-2 text-n-slate-12"
        >
          <div class="flex gap-1">
            <div class="w-2 h-2 rounded-full bg-n-blue-9 animate-bounce" />
            <div
              class="w-2 h-2 rounded-full bg-n-blue-9 animate-bounce [animation-delay:0.2s]"
            />
            <div
              class="w-2 h-2 rounded-full bg-n-blue-9 animate-bounce [animation-delay:0.4s]"
            />
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
