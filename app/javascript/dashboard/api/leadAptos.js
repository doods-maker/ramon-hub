/* global axios */
import ApiClient from './ApiClient';

// Lista "Aguardando validação" do jurídico (Ramon::ContratoApto.fila) e a validação em lote.
class LeadAptosAPI extends ApiClient {
  constructor() {
    super('lead_aptos', { accountScoped: true });
  }

  validarLote(ids) {
    return axios.post(`${this.url}/validar_lote`, { ids });
  }
}

export default new LeadAptosAPI();
