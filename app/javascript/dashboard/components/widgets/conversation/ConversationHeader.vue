<script setup>
// FORK(ramon): cabeçalho enxuto do redesign v2 (mockup .chat-topo) — só nome,
// Copiloto, painel e Resolver. Saíram avatar, #id/caixa, SLA nativo e ligação.
import { computed } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import BackButton from '../BackButton.vue';
import MoreActions from './MoreActions.vue';
import LeadPanelToggle from 'dashboard/routes/dashboard/ramon/components/conversation/LeadPanelToggle.vue';
import CopilotoModoSelector from 'dashboard/routes/dashboard/ramon/components/conversation/CopilotoModoSelector.vue';
import wootConstants from 'dashboard/constants/globals';
import { conversationListPageURL } from 'dashboard/helper/URLHelper';
import { snoozedReopenTime } from 'dashboard/helper/snoozeHelpers';
import { useInbox } from 'dashboard/composables/useInbox';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  chat: {
    type: Object,
    default: () => ({}),
  },
  showBackButton: {
    type: Boolean,
    default: false,
  },
});

const { t } = useI18n();
const store = useStore();
const route = useRoute();
const { isAWebWidgetInbox } = useInbox();

const currentChat = computed(() => store.getters.getSelectedChat);
const accountId = computed(() => store.getters.getCurrentAccountId);

const chatMetadata = computed(() => props.chat.meta);

const backButtonUrl = computed(() => {
  const {
    params: { inbox_id: inboxId, label, teamId, id: customViewId },
    name,
  } = route;

  const conversationTypeMap = {
    conversation_through_mentions: 'mention',
    conversation_through_participating: 'participating',
    conversation_through_unattended: 'unattended',
  };
  return conversationListPageURL({
    accountId: accountId.value,
    inboxId,
    label,
    teamId,
    conversationType: conversationTypeMap[name],
    customViewId,
  });
});

const isHMACVerified = computed(() => {
  if (!isAWebWidgetInbox.value) {
    return true;
  }
  return chatMetadata.value.hmac_verified;
});

const currentContact = computed(() =>
  store.getters['contacts/getContact'](props.chat.meta.sender.id)
);

const isSnoozed = computed(
  () => currentChat.value.status === wootConstants.STATUS_TYPE.SNOOZED
);

const snoozedDisplayText = computed(() => {
  const { snoozed_until: snoozedUntil } = currentChat.value;
  if (snoozedUntil) {
    return `${t('CONVERSATION.HEADER.SNOOZED_UNTIL')} ${snoozedReopenTime(snoozedUntil)}`;
  }
  return t('CONVERSATION.HEADER.SNOOZED_UNTIL_NEXT_REPLY');
});
</script>

<template>
  <div
    class="flex h-14 w-full min-w-0 flex-shrink-0 items-center gap-3 whitespace-nowrap px-5"
  >
    <BackButton v-if="showBackButton" :back-url="backButtonUrl" />
    <span class="min-w-0 truncate text-[14.5px] font-semibold text-n-slate-12">
      {{ currentContact.name }}
    </span>
    <fluent-icon
      v-if="!isHMACVerified"
      v-tooltip="$t('CONVERSATION.UNVERIFIED_SESSION')"
      size="14"
      class="text-n-amber-10 my-0 mx-0 min-w-[14px] flex-shrink-0"
      icon="warning"
    />
    <span v-if="isSnoozed" class="truncate text-xs font-medium text-n-amber-11">
      {{ snoozedDisplayText }}
    </span>
    <div class="ml-auto flex flex-shrink-0 items-center gap-2">
      <CopilotoModoSelector v-if="currentChat.id" />
      <LeadPanelToggle />
      <MoreActions :conversation-id="currentChat.id" />
    </div>
  </div>
</template>
