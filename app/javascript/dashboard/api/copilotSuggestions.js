/* global axios */
import ApiClient from './ApiClient';

class CopilotSuggestionsAPI extends ApiClient {
  constructor() {
    super('copilot_suggestions', { accountScoped: true });
  }

  apply(id) {
    return axios.post(`${this.url}/${id}/apply`);
  }

  dismiss(id) {
    return axios.post(`${this.url}/${id}/dismiss`);
  }

  applyAll() {
    return axios.post(`${this.url}/apply_all`);
  }
}

export default new CopilotSuggestionsAPI();
