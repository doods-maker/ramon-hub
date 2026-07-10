/* global axios */
import ApiClient from './ApiClient';

class RamonEsteiraAPI extends ApiClient {
  constructor() {
    super('ramon_esteira', { accountScoped: true });
  }

  done(leadId) {
    return axios.post(`${this.url}/done`, { lead_id: leadId });
  }

  snooze(leadId, taskId) {
    return axios.post(`${this.url}/snooze`, {
      lead_id: leadId,
      task_id: taskId,
    });
  }
}

export default new RamonEsteiraAPI();
