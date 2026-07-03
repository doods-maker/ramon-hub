/* global axios */
import ApiClient from './ApiClient';

class LeadTasksAPI extends ApiClient {
  constructor() {
    super('leads', { accountScoped: true });
  }

  get(leadId) {
    return axios.get(`${this.url}/${leadId}/tasks`);
  }

  getAccountScope(scope) {
    return axios.get(`${this.baseUrl()}/lead_tasks`, { params: { scope } });
  }

  create(leadId, payload) {
    return axios.post(`${this.url}/${leadId}/tasks`, payload);
  }

  update(leadId, id, payload) {
    return axios.patch(`${this.url}/${leadId}/tasks/${id}`, payload);
  }

  complete(leadId, id) {
    return axios.post(`${this.url}/${leadId}/tasks/${id}/complete`);
  }

  delete(leadId, id) {
    return axios.delete(`${this.url}/${leadId}/tasks/${id}`);
  }
}

export default new LeadTasksAPI();
