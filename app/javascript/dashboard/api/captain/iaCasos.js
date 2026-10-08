/* global axios */
import ApiClient from '../ApiClient';

// Casos de teste da IA (por assistente) e as rodadas que rodam todos.
class CaptainIaCasos extends ApiClient {
  constructor() {
    super('captain/assistants', { accountScoped: true });
  }

  casos(assistantId) {
    return axios.get(`${this.url}/${assistantId}/ia_casos`);
  }

  criar(assistantId, caso) {
    return axios.post(`${this.url}/${assistantId}/ia_casos`, { caso });
  }

  atualizar(assistantId, id, caso) {
    return axios.patch(`${this.url}/${assistantId}/ia_casos/${id}`, { caso });
  }

  remover(assistantId, id) {
    return axios.delete(`${this.url}/${assistantId}/ia_casos/${id}`);
  }

  rodadas(assistantId) {
    return axios.get(`${this.url}/${assistantId}/ia_rodadas`);
  }

  rodada(assistantId, id) {
    return axios.get(`${this.url}/${assistantId}/ia_rodadas/${id}`);
  }

  rodar(assistantId) {
    return axios.post(`${this.url}/${assistantId}/ia_rodadas`);
  }

  // Caderno automático (I-X6): liga/desliga a rodada da madrugada da conta.
  noturno(assistantId, ligado) {
    return axios.patch(`${this.url}/${assistantId}/ia_rodadas/noturno`, {
      ligado,
    });
  }
}

export default new CaptainIaCasos();
