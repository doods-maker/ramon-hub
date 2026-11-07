/* global axios */
import ApiClient from '../ApiClient';

class CaptainAssistant extends ApiClient {
  constructor() {
    super('captain/assistants', { accountScoped: true });
  }

  get({ page = 1, searchKey } = {}) {
    return axios.get(this.url, {
      params: {
        page,
        searchKey,
      },
    });
  }

  // ramon (roteiro F2): roteiro = { thesis_id, estado } quando o Testar escolheu uma tese.
  playground({ assistantId, messageContent, messageHistory, roteiro }) {
    return axios.post(`${this.url}/${assistantId}/playground`, {
      message_content: messageContent,
      message_history: messageHistory,
      ...(roteiro ? { roteiro } : {}),
    });
  }

  stats() {
    return axios.get(`${this.url}/stats`);
  }

  // ramon: "Testar pergunta" (I-FQ2) — mesma busca do faq_lookup.
  // thesisId = buscar como para um lead dessa tese (vazio = lead sem tese: todas).
  buscarFaq(assistantId, pergunta, thesisId = null) {
    return axios.get(`${this.url}/${assistantId}/buscar_faq`, {
      params: { q: pergunta, thesis_id: thesisId || undefined },
    });
  }

  // ramon: texto final que o assistente recebe (I-CF6).
  textoFinal(assistantId) {
    return axios.get(`${this.url}/${assistantId}/texto_final`);
  }

  // ramon (Etapa Documentos): imagens do passo a passo, uma por tema.
  passosAPasso(assistantId) {
    return axios.get(`${this.url}/${assistantId}/passos_a_passo`);
  }

  subirPassoAPasso(assistantId, tema, arquivo) {
    const corpo = new FormData();
    corpo.append('tema', tema);
    corpo.append('file', arquivo);
    return axios.post(`${this.url}/${assistantId}/passos_a_passo`, corpo);
  }

  removerPassoAPasso(assistantId, tema) {
    return axios.delete(`${this.url}/${assistantId}/passos_a_passo/${tema}`);
  }
}

export default new CaptainAssistant();
