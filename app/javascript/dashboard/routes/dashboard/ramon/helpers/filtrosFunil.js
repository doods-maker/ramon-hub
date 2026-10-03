import { prescriptionInfo } from './prescription';

// Pós-venda e Radar viraram filtros do funil (redesign v2, Onda 5), calculados
// sobre o payload slim. Pós-venda = mesma regra do LeadRadar.pos_venda (ganho
// com checklist de documentos e algum faltando); prescrição = o que o Radar
// chama de sangrando ou "em risco 90d" (penhasco em até 3 meses), fora os ganhos.
const emPosVenda = lead =>
  !!lead.won_at && lead.docs_total > 0 && lead.docs_received < lead.docs_total;

const emPrescricao = lead => {
  if (lead.won_at) return false;
  const info = prescriptionInfo(lead);
  return !!info && (info.lostInstallments > 0 || info.monthsToCliff <= 3);
};

export const FILTROS_FUNIL = {
  pos_venda: emPosVenda,
  prescricao: emPrescricao,
};

export const contarFiltros = leads => ({
  posVenda: leads.filter(emPosVenda).length,
  prescricao: leads.filter(emPrescricao).length,
});
