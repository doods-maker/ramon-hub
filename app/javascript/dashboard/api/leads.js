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

  getActivities(leadId) {
    return axios.get(`${this.url}/${leadId}/activities`);
  }
}

export default new LeadsAPI();
