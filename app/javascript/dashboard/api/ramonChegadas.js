/* global axios */
import ApiClient from './ApiClient';

class RamonChegadasAPI extends ApiClient {
  constructor() {
    super('ramon_chegadas', { accountScoped: true });
  }

  responder(id, resposta) {
    return axios.post(`${this.url}/${id}/responder`, { resposta });
  }

  agenda() {
    return axios.get(`${this.url}/agenda`);
  }
}

export default new RamonChegadasAPI();
