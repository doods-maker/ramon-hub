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

  // confirmar: sobe por cima de meta editada à mão (sem ele, 409).
  importarMetas(texto, confirmar = false) {
    return axios.post(`${this.url}/importar_metas`, {
      texto,
      ...(confirmar ? { confirmar: true } : {}),
    });
  }

  metasAtivas(ativas) {
    return axios.put(`${this.url}/metas_ativas`, { ativas });
  }

  editarMeta(id, valor) {
    return axios.patch(`${this.url}/metas/${id}`, { valor });
  }

  apagarMetas() {
    return axios.delete(`${this.url}/metas`);
  }
}

export default new RamonMarketingAPI();
