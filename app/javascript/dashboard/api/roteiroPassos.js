/* global axios */
import ApiClient from './ApiClient';

// Passos do roteiro da IA (F2): o index traz todos os da conta + o catálogo das calculadoras.
class RoteiroPassosAPI extends ApiClient {
  constructor() {
    super('roteiro_passos', { accountScoped: true });
  }

  reorder(ids) {
    return axios.post(`${this.url}/reorder`, { ids });
  }
}

export default new RoteiroPassosAPI();
