import { prescriptionInfo, PRESCRIPTION_WINDOW_MONTHS } from './prescription';

// Pós-venda e Radar viraram filtros do funil (redesign v2, Onda 5), calculados
// sobre o payload slim. Pós-venda = mesma regra do LeadRadar.pos_venda (ganho
// com checklist de documentos e algum faltando). Prescrição = mesmo critério
// do RamonPrescriptionRadarController: DCB conhecida, fora os ganhos (perdidos
// entram — o prazo deles continua correndo), já sangrando OU mais da metade
// dos 60 meses consumida.
const emPosVenda = lead =>
  !!lead.won_at && lead.docs_total > 0 && lead.docs_received < lead.docs_total;

const consumido = info =>
  Math.min(info.monthsSinceDcb / PRESCRIPTION_WINDOW_MONTHS, 1);

const emPrescricao = lead => {
  if (lead.won_at) return false;
  const info = prescriptionInfo(lead);
  return !!info && (info.lostInstallments > 0 || consumido(info) > 0.5);
};

export const FILTROS_FUNIL = {
  pos_venda: emPosVenda,
  prescricao: emPrescricao,
};

// Ordem de cada filtro: pós-venda do ganho mais antigo pro mais novo; radar
// por sangramento (valor perdido, depois % do prazo consumido).
const sangramento = lead => {
  const info = prescriptionInfo(lead);
  return [info?.lostValue || 0, info ? consumido(info) : 0];
};
export const ORDEM_FILTRO = {
  pos_venda: (a, b) => new Date(a.won_at) - new Date(b.won_at),
  prescricao: (a, b) => {
    const [perdaA, pctA] = sangramento(a);
    const [perdaB, pctB] = sangramento(b);
    return perdaB - perdaA || pctB - pctA;
  },
};

export const pctConsumido = lead => {
  const info = prescriptionInfo(lead);
  return info ? Math.round(consumido(info) * 100) : null;
};

export const contarFiltros = leads => ({
  posVenda: leads.filter(emPosVenda).length,
  prescricao: leads.filter(emPrescricao).length,
});
