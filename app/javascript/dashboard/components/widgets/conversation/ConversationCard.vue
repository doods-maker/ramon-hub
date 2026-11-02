<script setup>
import { computed, ref, watch } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { getLastMessage } from 'dashboard/helper/conversationHelper';
import Avatar from 'next/avatar/Avatar.vue';
import MessagePreview from './MessagePreview.vue';
import InboxName from '../InboxName.vue';
import TimeAgo from 'dashboard/components/ui/TimeAgo.vue';
import CardLabels from './conversationCardComponents/CardLabels.vue';
import CardPriorityIcon from 'dashboard/components-next/Conversation/ConversationCard/CardPriorityIcon.vue';
import UnreadBadge from 'dashboard/components-next/Conversation/ConversationCard/UnreadBadge.vue';
import SLACardLabel from './components/SLACardLabel.vue';
import VoiceCallStatus from './VoiceCallStatus.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import LeadLinhaCard from 'dashboard/routes/dashboard/ramon/components/conversation/LeadLinhaCard.vue';
import { semEtiquetasDoLead } from 'dashboard/routes/dashboard/ramon/helpers/leadNaConversa';
import {
  horaLista,
  identidadeConversa,
} from 'dashboard/routes/dashboard/ramon/helpers/equipe';

const props = defineProps({
  chat: { type: Object, required: true },
  currentContact: { type: Object, required: true },
  assignee: { type: Object, default: () => ({}) },
  inbox: { type: Object, default: () => ({}) },
  selected: { type: Boolean, default: false },
  isActiveChat: { type: Boolean, default: false },
  showAssignee: { type: Boolean, default: false },
  showInboxName: { type: Boolean, default: false },
  hideThumbnail: { type: Boolean, default: false },
  compact: { type: Boolean, default: false },
});

const emit = defineEmits([
  'click',
  'contextmenu',
  'selectConversation',
  'deSelectConversation',
]);

const hovered = ref(false);

// FORK(ramon): caixa Equipe. Linha de WhatsApp: foto, nome, hora, prévia e selos.
const equipe = computed(() => !!props.inbox?.equipe);
const meuId = useMapGetter('getCurrentUserID');
const identidade = computed(() =>
  equipe.value ? identidadeConversa(props.chat, meuId.value) : null
);
const nomeCard = computed(
  () => identidade.value?.nome ?? props.currentContact.name
);
const fotoCard = computed(() =>
  identidade.value ? identidade.value.foto : props.currentContact.thumbnail
);
const marcado = computed(() => equipe.value && !!props.chat.equipe_marcado);
const previaEquipe = computed(() =>
  equipe.value ? { meuId: meuId.value, tipo: props.chat.equipe_tipo } : null
);
// ponytail: "agora" só recalcula quando a conversa muda; lista aberta na virada do
// dia mantém a hora até a próxima atividade ou recarga. Timer aqui, se incomodar.
const horaEquipe = computed(() =>
  equipe.value ? horaLista(props.chat.timestamp, Date.now()) : ''
);
const avatarClass = computed(() => {
  if (equipe.value) return 'mt-3';
  return props.showInboxName ? 'mt-8' : 'mt-4';
});

const unreadCount = computed(() => props.chat.unread_count);
const hasUnread = computed(() => unreadCount.value > 0);
const lastMessageInChat = computed(() => getLastMessage(props.chat));

const voiceCallData = computed(() => {
  const last = lastMessageInChat.value;
  if (last?.content_type !== 'voice_call' || !last.call) {
    return { status: null, direction: null };
  }
  return {
    status: last.call.status,
    direction: last.call.direction === 'outgoing' ? 'outbound' : 'inbound',
  };
});

const showMetaSection = computed(() => {
  return (
    !equipe.value &&
    (props.showInboxName ||
      (props.showAssignee && props.assignee.name) ||
      props.chat.priority)
  );
});

const hasSlaPolicyId = computed(() => props.chat?.sla_policy_id);

// FORK(ramon): fase-*/tese-* saem do card quando a linha do lead aparece.
const cardLabels = computed(() =>
  semEtiquetasDoLead(props.chat.labels, props.chat.ramon_lead)
);

const showLabelsSection = computed(() => {
  return !equipe.value && (cardLabels.value.length > 0 || hasSlaPolicyId.value);
});

const messagePreviewClass = computed(() => {
  return [
    hasUnread.value ? 'font-medium text-n-slate-12' : 'text-n-slate-11',
    marcado.value ? 'ltr:pr-10 rtl:pl-10' : '',
    !marcado.value && !props.compact && hasUnread.value
      ? 'ltr:pr-4 rtl:pl-4'
      : '',
    !marcado.value && props.compact && hasUnread.value
      ? 'ltr:pr-6 rtl:pl-6'
      : '',
  ];
});

const onThumbnailHover = () => {
  hovered.value = !props.hideThumbnail;
};

const onThumbnailLeave = () => {
  hovered.value = false;
};

const onSelectConversation = checked => {
  if (checked) {
    emit('selectConversation', props.chat.id, props.inbox.id);
  } else {
    emit('deSelectConversation', props.chat.id, props.inbox.id);
  }
};

const selectedModel = computed({
  get: () => props.selected,
  set: value => onSelectConversation(value),
});

watch(
  () => props.chat.id,
  () => {
    hovered.value = false;
  }
);
</script>

<template>
  <div
    class="relative flex items-start flex-grow-0 flex-shrink-0 w-auto max-w-full py-0 cursor-pointer conversation border-b border-n-weak hover:border-n-surface-1 hover:bg-n-alpha-1 dark:hover:bg-n-alpha-3 group hover:z-[1] before:content-[none] before:absolute before:-top-px before:inset-x-0 before:h-px before:bg-n-surface-1 before:pointer-events-none hover:before:content-['']"
    :class="{
      'active animate-card-select bg-n-alpha-2 shadow-[inset_2px_0_0_rgb(var(--blue-9))] !border-n-surface-1':
        isActiveChat,
      'selected bg-n-slate-2 !border-n-surface-1': selected,
      'px-0': compact,
      'px-3': !compact,
    }"
    @click="$emit('click', $event)"
    @contextmenu="$emit('contextmenu', $event)"
  >
    <div
      class="relative"
      @mouseenter="onThumbnailHover"
      @mouseleave="onThumbnailLeave"
    >
      <Avatar
        v-if="!hideThumbnail"
        :name="nomeCard"
        :src="fotoCard"
        :size="equipe ? 40 : 32"
        :rounded-full="equipe"
        :status="currentContact.availability_status"
        :class="avatarClass"
        hide-offline-status
      >
        <template #overlay="{ size }">
          <label
            v-if="!equipe && (hovered || selected)"
            class="flex items-center justify-center rounded-full cursor-pointer absolute inset-0 z-10 backdrop-blur-[2px]"
            :style="{ width: `${size}px`, height: `${size}px` }"
            @click.stop
          >
            <Checkbox v-model="selectedModel" />
          </label>
        </template>
      </Avatar>
    </div>
    <div class="px-0 py-3 flex-1 min-w-0 border-line">
      <div
        v-if="showMetaSection"
        class="flex items-center min-w-0 gap-1"
        :class="{
          'ltr:ml-2 rtl:mr-2': !compact,
          'mx-2': compact,
        }"
      >
        <InboxName v-if="showInboxName" :inbox="inbox" class="flex-1 min-w-0" />
        <div
          class="flex items-baseline gap-2 flex-shrink-0"
          :class="{
            'flex-1 justify-between': !showInboxName,
          }"
        >
          <span
            v-if="showAssignee && assignee.name"
            class="text-n-slate-11 text-xs font-medium leading-3 py-0.5 px-0 inline-flex items-center truncate"
          >
            <fluent-icon icon="person" size="12" class="text-n-slate-11" />
            {{ assignee.name }}
          </span>
          <CardPriorityIcon
            :priority="chat.priority"
            class="flex-shrink-0 !size-3.5"
          />
        </div>
      </div>
      <h4
        class="conversation--user text-sm my-0 mx-2 capitalize pt-0.5 text-ellipsis overflow-hidden whitespace-nowrap flex-1 min-w-0 ltr:pr-16 rtl:pl-16 text-n-slate-12"
        :class="[
          hasUnread ? 'font-semibold' : 'font-medium',
          { '!normal-case': equipe },
        ]"
      >
        {{ nomeCard }}
      </h4>
      <LeadLinhaCard
        v-if="!equipe"
        :lead="chat.ramon_lead"
        class="mx-2 ltr:pr-6 rtl:pl-6"
      />
      <VoiceCallStatus
        v-if="voiceCallData.status"
        key="voice-status-row"
        :status="voiceCallData.status"
        :direction="voiceCallData.direction"
        :message-preview-class="messagePreviewClass"
      />
      <MessagePreview
        v-else-if="lastMessageInChat"
        key="message-preview"
        :message="lastMessageInChat"
        :equipe="previaEquipe"
        class="my-0 mx-2 leading-6 h-6 flex-1 min-w-0 text-sm"
        :class="messagePreviewClass"
      />
      <p
        v-else
        key="no-messages"
        class="text-n-slate-11 text-sm my-0 mx-2 leading-6 h-6 flex-1 min-w-0 overflow-hidden text-ellipsis whitespace-nowrap"
        :class="messagePreviewClass"
      >
        <fluent-icon
          size="16"
          class="-mt-0.5 align-middle inline-block text-n-slate-10"
          icon="info"
        />
        <span class="mx-0.5">
          {{ $t(`CHAT_LIST.NO_MESSAGES`) }}
        </span>
      </p>
      <div
        class="absolute flex flex-col ltr:right-3 rtl:left-3"
        :class="showMetaSection ? 'top-8' : 'top-4'"
      >
        <span class="ml-auto font-mono font-normal leading-4 text-xxs">
          <span
            v-if="equipe"
            data-equipe-hora
            :class="
              hasUnread
                ? 'text-[rgb(var(--ramon-nao-lida-texto))]'
                : 'text-n-slate-10'
            "
          >
            {{ horaEquipe === 'ONTEM' ? $t('RAMON.EQUIPE.ONTEM') : horaEquipe }}
          </span>
          <TimeAgo
            v-else
            :last-activity-timestamp="chat.timestamp"
            :created-at-timestamp="chat.created_at"
            :conversation-id="chat.id"
          />
        </span>
        <div
          v-if="marcado"
          class="flex items-center gap-1 ltr:ml-auto rtl:mr-auto mt-1"
        >
          <span
            data-equipe-selo
            class="bg-n-blue-9/[.18] rounded-full h-4 min-w-4 px-1 font-semibold text-xxs leading-3 text-n-blue-11 inline-grid place-items-center flex-shrink-0"
          >
            {{ $t('RAMON.EQUIPE.SELO_MARCACAO') }}
          </span>
          <UnreadBadge v-if="hasUnread" :count="unreadCount" />
        </div>
        <UnreadBadge
          v-else-if="hasUnread"
          :count="unreadCount"
          class="ltr:ml-auto rtl:mr-auto mt-1"
        />
      </div>
      <CardLabels
        v-if="showLabelsSection"
        :conversation-labels="cardLabels"
        class="mt-0.5 mx-2 mb-0"
      >
        <template v-if="hasSlaPolicyId" #before>
          <SLACardLabel :chat="chat" class="ltr:mr-1 rtl:ml-1" />
        </template>
      </CardLabels>
    </div>
  </div>
</template>
