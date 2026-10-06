// Lead no card da lista de conversas (FORK ramon): linha "Etapa · Tese ·
// Responsável" e as etiquetas espelhadas do lead (fase-*, tese-*), que saem do
// card quando a linha aparece — senão a mesma informação aparece duas vezes.
const ETIQUETA_DO_LEAD = /^(fase|tese)-/;

export const semEtiquetasDoLead = (labels, lead) =>
  lead
    ? (labels || []).filter(label => !ETIQUETA_DO_LEAD.test(label))
    : labels || [];

// Responsável = Closer quando já tem (a venda está com ele), senão o SDR.
export const partesDaLinha = lead =>
  [
    lead?.stage_name,
    lead?.thesis_name,
    lead?.closer_name || lead?.sdr_name,
  ].filter(Boolean);
