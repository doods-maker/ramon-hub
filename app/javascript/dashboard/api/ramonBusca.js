/* global axios */
import ApiClient from './ApiClient';

// Paleta Ctrl K (redesign v2, Onda 5): busca local — leads + painel do cliente.
class RamonBuscaAPI extends ApiClient {
  constructor() {
    super('ramon_busca', { accountScoped: true });
  }

  get(q) {
    return axios.get(this.url, { params: { q } });
  }
}

export default new RamonBuscaAPI();
