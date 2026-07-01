<script setup>
import { computed, watch } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import ConversationBox from 'dashboard/components/widgets/conversation/ConversationBox.vue';

defineOptions({ name: 'ConversationDock' });

const store = useStore();
const dockId = useMapGetter('leads/getDockConversationId');
const selectedLead = useMapGetter('leads/getSelectedLead');

const chat = computed(() =>
  store.getters['conversations/getConversationById'](dockId.value)
);
const isOpen = computed(() => !!dockId.value);
const drawerOpen = computed(() => !!selectedLead.value);
const contactName = computed(() => chat.value?.meta?.sender?.name || '');

const activate = async id => {
  if (!id) return;
  if (!store.getters['conversations/getConversationById'](id)) {
    await store.dispatch('conversations/getConversation', id);
  }
  const conversation = store.getters['conversations/getConversationById'](id);
  if (conversation) {
    store.dispatch('conversations/setActiveChat', { data: conversation });
  }
};
watch(dockId, activate, { immediate: true });

const close = () => store.dispatch('leads/closeDock');
</script>

<template>
  <div
    v-if="isOpen"
    data-testid="conversation-dock"
    class="fixed z-50 inset-0 flex flex-col overflow-hidden bg-n-solid-1 border-n-weak shadow-lg md:inset-auto md:bottom-4 md:h-[560px] md:w-[440px] md:rounded-lg md:border"
    :class="drawerOpen ? 'md:right-[25rem]' : 'md:right-4'"
  >
    <header class="flex items-center gap-2 px-3 py-2 border-b border-n-weak">
      <span class="flex-1 text-sm font-medium text-n-slate-12 truncate">{{
        contactName
      }}</span>
      <button
        data-testid="dock-close"
        class="text-n-slate-10 hover:text-n-slate-12"
        @click="close"
      >
        <span class="i-lucide-x size-4" />
      </button>
    </header>
    <div class="flex-1 min-h-0">
      <ConversationBox :inbox-id="chat?.inbox_id" :is-inbox-view="false" />
    </div>
  </div>
</template>
