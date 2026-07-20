<script setup>
import { computed, ref, watch } from 'vue';
import { onKeyStroke } from '@vueuse/core';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import ConversationBox from 'dashboard/components/widgets/conversation/ConversationBox.vue';

const props = defineProps({
  // Board com modal aberto: Esc é do modal, não do dock.
  suspendEsc: { type: Boolean, default: false },
});

defineOptions({ name: 'ConversationDock' });

const store = useStore();
const dockId = useMapGetter('leads/getDockConversationId');
const selectedLead = useMapGetter('leads/getSelectedLead');
const activeChat = useMapGetter('conversations/getSelectedChat');

const isOpen = computed(() => !!dockId.value);
const drawerOpen = computed(() => !!selectedLead.value);
// Só monta a ConversationBox nativa quando a conversa do dock já é a conversa
// ATIVA no store. Montá-la antes (chat vazio) quebrava o render do dock inteiro
// no caminho "conversa fria" (antes do setActiveChat async resolver).
const isReady = computed(
  () => !!dockId.value && Number(activeChat.value?.id) === Number(dockId.value)
);
const contactName = computed(() => activeChat.value?.meta?.sender?.name || '');

// Conversa que não veio (fetch falhou/404): erro com retry no lugar do
// "Carregando conversa…" eterno.
const loadFailed = ref(false);
const activate = async id => {
  if (!id) return;
  loadFailed.value = false;
  try {
    if (!store.getters['conversations/getConversationById'](id)) {
      await store.dispatch('conversations/getConversation', id);
    }
  } catch (e) {
    // segue: a checagem abaixo decide pelo que ficou (ou não) no store
  }
  const conversation = store.getters['conversations/getConversationById'](id);
  if (conversation) {
    store.dispatch('conversations/setActiveChat', { data: conversation });
  } else {
    loadFailed.value = true;
  }
};
watch(dockId, activate, { immediate: true });
const retry = () => activate(dockId.value);

const close = () => store.dispatch('leads/closeDock');
onKeyStroke('Escape', () => {
  if (isOpen.value && !props.suspendEsc) close();
});
</script>

<template>
  <Transition
    enter-active-class="transition-opacity duration-150"
    leave-active-class="transition-opacity duration-150"
    enter-from-class="opacity-0"
    leave-to-class="opacity-0"
  >
    <div
      v-if="isOpen"
      data-testid="conversation-dock"
      class="fixed z-50 inset-0 flex flex-col overflow-hidden bg-n-solid-1 border-n-weak shadow-lg md:inset-auto md:bottom-4 md:h-[560px] md:max-h-[calc(100vh-2rem)] md:w-[440px] md:rounded-lg md:border"
      :class="drawerOpen ? 'md:right-[25rem]' : 'md:right-4'"
    >
      <header class="flex items-center gap-2 px-3 py-2 border-b border-n-weak">
        <span class="flex-1 text-sm font-medium text-n-slate-12 truncate">{{
          contactName
        }}</span>
        <button
          data-testid="dock-close"
          :title="$t('RAMON.FUNIL.DOCK_CLOSE')"
          class="text-n-slate-10 hover:text-n-slate-12"
          @click="close"
        >
          <span class="i-lucide-x size-4" />
        </button>
      </header>
      <div class="flex-1 min-h-0">
        <ConversationBox
          v-if="isReady"
          :inbox-id="activeChat.inbox_id"
          :is-inbox-view="false"
        />
        <div
          v-else-if="loadFailed"
          data-testid="dock-load-error"
          class="flex flex-col items-center justify-center gap-3 h-full text-sm text-n-slate-11"
        >
          {{ $t('RAMON.FUNIL.CONVERSATION_ERROR') }}
          <div class="flex gap-2">
            <button
              data-testid="dock-load-retry"
              class="px-3 py-1.5 text-sm rounded-lg border border-n-weak text-n-slate-11 hover:text-n-slate-12"
              @click="retry"
            >
              {{ $t('RAMON.LEAD_PANEL.RETRY') }}
            </button>
            <button
              class="px-3 py-1.5 text-sm rounded-lg border border-n-weak text-n-slate-11 hover:text-n-slate-12"
              @click="close"
            >
              {{ $t('RAMON.FUNIL.DOCK_CLOSE') }}
            </button>
          </div>
        </div>
        <div
          v-else
          data-testid="dock-loading"
          class="flex items-center justify-center h-full text-sm text-n-slate-10"
        >
          {{ $t('RAMON.FUNIL.LOADING_CONVERSATION') }}
        </div>
      </div>
    </div>
  </Transition>
</template>
