/* global axios */
import ApiClient from './ApiClient';

class CalculosAPI extends ApiClient {
  constructor() {
    super('calculos', { accountScoped: true });
  }

  historico(q) {
    return axios.get(this.url, { params: q ? { q } : {} });
  }

  reabrir(id) {
    return axios.post(`${this.url}/${id}/reabrir`);
  }
}

export default new CalculosAPI();
