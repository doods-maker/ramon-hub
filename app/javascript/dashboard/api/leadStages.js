/* global axios */
import ApiClient from './ApiClient';

class LeadStagesAPI extends ApiClient {
  constructor() {
    super('lead_stages', { accountScoped: true });
  }

  reorder(ids) {
    return axios.post(`${this.url}/reorder`, { ids });
  }

  delete(id, config) {
    return axios.delete(`${this.url}/${id}`, config);
  }
}

export default new LeadStagesAPI();
