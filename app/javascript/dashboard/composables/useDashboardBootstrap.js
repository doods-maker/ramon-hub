import { computed, onMounted, watch } from 'vue';
import { useStore } from 'vuex';
import { useMapGetter } from 'dashboard/composables/store';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

// FORK(ramon): dados que o Sidebar do Chatwoot carregava no mount. O menu
// único não monta o Sidebar, então o Dashboard carrega — inclusive quem
// entra direto por uma URL da Intranet passa a receber inboxes/teams.
export function useDashboardBootstrap() {
  const store = useStore();
  const accountId = useMapGetter('getCurrentAccountId');
  const isFeatureEnabledonAccount = useMapGetter(
    'accounts/isFeatureEnabledonAccount'
  );
  const temNaoLidas = computed(() =>
    isFeatureEnabledonAccount.value(
      accountId.value,
      FEATURE_FLAGS.CONVERSATION_UNREAD_COUNTS
    )
  );

  onMounted(() => {
    store.dispatch('labels/get');
    store.dispatch('inboxes/get');
    store.dispatch('notifications/unReadCount');
    store.dispatch('teams/get');
    store.dispatch('attributes/get');
    store.dispatch('customViews/get', 'conversation');
    store.dispatch('customViews/get', 'contact');
  });

  watch(
    [accountId, temNaoLidas],
    ([id, ligado]) => {
      if (!id) return;
      store.dispatch(
        ligado
          ? 'conversationUnreadCounts/get'
          : 'conversationUnreadCounts/clear'
      );
    },
    { immediate: true }
  );
}
