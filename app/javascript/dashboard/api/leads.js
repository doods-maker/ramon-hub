/* global axios */
import ApiClient from './ApiClient';

class LeadsAPI extends ApiClient {
  constructor() {
    super('leads', { accountScoped: true });
  }

  get(params = {}) {
    return axios.get(this.url, { params });
  }

  forConversation(conversationId, { readonly = false } = {}) {
    return axios.post(`${this.url}/for_conversation`, {
      conversation_id: conversationId,
      ...(readonly ? { readonly: true } : {}),
    });
  }

  getActivities(leadId) {
    return axios.get(`${this.url}/${leadId}/activities`);
  }

  getNotes(leadId) {
    return axios.get(`${this.url}/${leadId}/notes`);
  }

  createNote(leadId, body) {
    return axios.post(`${this.url}/${leadId}/notes`, { body });
  }

  getDossie(leadId) {
    return axios.get(`${this.url}/${leadId}/dossie`);
  }

  simulate(leadId, payload) {
    return axios.post(`${this.url}/${leadId}/simulacao`, payload);
  }

  painel(leadId, payload) {
    return axios.post(`${this.url}/${leadId}/painel`, payload);
  }

  elegibilidade(leadId, payload) {
    return axios.post(`${this.url}/${leadId}/elegibilidade`, payload);
  }

  pensao(leadId, payload) {
    return axios.post(`${this.url}/${leadId}/pensao`, payload);
  }

  maternidade(leadId, payload) {
    return axios.post(`${this.url}/${leadId}/maternidade`, payload);
  }

  uploadCnis(leadId, file, sexo, { excluirSeqs = '', mensalidades = '' } = {}) {
    const data = new FormData();
    data.append('arquivo', file);
    data.append('sexo', sexo);
    if (excluirSeqs) data.append('excluir_seqs', excluirSeqs);
    if (mensalidades) data.append('mensalidades', mensalidades);
    return axios.post(`${this.url}/${leadId}/cnis`, data);
  }

  getCnis(leadId) {
    return axios.get(`${this.url}/${leadId}/cnis`);
  }

  deleteCnis(leadId) {
    return axios.delete(`${this.url}/${leadId}/cnis`);
  }

  // Troca o sexo do segurado guardado no CNIS (sem reanexar o PDF).
  trocarSexoCnis(leadId, sexo) {
    return axios.patch(`${this.url}/${leadId}/cnis`, { sexo });
  }

  liquidacao(leadId, payload) {
    return axios.post(`${this.url}/${leadId}/liquidacao`, payload);
  }

  liquidacaoPdf(leadId, payload) {
    return axios.post(`${this.url}/${leadId}/liquidacao/pdf`, payload, {
      responseType: 'blob',
    });
  }

  planejamento(leadId, payload) {
    return axios.post(`${this.url}/${leadId}/planejamento`, payload);
  }

  planejamentoPdf(leadId, payload) {
    return axios.post(`${this.url}/${leadId}/planejamento/pdf`, payload, {
      responseType: 'blob',
    });
  }

  createZapsign(leadId, templateId, regenerar = false) {
    return axios.post(`${this.url}/${leadId}/zapsign`, {
      template_id: templateId,
      regenerar,
    });
  }

  zapsignTemplates() {
    return axios.get(`${this.url}/zapsign_templates`);
  }

  zapsignPreview(leadId) {
    return axios.get(`${this.url}/${leadId}/zapsign/preview`);
  }

  saveZapsignDados(leadId, dados) {
    return axios.put(`${this.url}/${leadId}/zapsign/dados`, dados);
  }

  zapsignCep(cep) {
    return axios.get(`${this.url}/zapsign_cep`, { params: { cep } });
  }

  portalLink(leadId) {
    return axios.post(`${this.url}/${leadId}/portal_link`);
  }

  followUpDraft(leadId) {
    return axios.post(`${this.url}/${leadId}/follow_up_draft`);
  }

  // resultado: 'qualificada' | 'nao_qualificada' (Closer, base do prêmio do SDR)
  // taskId: a reunião que o "Feito" está fechando (sem ele, o backend fecha
  // a aberta mais antiga até hoje)
  registrarReuniao(leadId, resultado, taskId) {
    return axios.post(`${this.url}/${leadId}/reuniao`, {
      resultado,
      ...(taskId ? { task_id: taskId } : {}),
    });
  }

  // Reunião marcada pelo painel: mesmo efeito do Cal.com (etapa, Closer,
  // rascunho de confirmação nas notas, lembretes internos). Nada vai ao cliente.
  // force: marca mesmo com outra reunião aberta (sem ele o backend dá 409)
  agendarReuniao(leadId, { startsAt, title, force }) {
    return axios.post(`${this.url}/${leadId}/reuniao_agendada`, {
      starts_at: startsAt,
      title,
      ...(force ? { force: true } : {}),
    });
  }

  encaminharComercial(conversationId) {
    return axios.post(`${this.url}/encaminhar_comercial`, {
      conversation_id: conversationId,
    });
  }
}

export default new LeadsAPI();
