// Fallback neutro (cinza puro, visual branco e preto 03/10/2026) para etapa sem cor.
export const DEFAULT_STAGE_COLOR = '#737373';

// Etiquetas fase-* espelham a etapa do lead (Ramon::StageLabelSync); na lista de
// conversas a etapa já aparece como pílula própria, então elas somem do card.
export const semEtiquetaDeFase = titulos =>
  (titulos || []).filter(titulo => !titulo.startsWith('fase-'));
