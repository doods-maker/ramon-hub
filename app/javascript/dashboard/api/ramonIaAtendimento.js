/* global axios */
import ApiClient from './ApiClient';

// Tela Como a IA atende (Inteligência): Perfil da IA do padrão, de cada tese e de cada caixa.
// salvar({ padrao, teses: { id: cfg | null }, caixas: { ... } }) troca o cfg inteiro de cada alvo enviado.
class RamonIaAtendimentoAPI extends ApiClient {
  constructor() {
    super('ramon_ia_atendimento', { accountScoped: true });
  }

  get() {
    return axios.get(this.url);
  }

  salvar(alvos) {
    return axios.patch(this.url, alvos);
  }

  // Registro de ações (tipo ia): volta o valor de antes daquela linha só no alvo ('padrao' | 'tese:<id>' | 'caixa:<id>' | 'limites').
  desfazer(auditId, alvo) {
    return axios.post(`${this.url}/desfazer`, { audit_id: auditId, alvo });
  }
}

export default new RamonIaAtendimentoAPI();
