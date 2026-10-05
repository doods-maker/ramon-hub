/* global axios */
// app/javascript/dashboard/api/portalClientes.js
import ApiClient from './ApiClient';

class PortalClientesAPI extends ApiClient {
  constructor() {
    super('portal_clientes', { accountScoped: true });
  }

  convidar(id) {
    return axios.post(`${this.url}/${id}/convidar`);
  }

  suspender(id) {
    return axios.post(`${this.url}/${id}/suspender`);
  }

  reativar(id) {
    return axios.post(`${this.url}/${id}/reativar`);
  }

  assinatura(id, payload) {
    return axios.post(`${this.url}/${id}/assinatura`, payload);
  }
}

export default new PortalClientesAPI();
