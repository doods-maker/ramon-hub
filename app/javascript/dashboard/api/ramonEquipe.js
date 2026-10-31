/* global axios */
import ApiClient from './ApiClient';

// Equipe · chat interno como caixa do Chatwoot (ADR 0011).
class RamonEquipeAPI extends ApiClient {
  constructor() {
    super('ramon_equipe', { accountScoped: true });
  }

  conversa(userId) {
    return axios.post(`${this.url}/conversa`, { user_id: userId });
  }
}

export default new RamonEquipeAPI();
