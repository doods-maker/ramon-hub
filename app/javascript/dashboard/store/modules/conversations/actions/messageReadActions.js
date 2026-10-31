import { throwErrorMessage } from 'dashboard/store/utils/api';
import ConversationApi from '../../../../api/inbox/conversation';
import mutationTypes from '../../../mutation-types';
import { useEquipeStore } from 'dashboard/stores/equipe';

export default {
  markMessagesRead: async ({ commit, rootGetters }, data) => {
    try {
      const {
        data: { id, agent_last_seen_at: lastSeen, inbox_id: inboxId },
      } = await ConversationApi.markMessageRead(data);
      // FORK(ramon): leu conversa da Equipe → atualiza o badge da caixa
      if (rootGetters?.['inboxes/getInbox']?.(inboxId)?.equipe) {
        useEquipeStore()
          .carregar()
          .catch(() => {});
      }
      setTimeout(
        () =>
          commit(mutationTypes.UPDATE_MESSAGE_UNREAD_COUNT, { id, lastSeen }),
        4000
      );
    } catch (error) {
      // Handle error
    }
  },

  markMessagesUnread: async ({ commit }, { id }) => {
    try {
      const {
        data: { agent_last_seen_at: lastSeen, unread_count: unreadCount },
      } = await ConversationApi.markMessagesUnread({ id });
      commit(mutationTypes.UPDATE_MESSAGE_UNREAD_COUNT, {
        id,
        lastSeen,
        unreadCount,
      });
    } catch (error) {
      throwErrorMessage(error);
    }
  },
};
