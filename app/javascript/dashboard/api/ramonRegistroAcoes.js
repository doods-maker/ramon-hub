/* global axios */
import ApiClient from './ApiClient';

// Registro de ações (só administrador): trilha audits filtrada e paginada.
class RamonRegistroAcoesAPI extends ApiClient {
  constructor() {
    super('ramon_registro_acoes', { accountScoped: true });
  }

  listar(params) {
    return axios.get(this.url, { params });
  }
}

export default new RamonRegistroAcoesAPI();
