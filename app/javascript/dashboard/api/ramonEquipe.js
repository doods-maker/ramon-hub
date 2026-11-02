/* global axios */
import ApiClient from './ApiClient';

// Equipe · chat interno como caixa do Chatwoot (ADR 0011).
class RamonEquipeAPI extends ApiClient {
  constructor() {
    super('ramon_equipe', { accountScoped: true });
  }

  conversa(userId) {
    return axios.post(`${this.url}/conversa`, { user_id: userId });
  }

  participantes(conversationId) {
    return axios.get(`${this.url}/participantes`, {
      params: { conversation_id: conversationId },
    });
  }

  reagir(conversationId, messageId, emoji) {
    return axios.post(`${this.url}/reacao`, {
      conversation_id: conversationId,
      message_id: messageId,
      emoji,
    });
  }
}

export default new RamonEquipeAPI();
