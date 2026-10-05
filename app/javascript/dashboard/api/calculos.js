/* global axios */
import ApiClient from './ApiClient';

class CalculosAPI extends ApiClient {
  constructor() {
    super('calculos', { accountScoped: true });
  }

  historico(q) {
    return axios.get(this.url, { params: q ? { q } : {} });
  }

  // destino: 'rascunho' copia pro rascunho de quem abre (lead intacto).
  reabrir(id, destino) {
    return axios.post(`${this.url}/${id}/reabrir`, destino ? { destino } : {});
  }

  vincular(id, leadId, substituir = false) {
    return axios.post(`${this.url}/${id}/vincular`, {
      lead_id: leadId,
      substituir,
    });
  }
}

export default new CalculosAPI();
