/* global axios */
import ApiClient from '../ApiClient';

// "Virar FAQ" numa resposta da conversa (Inteligência A4): cria FAQ PENDENTE.
class FaqDeConversa extends ApiClient {
  constructor() {
    super('conversations', { accountScoped: true });
  }

  virarFaq(conversationId, messageId) {
    return axios.post(`${this.url}/${conversationId}/faqs`, {
      message_id: messageId,
    });
  }
}

export default new FaqDeConversa();
