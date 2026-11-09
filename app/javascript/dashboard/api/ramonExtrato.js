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

  // Programas de Metas do híbrido (gestor)
  programas() {
    return axios.get(`${this.url}/programas`);
  }

  // { id?, inicio, fim, regras: { faixas, gas, constancia } }
  salvarPrograma(payload) {
    return axios.post(`${this.url}/programa`, payload);
  }
}

export default new RamonExtratoAPI();
