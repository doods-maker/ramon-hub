/* global axios */
import ApiClient from './ApiClient';

// Automações em fluxo (spec automacoes-em-fluxo §7) — admin-only.
class RamonFluxosAPI extends ApiClient {
  constructor() {
    super('ramon_fluxos', { accountScoped: true });
  }

  publicar(id) {
    return axios.post(`${this.url}/${id}/publicar`);
  }

  // params: { lead_id } | { conversation_id } (+ usar: 'rascunho'|'publicada')
  ensaio(id, params) {
    return axios.post(`${this.url}/${id}/ensaio`, params);
  }

  rodar(id, params) {
    return axios.post(`${this.url}/${id}/rodar`, params);
  }

  // { usuarios: [{id, nome}], tipos_tarefa: [{id, nome}] } — passo ADVBOX
  opcoesAdvbox() {
    return axios.get(`${this.url}/opcoes_advbox`);
  }

  execucoes(id) {
    return axios.get(`${this.url}/${id}/execucoes`);
  }

  execucao(id, execId) {
    return axios.get(`${this.url}/${id}/execucoes/${execId}`);
  }
}

export default new RamonFluxosAPI();
