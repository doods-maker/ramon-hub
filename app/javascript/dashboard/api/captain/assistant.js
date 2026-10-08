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

  playground({ assistantId, messageContent, messageHistory }) {
    return axios.post(`${this.url}/${assistantId}/playground`, {
      message_content: messageContent,
      message_history: messageHistory,
    });
  }

  stats() {
    return axios.get(`${this.url}/stats`);
  }

  // ramon: "Testar pergunta" (I-FQ2) — mesma busca do faq_lookup.
  buscarFaq(assistantId, pergunta) {
    return axios.get(`${this.url}/${assistantId}/buscar_faq`, {
      params: { q: pergunta },
    });
  }

  // ramon: texto final que o assistente recebe (I-CF6).
  textoFinal(assistantId) {
    return axios.get(`${this.url}/${assistantId}/texto_final`);
  }
}

export default new CaptainAssistant();
