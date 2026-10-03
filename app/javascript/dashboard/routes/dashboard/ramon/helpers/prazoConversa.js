// Prazo de 1ª resposta na lista de conversas (mesma regra de Ramon::Cadencia:
// SLA da caixa, padrão 5 min; só em caixa que cria lead; some quando respondida).
// first_reply_created_at: 0 na API, null/ISO no websocket — falsy = sem resposta.
const PADRAO_MINUTOS = 5;

export const prazoDaConversa = (chat, inbox) => {
  if (!inbox?.auto_create_lead || !chat?.created_at) return null;
  if (chat.first_reply_created_at) return null;
  const minutos = inbox.first_response_sla_minutes || PADRAO_MINUTOS;
  return new Date((chat.created_at + minutos * 60) * 1000).toISOString();
};
