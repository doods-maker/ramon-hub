// Menu "Conversas" enxuto para quem atende (decisão Eduardo 06/10). Admin vê
// tudo. SDR, Closer e atendentes ficam sem "Participando" (repete o Minhas)
// e sem Times; Pastas só se existir alguma; Etiquetas sem as automáticas
// fase-*/tese-* (seguem no filtro e no card), e a seção some se ficar vazia.
const AUTOMATICA = /^(fase|tese)-/;
const FORA = ['Participating', 'Teams'];

const enxugar = itens =>
  itens
    .filter(item => !FORA.includes(item.name))
    .map(item =>
      item.name === 'Labels'
        ? {
            ...item,
            children: item.children.filter(c => !AUTOMATICA.test(c.label)),
          }
        : item
    )
    .filter(
      item => !['Folders', 'Labels'].includes(item.name) || item.children.length
    );

export const enxugarMenuConversas = (menu, { isAdmin }) =>
  isAdmin
    ? menu
    : menu.map(item =>
        item.name === 'Conversation'
          ? { ...item, children: enxugar(item.children) }
          : item
      );
