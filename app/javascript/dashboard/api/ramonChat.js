/* global axios */
import ApiClient from './ApiClient';

class RamonChatAPI extends ApiClient {
  constructor() {
    super('ramon_chat', { accountScoped: true });
  }

  mensagens(id, antes) {
    return axios.get(`${this.url}/${id}`, { params: { antes } });
  }

  enviar(id, conteudo) {
    return axios.post(`${this.url}/${id}/enviar`, { conteudo });
  }

  ler(id) {
    return axios.post(`${this.url}/${id}/ler`);
  }

  direto(userId) {
    return axios.post(`${this.url}/direto`, { user_id: userId });
  }
}

export default new RamonChatAPI();
