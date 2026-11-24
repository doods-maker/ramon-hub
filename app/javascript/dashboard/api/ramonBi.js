/* global axios */
import ApiClient from './ApiClient';

class RamonBiAPI extends ApiClient {
  constructor() {
    super('ramon_bi', { accountScoped: true });
  }

  // { enviado: false } ou { enviado: true, html, enviado_em, enviado_por }.
  get() {
    return axios.get(this.url);
  }

  // Sobe o HTML novo (campo `arquivo`); devolve o mesmo JSON do get().
  enviar(file) {
    const body = new FormData();
    body.append('arquivo', file);
    return axios.put(this.url, body);
  }
}

export default new RamonBiAPI();
