/* global axios */
import ApiClient from './ApiClient';

// Botão "IA: {perfil}" do cabeçalho da conversa: perfil efetivo, etapa e pausa. O id é o display_id.
class RamonIaConversasAPI extends ApiClient {
  constructor() {
    super('ramon_ia_conversas', { accountScoped: true });
  }

  get(conversationId) {
    return axios.get(`${this.url}/${conversationId}`);
  }
}

export default new RamonIaConversasAPI();
