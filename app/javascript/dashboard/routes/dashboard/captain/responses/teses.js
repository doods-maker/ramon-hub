// Teses das FAQs (I-FQ1, revisto 20/10/2026): as teses reais da conta (store theses, a lista do Playbooks — tese nova
// aparece sozinha) + Geral (vale para todo caso) + Sem tese. Filtro da tela (Ramon::FaqTeses.filtrar): id, 'geral' ou 'sem'.
export const GERAL = 'geral';
export const SEM_TESE = 'sem';

// Rótulos da FAQ: o de Geral ou os nomes das teses dela, na ordem do Playbooks (tese apagada some).
export const rotulosDaFaq = (faq, teses, rotuloGeral) =>
  faq.geral
    ? [rotuloGeral]
    : teses.filter(x => faq.thesis_ids?.includes(x.id)).map(x => x.name);
