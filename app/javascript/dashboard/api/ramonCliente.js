/* global axios */
import ApiClient from './ApiClient';

// Painel do cliente na caixa do escritório (redesign v2): cliente do ADVBOX
// pelo telefone da conversa (espelho do Painel do Cliente, sem gastar cota).
class RamonClienteAPI extends ApiClient {
  constructor() {
    super('conversations', { accountScoped: true });
  }

  get(conversationId) {
    return axios.get(`${this.url}/${conversationId}/ramon_cliente`);
  }
}

export default new RamonClienteAPI();
