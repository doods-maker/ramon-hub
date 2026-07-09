/* global axios */
import ApiClient from './ApiClient';

class RamonCopilotAPI extends ApiClient {
  constructor() {
    super('conversations', { accountScoped: true });
  }

  generate(conversationId, mode) {
    return axios.post(`${this.url}/${conversationId}/ramon_copilot`, { mode });
  }
}

export default new RamonCopilotAPI();
