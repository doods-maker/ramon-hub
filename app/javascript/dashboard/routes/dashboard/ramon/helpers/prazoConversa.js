// Prazo de 1ª resposta na lista de conversas (mesma regra de Ramon::Cadencia:
// SLA da caixa, padrão 5 min; só em caixa que cria lead; some quando respondida).
// first_reply_created_at: 0 na API, null/ISO no websocket — falsy = sem resposta.
// Só conversa aberta/pendente e até 24 h depois do prazo: depois disso o
// selo "+1234:56" não ajuda ninguém — o card volta a mostrar a hora.
const PADRAO_MINUTOS = 5;
const JANELA_MS = 24 * 60 * 60 * 1000;
const ATIVAS = ['open', 'pending'];

export const prazoDaConversa = (chat, inbox, agora = Date.now()) => {
  if (!inbox?.auto_create_lead || !chat?.created_at) return null;
  if (chat.first_reply_created_at || !ATIVAS.includes(chat.status)) return null;
  const minutos = inbox.first_response_sla_minutes || PADRAO_MINUTOS;
  const prazo = (chat.created_at + minutos * 60) * 1000;
  if (agora > prazo + JANELA_MS) return null;
  return new Date(prazo).toISOString();
};
