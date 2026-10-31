import { defineStore } from 'pinia';
import ChatAPI from 'dashboard/api/ramonChat';

// Equipe · chat interno (Fatia 2). Carregado no Dashboard (badge no menu em
// qualquer tela); mensagens chegam por ramon.chat.message (actionCable.js).
export const useChatStore = defineStore('chat', {
  state: () => ({
    canais: [],
    admin: false,
    mensagens: {}, // canalId → [mensagem] (só dos canais já abertos)
    mais: {}, // canalId → há página anterior
    abertoId: null,
  }),

  getters: {
    totalNaoLidas: state => state.canais.reduce((s, c) => s + c.nao_lidas, 0),
    aberto: state => state.canais.find(c => c.id === state.abertoId),
  },

  actions: {
    async carregar() {
      const { data } = await ChatAPI.get();
      this.canais = data.payload;
      this.admin = data.admin;
    },
    async abrir(id) {
      this.abertoId = id;
      const { data } = await ChatAPI.mensagens(id);
      this.mensagens[id] = data.payload;
      this.mais[id] = data.mais;
      this.marcarLido(id);
    },
    fechar() {
      this.abertoId = null;
    },
    async anteriores(id) {
      const { data } = await ChatAPI.mensagens(id, this.mensagens[id][0]?.id);
      this.mensagens[id] = [...data.payload, ...this.mensagens[id]];
      this.mais[id] = data.mais;
    },
    marcarLido(id) {
      const canal = this.canais.find(c => c.id === id);
      if (!canal?.participante) return;
      canal.nao_lidas = 0;
      ChatAPI.ler(id).catch(() => {});
    },
    async enviar(conteudo) {
      const { data } = await ChatAPI.enviar(this.abertoId, conteudo);
      this.adicionar(data);
    },
    async direto(userId) {
      const { data } = await ChatAPI.direto(userId);
      if (!this.canais.some(c => c.id === data.id)) this.canais.push(data);
      await this.abrir(data.id);
    },
    adicionar(msg) {
      const lista = this.mensagens[msg.canal_id];
      if (lista && !lista.some(m => m.id === msg.id)) lista.push(msg);
    },
    // Reconexão do websocket: o que chegou enquanto caiu.
    async recarregar() {
      await this.carregar();
      if (this.abertoId) await this.abrir(this.abertoId);
    },
    // true = avisar (som + notificação): é de outra pessoa, num canal de que
    // participo e fora da conversa à vista. Admin lendo canal alheio não é avisado.
    async receber(msg, meuId) {
      const novo = !this.canais.some(c => c.id === msg.canal_id);
      if (novo) await this.carregar(); // 1:1 que alguém acabou de abrir comigo
      this.adicionar(msg);
      const canal = this.canais.find(c => c.id === msg.canal_id);
      if (!canal?.participante || msg.autor.id === meuId) return false;
      if (
        canal.id === this.abertoId &&
        document.visibilityState === 'visible'
      ) {
        this.marcarLido(canal.id);
        return false;
      }
      if (!novo) canal.nao_lidas += 1; // carregar() já contou
      return true;
    },
  },
});

// Aviso discreto (D8): som curto + notificação do sistema que some sozinha.
export const avisarMensagem = msg => {
  new Audio('/audio/dashboard/ding.mp3').play().catch(() => {});
  if (!('Notification' in window) || Notification.permission !== 'granted')
    return;
  const n = new Notification(msg.autor.name, {
    body: msg.conteudo,
    tag: `chat-${msg.canal_id}`,
  });
  n.onclick = () => {
    window.focus();
    n.close();
  };
};
