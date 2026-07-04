/* global axios */
import ApiClient from './ApiClient';

class LeadsAPI extends ApiClient {
  constructor() {
    super('leads', { accountScoped: true });
  }

  get(params = {}) {
    return axios.get(this.url, { params });
  }

  forConversation(conversationId) {
    return axios.post(`${this.url}/for_conversation`, {
      conversation_id: conversationId,
    });
  }

  getActivities(leadId) {
    return axios.get(`${this.url}/${leadId}/activities`);
  }

  getNotes(leadId) {
    return axios.get(`${this.url}/${leadId}/notes`);
  }

  createNote(leadId, body) {
    return axios.post(`${this.url}/${leadId}/notes`, { body });
  }

  getTriages(leadId) {
    return axios.get(`${this.url}/${leadId}/triages`);
  }

  createTriage(leadId, triageAgentId) {
    const payload = triageAgentId ? { triage_agent_id: triageAgentId } : {};
    return axios.post(`${this.url}/${leadId}/triages`, payload);
  }

  createKit(leadId, triageId) {
    return axios.post(`${this.url}/${leadId}/triages/${triageId}/kit`);
  }
}

export default new LeadsAPI();
