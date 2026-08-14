import ApiClient from './ApiClient';

class RamonPosVendaAPI extends ApiClient {
  constructor() {
    super('ramon_pos_venda', { accountScoped: true });
  }
}

export default new RamonPosVendaAPI();
