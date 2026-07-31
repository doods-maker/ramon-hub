import ApiClient from './ApiClient';

class RamonRelatoriosAPI extends ApiClient {
  constructor() {
    super('ramon_relatorios', { accountScoped: true });
  }
}

export default new RamonRelatoriosAPI();
