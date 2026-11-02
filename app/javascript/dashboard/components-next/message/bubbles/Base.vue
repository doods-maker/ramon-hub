<script setup>
import { computed } from 'vue';

import MessageMeta from '../MessageMeta.vue';

import { emitter } from 'shared/helpers/mitt';
import { useMessageContext } from '../provider.js';
import { useI18n } from 'vue-i18n';

import MessageFormatter from 'shared/helpers/MessageFormatter.js';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { MESSAGE_VARIANTS, ORIENTATION } from '../constants';
import {
  autorCitacao,
  textoCitacao,
} from 'dashboard/routes/dashboard/ramon/helpers/equipe';

const props = defineProps({
  hideMeta: { type: Boolean, default: false },
});

const {
  variant,
  orientation,
  inReplyTo,
  shouldGroupWithNext,
  isEquipe,
  mostrarAutor,
  marcadoEquipe,
  primeiroDoAutor,
  sender,
  currentUserId,
  content: textoDaMensagem,
  attachments: anexosDaMensagem,
} = useMessageContext();
const { t } = useI18n();

// Hub: o que o escritório envia (agente, automação, modelo) fica no verde do
// WhatsApp; nota privada em âmbar translúcido com rótulo (05/10/2026).
const ENVIADA = 'bg-[rgb(var(--ramon-enviada))] text-n-slate-12';

// FORK(ramon): Equipe: @ em azul; marcação minha com fundo azul translúcido e fileta
// (.marcado do mockup). O áudio não tem padding próprio para o nome e a hora.
// ponytail: o destaque vale para todo @ da bolha que me marca; por pessoa exige casar o rótulo.
const EQUIPE_BOLHA =
  '[&_.prosemirror-mention-node]:font-semibold [&_.prosemirror-mention-node]:text-n-blue-11 data-[bubble-name=audio]:px-2.5 data-[bubble-name=audio]:pt-1.5 data-[bubble-name=audio]:pb-[5px]';
const EQUIPE_MARCADO =
  'shadow-[inset_3px_0_0_rgb(var(--blue-11))] [&_.prosemirror-mention-node]:bg-n-blue-9/[.18] [&_.prosemirror-mention-node]:rounded [&_.prosemirror-mention-node]:px-[3px]';
// FORK(ramon): hora na última linha do texto (.rodape do mockup). O float não sobe de
// dentro do <p>; então a hora é absoluta e um espaço invisível no fim do texto reserva
// o lugar dela. Sem espaço na linha, ele quebra e abre uma linha para a hora.
const EQUIPE_HORA_NA_LINHA =
  "relative [&_.prose>:last-child]:after:inline-block [&_.prose>:last-child]:after:w-[3.75rem] [&_.prose>:last-child]:after:content-['']";

const varaintBaseMap = {
  [MESSAGE_VARIANTS.AGENT]: ENVIADA,
  [MESSAGE_VARIANTS.PRIVATE]:
    'bg-n-amber-9/15 text-n-slate-12 [&_.prosemirror-mention-node]:font-semibold',
  [MESSAGE_VARIANTS.USER]: 'bg-n-slate-4 text-n-slate-12',
  [MESSAGE_VARIANTS.ACTIVITY]: 'bg-n-alpha-1 text-n-slate-11 text-sm',
  [MESSAGE_VARIANTS.BOT]: ENVIADA,
  [MESSAGE_VARIANTS.TEMPLATE]: ENVIADA,
  [MESSAGE_VARIANTS.ERROR]: 'bg-n-ruby-4 text-n-ruby-12',
  [MESSAGE_VARIANTS.EMAIL]: 'w-full',
  [MESSAGE_VARIANTS.UNSUPPORTED]:
    'bg-n-amber-9/10 border border-dashed border-n-amber-9 text-n-slate-12',
};

const orientationMap = {
  [ORIENTATION.LEFT]:
    'left-bubble rounded-xl ltr:rounded-bl-sm rtl:rounded-br-sm',
  [ORIENTATION.RIGHT]:
    'right-bubble rounded-xl ltr:rounded-br-sm rtl:rounded-bl-sm',
  [ORIENTATION.CENTER]: 'rounded-md',
};

const flexOrientationClass = computed(() => {
  const map = {
    [ORIENTATION.LEFT]: 'justify-start',
    [ORIENTATION.RIGHT]: 'justify-end',
    [ORIENTATION.CENTER]: 'justify-center',
  };

  return map[orientation.value];
});

// FORK(ramon): só em texto puro; anexo vem depois do texto, e a hora iria por cima dele.
const horaNaLinha = computed(
  () =>
    isEquipe.value && !!textoDaMensagem.value && !anexosDaMensagem.value?.length
);

const messageClass = computed(() => {
  const classToApply = [varaintBaseMap[variant.value]];

  if (variant.value !== MESSAGE_VARIANTS.ACTIVITY) {
    classToApply.push(orientationMap[orientation.value]);
  } else {
    classToApply.push('rounded-lg');
  }

  if (isEquipe.value) classToApply.push(EQUIPE_BOLHA);
  if (marcadoEquipe.value) classToApply.push(EQUIPE_MARCADO);
  if (horaNaLinha.value) classToApply.push(EQUIPE_HORA_NA_LINHA);

  return classToApply;
});

const scrollToMessage = () => {
  emitter.emit(BUS_EVENTS.SCROLL_TO_MESSAGE, {
    messageId: inReplyTo.value.id,
  });
};

const shouldShowMeta = computed(
  () =>
    !props.hideMeta &&
    // FORK(ramon): na Equipe toda bolha mostra a hora, mesmo agrupada
    (!shouldGroupWithNext.value || isEquipe.value) &&
    variant.value !== MESSAGE_VARIANTS.ACTIVITY
);

const replyToPreview = computed(() => {
  if (!inReplyTo) return '';
  // FORK(ramon): texto puro, renderizado sem .prose (a reserva da hora é só do conteúdo da mensagem)
  if (isEquipe.value) return textoCitacao(inReplyTo.value, t);

  const { content, attachments } = inReplyTo.value;

  if (content) return new MessageFormatter(content).formattedMessage;
  if (attachments?.length) {
    const firstAttachment = attachments[0];
    const fileType = firstAttachment.fileType ?? firstAttachment.file_type;

    return t(`CHAT_LIST.ATTACHMENTS.${fileType}.CONTENT`);
  }

  return t('CONVERSATION.REPLY_MESSAGE_NOT_FOUND');
});

const autorDaCitacao = computed(() =>
  autorCitacao(inReplyTo.value, currentUserId.value, t)
);
</script>

<template>
  <div
    class="text-sm min-w-0"
    :class="[
      messageClass,
      {
        'max-w-lg': variant !== MESSAGE_VARIANTS.EMAIL,
      },
    ]"
  >
    <!-- FORK(ramon): nome do autor na primeira do bloco; usuário apagado não tem nome -->
    <p
      v-if="mostrarAutor && primeiroDoAutor && sender?.name"
      class="mb-px text-xs font-semibold text-n-blue-11"
      data-testid="equipe-autor"
    >
      {{ sender?.name }}
    </p>
    <!-- FORK(ramon): .cita do mockup. Autor e fileta azul; usuário apagado não tem nome -->
    <div
      v-if="inReplyTo && isEquipe"
      class="px-2 py-1 mb-1 text-xs rounded-md cursor-pointer bg-n-slate-9/[.12] shadow-[inset_3px_0_0_rgb(var(--blue-11))]"
      data-testid="equipe-cita"
      @click="scrollToMessage"
    >
      <span v-if="autorDaCitacao" class="block font-semibold text-n-blue-11">
        {{ autorDaCitacao }}
      </span>
      <span class="line-clamp-2 text-n-slate-11">{{ replyToPreview }}</span>
    </div>
    <div
      v-else-if="inReplyTo"
      class="p-2 -mx-1 mb-2 rounded-lg cursor-pointer bg-n-alpha-black1"
      @click="scrollToMessage"
    >
      <div
        v-dompurify-html="replyToPreview"
        class="prose prose-bubble line-clamp-2"
      />
    </div>
    <p
      v-if="variant === MESSAGE_VARIANTS.PRIVATE"
      class="mb-1 text-[11px] font-semibold text-n-amber-11"
      data-testid="nota-privada-rotulo"
    >
      {{ t('RAMON.NOTA_PRIVADA_ROTULO') }}
    </p>
    <slot />
    <!-- FORK(ramon): na Equipe a hora fica na linha do texto ou abaixo, à direita -->
    <MessageMeta
      v-if="shouldShowMeta"
      :class="[
        horaNaLinha ? 'absolute bottom-1 ltr:right-2.5 rtl:left-2.5' : '',
        isEquipe && !horaNaLinha ? 'justify-end mt-0.5' : '',
        !isEquipe ? [flexOrientationClass, 'mt-2'] : '',
        variant === MESSAGE_VARIANTS.EMAIL ? 'px-3 pb-3' : '',
      ]"
      class="text-n-slate-11"
    />
  </div>
</template>
