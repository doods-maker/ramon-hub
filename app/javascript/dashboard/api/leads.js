/* global axios */
import ApiClient from './ApiClient';

class LeadsAPI extends ApiClient {
  constructor() {
    super('leads', { accountScoped: true });
  }

  forConversation(conversationId) {
    return axios.post(`${this.url}/for_conversation`, {
      conversation_id: conversationId,
    });
  }
}

export default new LeadsAPI();
