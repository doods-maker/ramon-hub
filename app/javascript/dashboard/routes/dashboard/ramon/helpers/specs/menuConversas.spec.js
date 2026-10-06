import { enxugarMenuConversas } from '../menuConversas';

const menu = (labels, pastas = []) => [
  { name: 'Inbox' },
  {
    name: 'Conversation',
    children: [
      { name: 'All' },
      { name: 'Mentions' },
      { name: 'Participating' },
      { name: 'Unattended' },
      { name: 'Folders', children: pastas },
      { name: 'Teams', children: [{ label: 'sdr' }] },
      { name: 'Channels', children: [{ label: 'WhatsApp' }] },
      { name: 'Labels', children: labels.map(label => ({ label })) },
    ],
  },
];

const conversas = lista => lista.find(i => i.name === 'Conversation').children;
const nomes = lista => conversas(lista).map(i => i.name);

describe('enxugarMenuConversas', () => {
  it('admin vê o menu inteiro', () => {
    const original = menu(['fase-qualificacao']);
    expect(enxugarMenuConversas(original, { isAdmin: true })).toBe(original);
  });

  it('atendente: sem Participando, Times, pasta vazia e etiquetas só automáticas', () => {
    const enxuto = enxugarMenuConversas(
      menu(['fase-qualificacao', 'tese-auxilio-acidente']),
      { isAdmin: false }
    );
    expect(nomes(enxuto)).toEqual([
      'All',
      'Mentions',
      'Unattended',
      'Channels',
    ]);
    expect(enxuto[0]).toEqual({ name: 'Inbox' });
  });

  it('atendente vê pastas existentes e etiquetas manuais, sem fase-*/tese-*', () => {
    const enxuto = enxugarMenuConversas(
      menu(['fase-negociacao', 'vip', 'tese-bpc'], [{ label: 'Minha' }]),
      { isAdmin: false }
    );
    expect(nomes(enxuto)).toEqual([
      'All',
      'Mentions',
      'Unattended',
      'Folders',
      'Channels',
      'Labels',
    ]);
    expect(conversas(enxuto).at(-1).children).toEqual([{ label: 'vip' }]);
  });
});
