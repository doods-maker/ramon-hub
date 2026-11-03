<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { format, fromUnixTime } from 'date-fns';
import { messageTimestamp } from 'shared/helpers/timeHelper';

import MessageStatus from './MessageStatus.vue';
import Icon from 'next/icon/Icon.vue';
import { useInbox } from 'dashboard/composables/useInbox';
import { useMessageContext } from './provider.js';
import { useEquipeStore } from 'dashboard/stores/equipe';
import { estadoVisto } from 'dashboard/routes/dashboard/ramon/helpers/equipe';

import { MESSAGE_STATUS, MESSAGE_TYPES, ORIENTATION } from './constants';

const {
  isAFacebookInbox,
  isALineChannel,
  isAPIInbox,
  isASmsInbox,
  isATelegramChannel,
  isATwilioChannel,
  isAWebWidgetInbox,
  isAWhatsAppChannel,
  isAnEmailChannel,
  isAnInstagramChannel,
  isATiktokChannel,
} = useInbox();

const {
  status,
  isPrivate,
  createdAt,
  sourceId,
  messageType,
  contentAttributes,
  isEquipe,
  equipeTipo,
  participaEquipe,
  orientation,
  conversationId,
  currentUserId,
} = useMessageContext();

const { t } = useI18n();

// FORK(ramon): Equipe = só a hora. Direto no date-fns: messageTimestamp troca o
// formato em mensagem de outro ano.
const readableTime = computed(() =>
  isEquipe.value
    ? format(fromUnixTime(createdAt.value), 'HH:mm')
    : messageTimestamp(createdAt.value, 'LLL d, h:mm a')
);

const showStatusIndicator = computed(() => {
  if (isPrivate.value) return false;
  // FORK(ramon): na Equipe tudo é outgoing; status só nas minhas mensagens
  if (isEquipe.value && orientation.value === ORIENTATION.LEFT) return false;
  // FORK(ramon): admin de fora não vê ✓, nem na mensagem de quando participava
  if (isEquipe.value && participaEquipe.value === false) return false;
  // Don't show status for failed messages, we already show error message
  if (status.value === MESSAGE_STATUS.FAILED) return false;
  // Don't show status for deleted messages
  if (contentAttributes.value?.deleted) return false;

  if (messageType.value === MESSAGE_TYPES.OUTGOING) return true;
  if (messageType.value === MESSAGE_TYPES.TEMPLATE) return true;

  return false;
});

const isSent = computed(() => {
  if (!showStatusIndicator.value) return false;

  // Messages will be marked as sent for the Email channel if they have a source ID.
  if (isAnEmailChannel.value) return !!sourceId.value;

  if (
    isAWhatsAppChannel.value ||
    isATwilioChannel.value ||
    isAFacebookInbox.value ||
    isASmsInbox.value ||
    isATelegramChannel.value ||
    isAnInstagramChannel.value ||
    isATiktokChannel.value
  ) {
    return sourceId.value && status.value === MESSAGE_STATUS.SENT;
  }

  // API inbox messages use real sent/delivered/read status values from the external system.
  if (isAPIInbox.value) return status.value === MESSAGE_STATUS.SENT;

  // All messages will be mark as sent for the Line channel, as there is no source ID.
  if (isALineChannel.value) return true;

  return false;
});

const isDelivered = computed(() => {
  if (!showStatusIndicator.value) return false;

  if (
    isAWhatsAppChannel.value ||
    isATwilioChannel.value ||
    isASmsInbox.value ||
    isAFacebookInbox.value ||
    isAnInstagramChannel.value ||
    isATiktokChannel.value
  ) {
    return sourceId.value && status.value === MESSAGE_STATUS.DELIVERED;
  }
  // API inbox messages use real delivered status from the external system.
  if (isAPIInbox.value) return status.value === MESSAGE_STATUS.DELIVERED;
  // All messages marked as delivered for the web widget inbox once they are sent.
  if (isAWebWidgetInbox.value) {
    return status.value === MESSAGE_STATUS.SENT;
  }
  if (isALineChannel.value) {
    return status.value === MESSAGE_STATUS.DELIVERED;
  }

  return false;
});

const isRead = computed(() => {
  if (!showStatusIndicator.value) return false;

  if (
    isAWhatsAppChannel.value ||
    isATwilioChannel.value ||
    isAFacebookInbox.value ||
    isAnInstagramChannel.value ||
    isATiktokChannel.value
  ) {
    return sourceId.value && status.value === MESSAGE_STATUS.READ;
  }

  if (isAWebWidgetInbox.value || isAPIInbox.value) {
    return status.value === MESSAGE_STATUS.READ;
  }

  return false;
});

// FORK(ramon): vistos por pessoa. Sem lista carregada (ou sozinho no chat), um ✓ cinza.
const vistoEquipe = computed(() => {
  if (!isEquipe.value) return null;
  const visto = estadoVisto(
    { createdAt: createdAt.value, senderId: currentUserId.value },
    useEquipeStore().participantes[conversationId.value]
  );
  if (!visto.total) return { status: MESSAGE_STATUS.SENT, titulo: '' };

  const umAum = equipeTipo.value === '1a1';
  if (visto.todosLeram) {
    return {
      status: MESSAGE_STATUS.READ,
      titulo: umAum ? t('RAMON.EQUIPE.VISTO') : t('RAMON.EQUIPE.VISTO_TODOS'),
    };
  }
  return {
    status: MESSAGE_STATUS.DELIVERED,
    titulo: umAum
      ? ''
      : t('RAMON.EQUIPE.VISTO_POR', {
          leram: visto.leram.length,
          total: visto.total,
          faltam: visto.faltam.join(', '),
        }),
  };
});

const statusToShow = computed(() => {
  // FORK(ramon): o status do canal na Equipe é sempre "sent"; só a pendência vale.
  if (isEquipe.value) {
    return status.value === MESSAGE_STATUS.PROGRESS
      ? MESSAGE_STATUS.PROGRESS
      : vistoEquipe.value.status;
  }
  if (isRead.value) return MESSAGE_STATUS.READ;
  if (isDelivered.value) return MESSAGE_STATUS.DELIVERED;
  if (isSent.value) return MESSAGE_STATUS.SENT;

  return MESSAGE_STATUS.PROGRESS;
});
</script>

<template>
  <div
    class="flex items-center gap-1.5"
    :class="isEquipe ? 'text-[10px] font-mono' : 'text-xs'"
  >
    <!-- FORK(ramon): na Equipe, hora pequena e mono (.rodape do mockup) -->
    <div class="inline">
      <time class="inline">{{ readableTime }}</time>
    </div>
    <Icon v-if="isPrivate" icon="i-lucide-lock-keyhole" class="size-3" />
    <MessageStatus
      v-if="showStatusIndicator"
      :status="statusToShow"
      :equipe="isEquipe"
      :titulo="vistoEquipe?.titulo"
    />
  </div>
</template>
`
