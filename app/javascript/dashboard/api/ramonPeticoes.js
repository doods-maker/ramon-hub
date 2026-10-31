/* global axios */
import ApiClient from './ApiClient';

// Peticionamento · Fase 1: petições, pacote de PDFs, seletor do Drive e protocolo.
class RamonPeticoesAPI extends ApiClient {
  constructor() {
    super('ramon_peticoes', { accountScoped: true });
  }

  get(params = {}) {
    return axios.get(this.url, { params });
  }

  uploadArquivo(id, file, extras = {}) {
    const dados = new FormData();
    dados.append('file', file);
    Object.entries(extras).forEach(([k, v]) => dados.append(k, v));
    return axios.post(`${this.url}/${id}/arquivos`, dados);
  }

  adicionarDoDrive(id, fileIds) {
    return axios.post(`${this.url}/${id}/arquivos_drive`, {
      file_ids: fileIds,
    });
  }

  atualizarArquivo(id, arquivoId, dados) {
    return axios.patch(`${this.url}/${id}/arquivos/${arquivoId}`, dados);
  }

  removerArquivo(id, arquivoId) {
    return axios.delete(`${this.url}/${id}/arquivos/${arquivoId}`);
  }

  reordenar(id, ids) {
    return axios.patch(`${this.url}/${id}/ordem`, { ids });
  }

  registrarProtocolo(id, numeroEvento, file) {
    const dados = new FormData();
    if (numeroEvento) dados.append('numero_evento', numeroEvento);
    if (file) dados.append('comprovante', file);
    return axios.post(`${this.url}/${id}/registrar_protocolo`, dados);
  }

  drive(pastaId) {
    return axios.get(`${this.url}/drive`, {
      params: pastaId ? { pasta_id: pastaId } : {},
    });
  }

  buscarDrive(q) {
    return axios.get(`${this.url}/drive_busca`, { params: { q } });
  }

  processos(contactId) {
    return axios.get(`${this.url}/processos`, {
      params: { contact_id: contactId },
    });
  }
}

export default new RamonPeticoesAPI();
