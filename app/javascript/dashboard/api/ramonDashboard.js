import ApiClient from './ApiClient';

class RamonDashboardAPI extends ApiClient {
  constructor() {
    super('ramon_dashboard', { accountScoped: true });
  }
}

export default new RamonDashboardAPI();
