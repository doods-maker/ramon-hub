// FAQs e Documentos são do assistente que fala com o lead (I-FQ5): o primeiro com caixa conectada; sem
// nenhum, o que tem mais FAQs aprovadas. null = conta sem assistente. Entrada = captain/assistants/stats.
export const assistenteDasFaqs = (stats = []) =>
  stats.find(item => item.publico === 'lead') ||
  [...stats].sort((a, b) => b.faqs_aprovadas - a.faqs_aprovadas)[0] ||
  null;

export const ROTAS_DAS_FAQS = [
  'captain_assistants_responses_index',
  'captain_assistants_documents_index',
];
