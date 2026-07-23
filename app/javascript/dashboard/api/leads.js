/* global axios */
import ApiClient from './ApiClient';

class LeadsAPI extends ApiClient {
  constructor() {
    super('leads', { accountScoped: true });
  }

  get(params = {}) {
    return axios.get(this.url, { params });
  }

  forConversation(conversationId, { readonly = false } = {}) {
    return axios.post(`${this.url}/for_conversation`, {
      conversation_id: conversationId,
      ...(readonly ? { readonly: true } : {}),
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

  getDossie(leadId) {
    return axios.get(`${this.url}/${leadId}/dossie`);
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

  simulate(leadId, payload) {
    return axios.post(`${this.url}/${leadId}/simulacao`, payload);
  }

  painel(leadId, payload) {
    return axios.post(`${this.url}/${leadId}/painel`, payload);
  }

  elegibilidade(leadId, payload) {
    return axios.post(`${this.url}/${leadId}/elegibilidade`, payload);
  }

  uploadCnis(leadId, file, sexo, { excluirSeqs = '', mensalidades = '' } = {}) {
    const data = new FormData();
    data.append('arquivo', file);
    data.append('sexo', sexo);
    if (excluirSeqs) data.append('excluir_seqs', excluirSeqs);
    if (mensalidades) data.append('mensalidades', mensalidades);
    return axios.post(`${this.url}/${leadId}/cnis`, data);
  }

  getCnis(leadId) {
    return axios.get(`${this.url}/${leadId}/cnis`);
  }

  deleteCnis(leadId) {
    return axios.delete(`${this.url}/${leadId}/cnis`);
  }

  liquidacao(leadId, payload) {
    return axios.post(`${this.url}/${leadId}/liquidacao`, payload);
  }

  liquidacaoPdf(leadId, payload) {
    return axios.post(`${this.url}/${leadId}/liquidacao/pdf`, payload, {
      responseType: 'blob',
    });
  }

  createZapsign(leadId) {
    return axios.post(`${this.url}/${leadId}/zapsign`);
  }

  extractColheita(leadId) {
    return axios.post(`${this.url}/${leadId}/colheita`);
  }
}

export default new LeadsAPI();
