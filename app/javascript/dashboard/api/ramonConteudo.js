/* global axios */
import ApiClient from './ApiClient';

class RamonConteudoAPI extends ApiClient {
  constructor() {
    super('ramon_conteudo', { accountScoped: true });
  }

  aprovar(id) {
    return axios.post(`${this.url}/${id}/aprovar`);
  }

  reprovar(id, nota) {
    return axios.post(`${this.url}/${id}/reprovar`, { nota });
  }

  atualizarLegenda(id, legenda) {
    return axios.patch(`${this.url}/${id}/atualizar_legenda`, { legenda });
  }

  refazer(id, cards) {
    return axios.post(`${this.url}/${id}/refazer`, { cards });
  }
}

export default new RamonConteudoAPI();
