<script setup>
import { computed, ref } from 'vue';
import ContactPanel from 'dashboard/routes/dashboard/conversation/ContactPanel.vue';
import LeadConversationPanel from 'dashboard/routes/dashboard/ramon/components/conversation/LeadConversationPanel.vue';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useWindowSize } from '@vueuse/core';
import { vOnClickOutside } from '@vueuse/components';
import wootConstants from 'dashboard/constants/globals';

const props = defineProps({
  currentChat: {
    required: true,
    type: Object,
  },
});

// Ramon — fase 1a: conversas descartadas do painel do lead nesta visita
// voltam ao ContactPanel nativo até re-navegação (não persiste entre sessões).
const discardedConversations = ref(new Set());
const showLeadPanel = computed(
  () => !discardedConversations.value.has(props.currentChat.id)
);
const onDiscard = id => {
  discardedConversations.value.add(id);
};

const { uiSettings, updateUISettings } = useUISettings();
const { width: windowWidth } = useWindowSize();

const activeTab = computed(() => {
  const { is_contact_sidebar_open: isContactSidebarOpen } = uiSettings.value;

  if (isContactSidebarOpen) {
    return 0;
  }
  return null;
});

const isSmallScreen = computed(
  () => windowWidth.value < wootConstants.SMALL_SCREEN_BREAKPOINT
);

const closeContactPanel = () => {
  if (isSmallScreen.value && uiSettings.value?.is_contact_sidebar_open) {
    updateUISettings({
      is_contact_sidebar_open: false,
      is_copilot_panel_open: false,
    });
  }
};

const closeSidebar = () => {
  updateUISettings({
    is_contact_sidebar_open: false,
    is_copilot_panel_open: false,
  });
};
</script>

<template>
  <div
    v-on-click-outside="[
      () => closeContactPanel(),
      {
        ignore: [
          'dialog.ProseMirror-prompt-backdrop',
          '[data-popover-content]',
          '[data-popover-backdrop]',
        ],
      },
    ]"
    class="bg-n-surface-2 h-full overflow-hidden flex flex-col fixed top-0 z-40 w-full max-w-sm transition-transform duration-300 ease-in-out ltr:right-0 rtl:left-0 md:static ltr:border-l rtl:border-r border-n-weak shadow-lg md:shadow-none"
    :class="[
      {
        'md:flex': activeTab === 0,
        'md:hidden': activeTab !== 0,
      },
      showLeadPanel
        ? 'md:w-[420px] md:min-w-[420px] 2xl:min-w-[480px] 2xl:w-[480px]'
        : 'md:w-[320px] md:min-w-[320px] 2xl:min-w-[360px] 2xl:w-[360px]',
    ]"
  >
    <div class="flex flex-1 overflow-auto">
      <LeadConversationPanel
        v-if="showLeadPanel"
        v-show="activeTab === 0"
        :key="currentChat.id"
        :conversation-id="currentChat.id"
        @discarded="onDiscard(currentChat.id)"
        @close="closeSidebar"
      />
      <ContactPanel
        v-else
        v-show="activeTab === 0"
        :conversation-id="currentChat.id"
        :inbox-id="currentChat.inbox_id"
      />
    </div>
  </div>
</template>
