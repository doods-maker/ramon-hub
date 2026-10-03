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
}

export default new RamonConteudoAPI();
