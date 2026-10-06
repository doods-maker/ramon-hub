// Rascunho do "Cobrar pendentes" (painel do lead e Pós-venda): o mesmo texto
// nos dois lugares. Só monta o texto — quem envia é sempre uma pessoa.
export const docChargeDraft = (t, name, titles) =>
  [
    t('RAMON.DOCS.DRAFT.GREETING', { name: name || '' }),
    '',
    ...titles.map(item => t('RAMON.DOCS.DRAFT.ITEM', { item })),
    '',
    t('RAMON.DOCS.DRAFT.CLOSING'),
  ].join('\n');
