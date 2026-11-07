/* global axios */
import ApiClient from './ApiClient';

class RamonRelatoriosAPI extends ApiClient {
  constructor() {
    super('ramon_relatorios', { accountScoped: true });
  }

  // painel: 'marketing' = dashboard da aba Tráfego; vazio = Relatórios.
  embed(painel) {
    return axios.get(this.url, { params: painel ? { painel } : {} });
  }
}

export default new RamonRelatoriosAPI();
