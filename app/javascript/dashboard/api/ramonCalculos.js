/* global axios */
import ApiClient from './ApiClient';

class RamonCalculosAPI extends ApiClient {
  constructor() {
    super('ramon_calculos', { accountScoped: true });
  }

  advboxCustomers(q) {
    return axios.get(`${this.url}/advbox_customers`, { params: { q } });
  }

  criarCaso(payload) {
    return axios.post(`${this.url}/criar_caso`, payload);
  }

  rascunho() {
    return axios.post(`${this.url}/rascunho`);
  }
}

export default new RamonCalculosAPI();
