import { defineStore } from 'pinia';
import EquipeAPI from 'dashboard/api/ramonEquipe';
import { textoLimpo } from 'dashboard/routes/dashboard/ramon/helpers/equipe';

// Equipe · chat interno como caixa do Chatwoot (ADR 0011). Guarda a caixa e as
// não-lidas da pessoa (badge do menu) e dá o aviso discreto: o servidor só cria
// a notificação de mensagem para quem participa da conversa (aviso nativo).
const TIPOS_AVISO = [
  'participating_conversation_new_message',
  'conversation_mention',
];

export const useEquipeStore = defineStore('equipe', {
  state: () => ({
    inboxId: null,
    naoLidas: 0,
    carregado: false,
    participantes: {},
  }),

  actions: {
    async carregar() {
      const { data } = await EquipeAPI.get();
      this.inboxId = data.inbox_id;
      this.naoLidas = data.nao_lidas;
      this.carregado = true;
    },
    // last_seen_at vem em segundos (nulo = nunca leu).
    async carregarParticipantes(conversationId) {
      const { data } = await EquipeAPI.participantes(conversationId);
      this.participantes[conversationId] = data.map(p => ({
        id: p.id,
        name: p.name,
        thumbnail: p.thumbnail,
        lastSeenAt: p.last_seen_at ?? null,
      }));
    },
    atualizarLeitura({ conversationId, userId, lastSeenAt }) {
      const pessoa = this.participantes[conversationId]?.find(
        p => p.id === userId
      );
      if (pessoa) pessoa.lastSeenAt = lastSeenAt;
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
        const nome = mensagem.sender?.name;
        const marcou = notificacao.notification_type === 'conversation_mention';
        // ponytail: texto fixo em PT-BR; o store não alcança o i18n (instância criada na entrypoint).
        const autor = marcou && nome ? `${nome} te marcou` : nome;
        // Na 1:1 o contato é sintético ("Ana e Bia"): fica só quem escreveu.
        const canal =
          conversa.equipe_tipo === '1a1' ? null : conversa.meta?.sender?.name;
        const n = new Notification([autor, canal].filter(Boolean).join(' · '), {
          body: textoLimpo(mensagem.content),
          tag: `equipe-${conversa.id}`,
        });
        n.onclick = () => {
          window.focus();
          n.close();
        };
      }
      return true;
    },
  },
});
