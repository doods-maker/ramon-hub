/* global axios */
import ApiClient from './ApiClient';

// Aba "Custos e metas" da área Marketing. Arquivos vão como texto (lido no navegador).
class RamonMarketingAPI extends ApiClient {
  constructor() {
    super('ramon_marketing', { accountScoped: true });
  }

  criarCusto(custo) {
    return axios.post(`${this.url}/custos`, custo);
  }

  removerCusto(id) {
    return axios.delete(`${this.url}/custos/${id}`);
  }

  importarGasto(texto) {
    return axios.post(`${this.url}/importar_gasto`, { texto });
  }

  importarMetas(texto) {
    return axios.post(`${this.url}/importar_metas`, { texto });
  }
}

export default new RamonMarketingAPI();
