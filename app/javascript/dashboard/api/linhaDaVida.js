/* global axios */
import ApiClient from './ApiClient';

class LinhaDaVidaAPI extends ApiClient {
  constructor() {
    super('contacts', { accountScoped: true });
  }

  show(contactId) {
    return axios.get(`${this.url}/${contactId}/linha_da_vida`);
  }
}

export default new LinhaDaVidaAPI();
