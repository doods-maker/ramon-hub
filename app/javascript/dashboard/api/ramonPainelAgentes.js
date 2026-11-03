import ApiClient from './ApiClient';

class RamonPainelAgentesAPI extends ApiClient {
  constructor() {
    super('ramon_painel_agentes', { accountScoped: true });
  }
}

export default new RamonPainelAgentesAPI();
