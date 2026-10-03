/* global axios */
import ApiClient from './ApiClient';

class RamonExtratoAPI extends ApiClient {
  constructor() {
    super('ramon_extrato', { accountScoped: true });
  }

  get(mes) {
    return axios.get(this.url, { params: { mes } });
  }

  salvarMeta(payload) {
    return axios.put(`${this.url}/meta`, payload);
  }
}

export default new RamonExtratoAPI();
