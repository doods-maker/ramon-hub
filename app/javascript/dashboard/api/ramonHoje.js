import ApiClient from './ApiClient';

// Tela Hoje por papel (redesign v2, Onda 3) — o papel vem do backend.
class RamonHojeAPI extends ApiClient {
  constructor() {
    super('ramon_hoje', { accountScoped: true });
  }
}

export default new RamonHojeAPI();
