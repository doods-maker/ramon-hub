import ApiClient from './ApiClient';

class RamonAprovacoesAgenteAPI extends ApiClient {
  constructor() {
    super('ramon_aprovacoes_agente', { accountScoped: true });
  }
}

export default new RamonAprovacoesAgenteAPI();
