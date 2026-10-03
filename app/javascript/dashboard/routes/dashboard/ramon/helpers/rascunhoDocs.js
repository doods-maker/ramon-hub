// Rascunho de "Cobrar pendentes" (gaveta do lead e ficha): saudação, um item
// por documento faltando e fecho. Nada é enviado — quem envia é a pessoa.
export const rascunhoCobranca = (t, nome, itens) =>
  [
    t('RAMON.DOCS.DRAFT.GREETING', { name: nome || '' }),
    '',
    ...itens.map(item => t('RAMON.DOCS.DRAFT.ITEM', { item })),
    '',
    t('RAMON.DOCS.DRAFT.CLOSING'),
  ].join('\n');
