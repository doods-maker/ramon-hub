import ApiClient from './ApiClient';

class RamonInteligenciaAPI extends ApiClient {
  constructor() {
    super('ramon_inteligencia', { accountScoped: true });
  }
}

export default new RamonInteligenciaAPI();
