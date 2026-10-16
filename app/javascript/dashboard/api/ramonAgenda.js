/* global axios */
import ApiClient from './ApiClient';

// Agenda do comercial: compromissos do Google por pessoa + membros do comercial.
class RamonAgendaAPI extends ApiClient {
  constructor() {
    super('ramon_agenda', { accountScoped: true });
  }

  google(params = {}) {
    return axios.get(`${this.url}/google`, { params });
  }
}

export default new RamonAgendaAPI();
