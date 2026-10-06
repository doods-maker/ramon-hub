/* global axios */
import ApiClient from './ApiClient';

class ReunioesAPI extends ApiClient {
  constructor() {
    super('ramon_reunioes', { accountScoped: true });
  }

  criar(formData, onUploadProgress) {
    return axios.post(this.url, formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
      onUploadProgress,
    });
  }

  // q: título ou nome do lead (busca no servidor)
  buscar(q) {
    return axios.get(this.url, { params: q ? { q } : {} });
  }

  vincularLead(id, leadId) {
    return axios.patch(`${this.url}/${id}`, { lead_id: leadId });
  }

  reprocessar(id) {
    return axios.post(`${this.url}/${id}/reprocessar`);
  }
}

export default new ReunioesAPI();
