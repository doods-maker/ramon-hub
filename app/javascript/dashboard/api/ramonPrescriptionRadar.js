/* global axios */
import ApiClient from './ApiClient';

class RamonPrescriptionRadarAPI extends ApiClient {
  constructor() {
    super('ramon_prescription_radar', { accountScoped: true });
  }

  // Campanha de resgate: etiqueta os contatos do radar (só gestor). Não envia nada.
  resgate() {
    return axios.post(`${this.url}/resgate`);
  }
}

export default new RamonPrescriptionRadarAPI();
