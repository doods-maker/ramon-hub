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

// Entrar no ganho pede valor e dispara a cascata; andar entre etapas de ganho
// (Fechado → Documentos → Jurídico) não é um ganho novo (ADR 0015).
export const entraNoGanho = (destino, origem) =>
  Boolean(destino?.is_won) && !origem?.is_won;

// Ganho que pula Documentos (decisão 07/11): entrar no ganho por outra etapa
// que não Documentos, com a tese marcada "passa pela etapa Documentos" e a
// conta tendo a etapa. A coluna escolhida vale, mas pede o motivo (vai para as
// notas do lead).
const DOCUMENTOS = 'fase-documentos';
export const pulaDocumentos = (destino, origem, lead, etapas) =>
  entraNoGanho(destino, origem) &&
  destino.label !== DOCUMENTOS &&
  Boolean(lead?.thesis_passa_documentos) &&
  (etapas || []).some(e => e.label === DOCUMENTOS && e.is_won);
