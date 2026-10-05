/* global axios */
import ApiClient from './ApiClient';

class LeadTasksAPI extends ApiClient {
  constructor() {
    super('leads', { accountScoped: true });
  }

  get(leadId) {
    return axios.get(`${this.url}/${leadId}/tasks`);
  }

  // params: { scope } ou, na Agenda, { scope: 'agenda', from, to }
  getAccountScope(params) {
    return axios.get(`${this.baseUrl()}/lead_tasks`, { params });
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

  // Remarcar reunião: passa pelo agendamento (lembretes, rascunho, sino)
  remarcarReuniao(leadId, taskId, startsAt) {
    return axios.patch(`${this.url}/${leadId}/reuniao_agendada`, {
      task_id: taskId,
      starts_at: startsAt,
    });
  }

  delete(leadId, id) {
    return axios.delete(`${this.url}/${leadId}/tasks/${id}`);
  }
}

export default new LeadTasksAPI();
