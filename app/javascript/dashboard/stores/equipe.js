import { defineStore } from 'pinia';
import EquipeAPI from 'dashboard/api/ramonEquipe';

// Equipe · chat interno como caixa do Chatwoot (ADR 0011). Guarda a caixa e as
// não-lidas da pessoa (badge do menu) e dá o aviso discreto: o servidor só cria
// a notificação de mensagem para quem participa da conversa (aviso nativo).
const TIPOS_AVISO = [
  'participating_conversation_new_message',
  'conversation_mention',
];

export const useEquipeStore = defineStore('equipe', {
  state: () => ({ inboxId: null, naoLidas: 0, carregado: false }),

  actions: {
    async carregar() {
      const { data } = await EquipeAPI.get();
      this.inboxId = data.inbox_id;
      this.naoLidas = data.nao_lidas;
      this.carregado = true;
    },
    // true = avisou (som + notificação do sistema). Quem está com a conversa
    // aberta e à vista não é avisado. Na Intranet o menu de Conversas (que
    // carrega a caixa) não está montado — carrega aqui na 1ª notificação.
    async avisar(notificacao) {
      const conversa = notificacao?.primary_actor;
      if (!TIPOS_AVISO.includes(notificacao?.notification_type)) return false;
      if (!this.carregado) await this.carregar().catch(() => {});
      if (!this.inboxId || conversa?.inbox_id !== this.inboxId) return false;
      this.carregar().catch(() => {});
      const aberta =
        document.visibilityState === 'visible' &&
        window.location.pathname.endsWith(`/conversations/${conversa.id}`);
      if (aberta) return false;
      new Audio('/audio/dashboard/ding.mp3').play().catch(() => {});
      if ('Notification' in window && Notification.permission === 'granted') {
        const mensagem = notificacao.secondary_actor || {};
        const canal = conversa.meta?.sender?.name;
        const n = new Notification(
          [mensagem.sender?.name, canal].filter(Boolean).join(' · '),
          { body: mensagem.content || '', tag: `equipe-${conversa.id}` }
        );
        n.onclick = () => {
          window.focus();
          n.close();
        };
      }
      return true;
    },
  },
});
