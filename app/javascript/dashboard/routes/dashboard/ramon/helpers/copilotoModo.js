export const MODOS = ['manual', 'rascunho', 'piloto_limitado', 'piloto_total'];

export const modoDefault = () => {
  const m = window.chatwootConfig?.ramonCopilotoModoDefault;
  return MODOS.includes(m) ? m : 'rascunho';
};

// Fonte unica do modo efetivo da conversa no front (espelha Ramon::CopilotoModo.of).
export const copilotoModoDe = chat => {
  const m = chat?.custom_attributes?.copiloto_modo;
  return MODOS.includes(m) ? m : modoDefault();
};
