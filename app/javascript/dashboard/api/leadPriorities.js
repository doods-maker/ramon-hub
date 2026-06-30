/* global axios */
import ApiClient from './ApiClient';

class LeadPrioritiesAPI extends ApiClient {
  constructor() {
    super('lead_priorities', { accountScoped: true });
  }

  reorder(ids) {
    return axios.post(`${this.url}/reorder`, { ids });
  }
}

export default new LeadPrioritiesAPI();
