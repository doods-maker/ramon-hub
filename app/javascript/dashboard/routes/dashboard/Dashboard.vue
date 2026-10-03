<script>
import { defineAsyncComponent, ref, computed } from 'vue';

import NextSidebar from 'next/sidebar/Sidebar.vue';
import RamonNav from './ramon/components/nav/RamonNav.vue';
import { ehAreaChatwoot } from './ramon/helpers/navItems';
import AlertaChegada from './ramon/components/equipe/AlertaChegada.vue';
import ChegouCliente from './ramon/components/equipe/ChegouCliente.vue';
// FORK(ramon): paleta Ctrl K própria (redesign v2, Onda 5)
import CommandPalette from './ramon/components/busca/CommandPalette.vue';
import WootKeyShortcutModal from 'dashboard/components/widgets/modal/WootKeyShortcutModal.vue';
import AddAccountModal from 'dashboard/components/app/AddAccountModal.vue';
import UpgradePage from 'dashboard/routes/dashboard/upgrade/UpgradePage.vue';

import { useUISettings } from 'dashboard/composables/useUISettings';
import { useAccount } from 'dashboard/composables/useAccount';
import { useDashboardBootstrap } from 'dashboard/composables/useDashboardBootstrap';
import { useSidebarKeyboardShortcuts } from 'dashboard/components-next/sidebar/useSidebarKeyboardShortcuts';
import { useWindowSize } from '@vueuse/core';

import wootConstants from 'dashboard/constants/globals';

const CommandBar = defineAsyncComponent(
  () => import('./commands/commandbar.vue')
);

const FloatingCallWidget = defineAsyncComponent(
  () => import('dashboard/components-next/call/FloatingCallWidget.vue')
);

import CopilotLauncher from 'dashboard/components-next/copilot/CopilotLauncher.vue';
import CopilotContainer from 'dashboard/components/copilot/CopilotContainer.vue';

import MobileSidebarLauncher from 'dashboard/components-next/sidebar/MobileSidebarLauncher.vue';
import { useCallsStore } from 'dashboard/stores/calls';

export default {
  components: {
    NextSidebar,
    RamonNav,
    AddAccountModal,
    CommandBar,
    WootKeyShortcutModal,
    UpgradePage,
    CopilotLauncher,
    CopilotContainer,
    FloatingCallWidget,
    AlertaChegada,
    ChegouCliente,
    CommandPalette,
    MobileSidebarLauncher,
  },
  setup() {
    const upgradePageRef = ref(null);
    const { uiSettings, updateUISettings } = useUISettings();
    const { accountId } = useAccount();
    const { width: windowWidth } = useWindowSize();
    const callsStore = useCallsStore();
    const showShortcutModal = ref(false);

    useDashboardBootstrap();
    useSidebarKeyboardShortcuts(show => {
      showShortcutModal.value = show;
    });

    return {
      uiSettings,
      updateUISettings,
      accountId,
      upgradePageRef,
      showShortcutModal,
      windowWidth,
      hasActiveCall: computed(() => callsStore.hasActiveCall),
      hasIncomingCall: computed(() => callsStore.hasIncomingCall),
    };
  },
  data() {
    return {
      showCreateAccountModal: false,
      isMobileSidebarOpen: false,
    };
  },
  computed: {
    isSmallScreen() {
      return this.windowWidth < wootConstants.SMALL_SCREEN_BREAKPOINT;
    },
    // FORK(ramon): Configurações, Captain, Relatórios, Contatos, Campanhas e
    // Central de ajuda usam o sidebar do Chatwoot (submenus nativos); o resto, o menu único.
    isAreaChatwoot() {
      return ehAreaChatwoot(this.$route.path);
    },
    showUpgradePage() {
      return this.upgradePageRef?.shouldShowUpgradePage;
    },
    bypassUpgradePage() {
      return [
        'billing_settings_index',
        'settings_inbox_list',
        'general_settings_index',
        'agent_list',
      ].includes(this.$route.name);
    },
    previouslyUsedDisplayType() {
      const {
        previously_used_conversation_display_type: conversationDisplayType,
      } = this.uiSettings;
      return conversationDisplayType;
    },
  },
  watch: {
    isSmallScreen: {
      handler() {
        const { LAYOUT_TYPES } = wootConstants;
        if (window.innerWidth <= wootConstants.SMALL_SCREEN_BREAKPOINT) {
          this.updateUISettings({
            conversation_display_type: LAYOUT_TYPES.EXPANDED,
          });
        } else {
          this.updateUISettings({
            conversation_display_type: this.previouslyUsedDisplayType,
          });
        }
      },
      immediate: true,
    },
  },
  methods: {
    toggleMobileSidebar() {
      this.isMobileSidebarOpen = !this.isMobileSidebarOpen;
    },
    closeMobileSidebar() {
      this.isMobileSidebarOpen = false;
    },
    openCreateAccountModal() {
      this.showCreateAccountModal = true;
    },
    closeCreateAccountModal() {
      this.showCreateAccountModal = false;
    },
    toggleKeyShortcutModal() {
      this.showShortcutModal = true;
    },
    closeKeyShortcutModal() {
      this.showShortcutModal = false;
    },
  },
};
</script>

<template>
  <div class="flex flex-grow overflow-hidden text-n-slate-12">
    <NextSidebar
      v-if="isAreaChatwoot"
      :is-mobile-sidebar-open="isMobileSidebarOpen"
      @open-key-shortcut-modal="toggleKeyShortcutModal"
      @close-key-shortcut-modal="closeKeyShortcutModal"
      @show-create-account-modal="openCreateAccountModal"
      @close-mobile-sidebar="closeMobileSidebar"
    />
    <RamonNav
      v-else
      :is-mobile-sidebar-open="isMobileSidebarOpen"
      @close-mobile-sidebar="closeMobileSidebar"
      @open-key-shortcut-modal="toggleKeyShortcutModal"
    />

    <main
      class="flex flex-1 h-full w-full min-h-0 px-0 overflow-hidden bg-n-surface-1"
    >
      <UpgradePage
        v-show="showUpgradePage"
        ref="upgradePageRef"
        :bypass-upgrade-page="bypassUpgradePage"
      >
        <MobileSidebarLauncher
          :is-mobile-sidebar-open="isMobileSidebarOpen"
          @toggle="toggleMobileSidebar"
        />
      </UpgradePage>
      <template v-if="!showUpgradePage">
        <router-view />
        <CommandBar />
        <CommandPalette />
        <CopilotLauncher />
        <MobileSidebarLauncher
          :is-mobile-sidebar-open="isMobileSidebarOpen"
          @toggle="toggleMobileSidebar"
        />
        <CopilotContainer />
        <FloatingCallWidget v-if="hasActiveCall || hasIncomingCall" />
        <AlertaChegada />
        <ChegouCliente />
      </template>
      <AddAccountModal
        :show="showCreateAccountModal"
        @close-account-create-modal="closeCreateAccountModal"
      />
      <WootKeyShortcutModal
        v-model:show="showShortcutModal"
        @close="closeKeyShortcutModal"
        @clickaway="closeKeyShortcutModal"
      />
    </main>
  </div>
</template>
