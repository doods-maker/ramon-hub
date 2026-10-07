// Assistente do painel do Copiloto: o que a pessoa escolheu → o da equipe (ramon A4: atalhos da banca
// e skills do Copiloto do Escritório) → o da caixa da conversa (como era) → o primeiro.
export const escolherAssistente = ({
  assistants,
  preferredId,
  equipeIds,
  inboxAssistantId,
}) =>
  assistants.find(a => a.id === preferredId) ||
  assistants.find(a => equipeIds.includes(a.id)) ||
  assistants.find(a => a.id === inboxAssistantId) ||
  assistants[0];
