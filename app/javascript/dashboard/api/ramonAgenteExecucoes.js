/* global axios */
import ApiClient from './ApiClient';

// Aba "Agente Claude" das Execuções (I-EX4).
class RamonAgenteExecucoesAPI extends ApiClient {
  constructor() {
    super('ramon_agente_execucoes', { accountScoped: true });
  }

  list(params = {}) {
    return axios.get(this.url, { params });
  }
}

export default new RamonAgenteExecucoesAPI();
