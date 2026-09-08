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

  assinatura(id, payload) {
    return axios.post(`${this.url}/${id}/assinatura`, payload);
  }
}

export default new PortalClientesAPI();
