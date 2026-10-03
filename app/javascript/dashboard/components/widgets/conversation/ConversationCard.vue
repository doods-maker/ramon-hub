<script setup>
// FORK(ramon): card do redesign v2 (mockup .conv) — sem avatar (bolinha azul de
// não lida + checkbox no hover no lugar), etiqueta da etapa + tese e o selo do
// prazo de 1ª resposta no lugar da hora/SLA nativo.
import { computed, ref, watch } from 'vue';
import { getLastMessage } from 'dashboard/helper/conversationHelper';
import { useMapGetter } from 'dashboard/composables/store';
import MessagePreview from './MessagePreview.vue';
import InboxName from '../InboxName.vue';
import TimeAgo from 'dashboard/components/ui/TimeAgo.vue';
import CardLabels from './conversationCardComponents/CardLabels.vue';
import CardPriorityIcon from 'dashboard/components-next/Conversation/ConversationCard/CardPriorityIcon.vue';
import VoiceCallStatus from './VoiceCallStatus.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import SeloPrazo from 'dashboard/routes/dashboard/ramon/components/hoje/SeloPrazo.vue';
import { prazoDaConversa } from 'dashboard/routes/dashboard/ramon/helpers/prazoConversa';
import {
  DEFAULT_STAGE_COLOR,
  semEtiquetaDeFase,
} from 'dashboard/routes/dashboard/ramon/helpers/stage';

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
  return props.showInboxName || (props.showAssignee && props.assignee.name);
});

const visibleLabels = computed(() => semEtiquetaDeFase(props.chat.labels));
// Lead da store (websocket de leads: a etapa muda ao vivo) com o bloco slim da
// conversa como reserva. A store casa pelo id da conversa — se o slim já diz
// qual é o lead e a store achou outro, fica o slim.
const leadDaConversa = useMapGetter('leads/getLeadByConversationId');
const lead = computed(() => {
  const slim = props.chat.ramon_lead;
  const daStore = leadDaConversa.value?.(props.chat.id);
  if (daStore && (!slim || slim.id === daStore.id)) return daStore;
  return slim;
});
const prazo = computed(() => prazoDaConversa(props.chat, props.inbox));

const messagePreviewClass = computed(() =>
  hasUnread.value ? 'text-n-slate-12' : 'text-n-slate-11'
);

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
    class="conversation relative max-w-full cursor-pointer border-b border-n-weak py-3 group"
    :class="{
      // compacto (barra do contato) só aperta quando não há checkbox na borda
      'px-2': compact && hideThumbnail,
      'px-4': !compact || !hideThumbnail,
      'active bg-n-slate-4 shadow-[inset_2px_0_0_rgb(var(--blue-9))]':
        isActiveChat,
      'selected bg-n-slate-3': selected && !isActiveChat,
      'hover:bg-n-slate-3': !isActiveChat,
    }"
    @click="$emit('click', $event)"
    @contextmenu="$emit('contextmenu', $event)"
    @mouseenter="onThumbnailHover"
    @mouseleave="onThumbnailLeave"
  >
    <label
      v-if="hovered || selected"
      class="absolute left-0 top-[11px] z-10 flex cursor-pointer"
      @click.stop
    >
      <Checkbox v-model="selectedModel" />
    </label>
    <span
      v-else-if="hasUnread"
      class="absolute left-[5px] top-[18px] size-1.5 rounded-full bg-n-blue-9"
    />
    <div class="flex min-w-0 items-center gap-2">
      <h4
        class="conversation--user my-0 min-w-0 truncate text-[13.5px] font-medium capitalize text-n-slate-12"
      >
        {{ currentContact.name }}
      </h4>
      <div class="ml-auto flex flex-shrink-0 items-center gap-1.5">
        <CardPriorityIcon :priority="chat.priority" class="!size-3.5" />
        <SeloPrazo v-if="prazo" :prazo-em="prazo" />
        <span v-else class="font-mono text-[11.5px] text-n-slate-9">
          <TimeAgo
            :last-activity-timestamp="chat.timestamp"
            :created-at-timestamp="chat.created_at"
            :conversation-id="chat.id"
          />
        </span>
      </div>
    </div>
    <div
      v-if="lead"
      class="mb-0.5 mt-[3px] flex min-w-0 items-center gap-2 text-xs text-n-slate-9"
    >
      <span
        class="ramon-stage-pill inline-flex items-center gap-1.5 whitespace-nowrap rounded-full px-[9px] py-1 text-[11.5px] font-medium leading-none"
        :style="{ '--stage': lead.stage_color || DEFAULT_STAGE_COLOR }"
      >
        <span class="size-1.5 rounded-full bg-current" />
        {{ lead.stage_name }}
      </span>
      <span v-if="lead.thesis_name" class="truncate">
        {{ lead.thesis_name }}
      </span>
    </div>
    <div
      v-if="showMetaSection"
      class="mt-0.5 flex min-w-0 items-center gap-2 text-xs text-n-slate-9"
    >
      <InboxName v-if="showInboxName" :inbox="inbox" class="min-w-0" />
      <span
        v-if="showAssignee && assignee.name"
        class="inline-flex min-w-0 items-center gap-1 truncate"
      >
        <span class="i-lucide-user size-3 flex-shrink-0" />
        {{ assignee.name }}
      </span>
    </div>
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
      class="my-0 min-w-0 text-[13px] leading-5"
      :class="messagePreviewClass"
    />
    <p
      v-else
      key="no-messages"
      class="my-0 min-w-0 truncate text-[13px] leading-5"
      :class="messagePreviewClass"
    >
      {{ $t(`CHAT_LIST.NO_MESSAGES`) }}
    </p>
    <CardLabels
      v-if="visibleLabels.length"
      :conversation-labels="visibleLabels"
      class="mt-1"
    />
  </div>
</template>
