// Limites da legenda do Instagram: 2.200 caracteres e 30 hashtags.
export const LIMITE_CARACTERES = 2200;
export const LIMITE_HASHTAGS = 30;
const PERTO = 0.9; // a partir de 90% do limite: âmbar

// Caracteres por ponto de código (emoji conta 1, não 2 como no .length).
export const contarLegenda = (texto = '') => ({
  caracteres: [...texto].length,
  hashtags: (texto.match(/#[\p{L}\p{N}_]+/gu) || []).length,
});

// slate = folga; amber = perto do limite; ruby = no limite ou acima.
export const tomDoLimite = (valor, limite) => {
  if (valor >= limite) return 'ruby';
  if (valor >= limite * PERTO) return 'amber';
  return 'slate';
};
