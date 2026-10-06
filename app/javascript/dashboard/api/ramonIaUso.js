/* global axios */
import ApiClient from './ApiClient';

// Tela Uso e custo (Inteligência): números do período e teto do alerta de gasto.
class RamonIaUsoAPI extends ApiClient {
  constructor() {
    super('ramon_ia_uso', { accountScoped: true });
  }

  get(params = {}) {
    return axios.get(this.url, { params });
  }

  salvarTeto(teto) {
    return axios.patch(this.url, { teto_diario_usd: teto });
  }
}

export default new RamonIaUsoAPI();
