import ApiClient from './ApiClient';

class LeadConfigAPI extends ApiClient {
  constructor() {
    super('lead_config', { accountScoped: true });
  }
}

export default new LeadConfigAPI();
