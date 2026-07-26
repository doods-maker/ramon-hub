/* global axios */
import ApiClient from './ApiClient';

class CaptainToolRunsAPI extends ApiClient {
  constructor() {
    super('captain_tool_runs', { accountScoped: true });
  }

  list(params = {}) {
    return axios.get(this.url, { params });
  }
}

export default new CaptainToolRunsAPI();
