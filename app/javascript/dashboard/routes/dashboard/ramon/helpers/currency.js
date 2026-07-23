export const formatBrl = value => {
  if (value === null || value === undefined || value === '') return '';
  return new Intl.NumberFormat('pt-BR', {
    style: 'currency',
    currency: 'BRL',
  }).format(Number(value));
};

// Forma compacta ("R$ 38 mil") para cards e headers de coluna do Kanban.
export const brlCompact = value =>
  new Intl.NumberFormat('pt-BR', {
    style: 'currency',
    currency: 'BRL',
    notation: 'compact',
    maximumFractionDigits: 1,
  }).format(Number(value) || 0);

// pt-BR: com vírgula, pontos são milhar ("1.234,56" → 1234.56);
// sem vírgula, trata como número JS padrão ("1234.56" → 1234.56).
export const parseBrlInput = raw => {
  if (raw === null || raw === undefined) return null;
  const cleaned = String(raw).replace(/[R$\s ]/g, '');
  if (!cleaned) return null;
  const normalized = cleaned.includes(',')
    ? cleaned.replace(/\./g, '').replace(',', '.')
    : cleaned;
  const number = Number(normalized);
  return Number.isNaN(number) ? null : number;
};
