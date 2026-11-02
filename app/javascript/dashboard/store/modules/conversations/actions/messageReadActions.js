import { throwErrorMessage } from 'dashboard/store/utils/api';
import ConversationApi from '../../../../api/inbox/conversation';
import mutationTypes from '../../../mutation-types';
import { useEquipeStore } from 'dashboard/stores/equipe';

export default {
  markMessagesRead: async ({ commit, rootGetters }, data) => {
    // FORK(ramon): na Equipe, marcar lida acende o ✓✓ do colega: só com a aba à vista
    // (MessagesView marca ao voltar). Aqui e não na tela: o sync da reconexão também passa.
    const conversa = rootGetters?.getConversationById?.(data.id);
    if (
      document.visibilityState !== 'visible' &&
      rootGetters?.['inboxes/getInbox']?.(conversa?.inbox_id)?.equipe
    ) {
      return;
    }
    try {
      const {
        data: { id, agent_last_seen_at: lastSeen, inbox_id: inboxId },
      } = await ConversationApi.markMessageRead(data);
      // FORK(ramon): leu conversa da Equipe → atualiza o badge da caixa e apaga o selo @
      const equipe = rootGetters?.['inboxes/getInbox']?.(inboxId)?.equipe;
      if (equipe) {
        useEquipeStore()
          .carregar()
          .catch(() => {});
      }
      setTimeout(
        () =>
          commit(
            mutationTypes.UPDATE_MESSAGE_UNREAD_COUNT,
            equipe ? { id, lastSeen, equipeMarcado: false } : { id, lastSeen }
          ),
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
