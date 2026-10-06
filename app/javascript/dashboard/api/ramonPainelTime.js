/* global axios */
import ApiClient from './ApiClient';

class RamonPainelTimeAPI extends ApiClient {
  constructor() {
    super('ramon_painel_time', { accountScoped: true });
  }

  // papel: 'sdr' | 'closer'; periodo: 'hoje' | 'semana' | 'mes' | 'mes_passado'
  get({ papel, periodo }) {
    return axios.get(this.url, { params: { papel, periodo } });
  }
}

export default new RamonPainelTimeAPI();
