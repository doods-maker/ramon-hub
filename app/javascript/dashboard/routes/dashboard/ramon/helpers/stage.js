// Fallback neutro (cinza puro, visual branco e preto 03/10/2026) para etapa sem cor.
export const DEFAULT_STAGE_COLOR = '#737373';

// SLA de 1º contato só alerta na etapa de entrada (menor position) e nunca em
// ganho/perda. Sem etapas carregadas, não há como saber: vale o alerta.
export const slaApplies = (stageId, stages) => {
  if (!stages?.length) return true;
  const entry = [...stages].sort(
    (a, b) => (a.position ?? 0) - (b.position ?? 0)
  )[0];
  return entry.id === stageId && !entry.is_won && !entry.is_lost;
};
