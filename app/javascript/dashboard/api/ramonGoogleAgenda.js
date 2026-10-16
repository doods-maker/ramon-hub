/* global axios */
import ApiClient from './ApiClient';

// Conexão do Google do usuário logado (status e URL de autorização OAuth).
class RamonGoogleAgendaAPI extends ApiClient {
  constructor() {
    super('ramon_google_agenda', { accountScoped: true });
  }

  status() {
    return axios.get(this.url);
  }

  autorizar() {
    return axios.post(`${this.url}/autorizacao`);
  }

  desconectar() {
    return axios.delete(this.url);
  }
}

export default new RamonGoogleAgendaAPI();
