/* global axios */
import ApiClient from './ApiClient';

// Conferência de fases: etapa do ADVBOX × fase do Painel do Cliente. A equipe
// marca (update herdado do ApiClient); só o administrador aplica no ADVBOX.
class RamonConferenciaFasesAPI extends ApiClient {
  constructor() {
    super('ramon_conferencia_fases', { accountScoped: true });
  }

  get(params) {
    return axios.get(this.url, { params });
  }

  aplicar() {
    return axios.post(`${this.url}/aplicar`);
  }
}

export default new RamonConferenciaFasesAPI();
