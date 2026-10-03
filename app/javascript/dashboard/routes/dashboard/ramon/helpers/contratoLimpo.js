// Selo do contrato limpo (regulamento §2: assinado + checklist completa + 7
// dias sem cancelamento). O carimbo oficial vem do job horário do backend;
// aqui só se descreve o caminho até ele. null = lead ainda não assinou.
const DIA_MS = 24 * 60 * 60 * 1000;

export const contratoLimpoStatus = (lead, agora = Date.now()) => {
  if (!lead?.won_at) return null;
  if (lead.contrato_limpo_em) return { key: 'LIMPO' };
  if (!lead.docs_completos_em) {
    const faltam = (lead.docs_total || 0) - (lead.docs_received || 0);
    return lead.docs_total
      ? { key: 'FALTAM_DOCS', count: faltam }
      : { key: 'SEM_CHECKLIST' };
  }
  const limpoEm = Math.max(
    new Date(lead.won_at).getTime() + 7 * DIA_MS,
    new Date(lead.docs_completos_em).getTime()
  );
  return {
    key: 'EM_DIAS',
    count: Math.max(Math.ceil((limpoEm - agora) / DIA_MS), 0),
  };
};
