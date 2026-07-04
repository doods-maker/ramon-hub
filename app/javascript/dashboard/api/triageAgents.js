import ApiClient from './ApiClient';

class TriageAgentsAPI extends ApiClient {
  constructor() {
    super('triage_agents', { accountScoped: true });
  }
}

export default new TriageAgentsAPI();
