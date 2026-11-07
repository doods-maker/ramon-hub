// Rascunho do "Cobrar pendentes" (painel do lead e Pós-venda) e do "Pedir
// documentos das lacunas" da colheita: saudação, um item por linha, fecho. O
// texto vem do namespace i18n (cada um com o seu). Só monta — quem envia é
// sempre uma pessoa.
export const docChargeDraft = (t, name, titles, ns = 'RAMON.DOCS.DRAFT') =>
  [
    t(`${ns}.GREETING`, { name: name || '' }),
    '',
    ...titles.map(item => t(`${ns}.ITEM`, { item })),
    '',
    t(`${ns}.CLOSING`),
  ].join('\n');
