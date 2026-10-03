import { prazoDaConversa } from '../prazoConversa';

const inbox = { auto_create_lead: true, first_response_sla_minutes: null };
const criada = 1759496400; // 2025-10-03T13:00:00Z em segundos
const agora = criada * 1000 + 60 * 1000; // 1 min depois
const aberta = {
  created_at: criada,
  first_reply_created_at: 0,
  status: 'open',
};

describe('prazoDaConversa', () => {
  it('criação + 5 min por padrão', () => {
    expect(prazoDaConversa(aberta, inbox, agora)).toBe(
      '2025-10-03T13:05:00.000Z'
    );
  });

  it('usa o SLA da caixa', () => {
    expect(
      prazoDaConversa(
        aberta,
        { ...inbox, first_response_sla_minutes: 60 },
        agora
      )
    ).toBe('2025-10-03T14:00:00.000Z');
  });

  it('respondida (número ou ISO do websocket) ou caixa sem lead → null', () => {
    expect(
      prazoDaConversa(
        { ...aberta, first_reply_created_at: criada + 30 },
        inbox,
        agora
      )
    ).toBeNull();
    expect(
      prazoDaConversa(
        { ...aberta, first_reply_created_at: '2025-10-03T13:01:00Z' },
        inbox,
        agora
      )
    ).toBeNull();
    expect(
      prazoDaConversa(
        { ...aberta, first_reply_created_at: null },
        { auto_create_lead: false },
        agora
      )
    ).toBeNull();
  });

  it('pendente conta; resolvida ou adiada não', () => {
    expect(
      prazoDaConversa({ ...aberta, status: 'pending' }, inbox, agora)
    ).not.toBeNull();
    expect(
      prazoDaConversa({ ...aberta, status: 'resolved' }, inbox, agora)
    ).toBeNull();
    expect(
      prazoDaConversa({ ...aberta, status: 'snoozed' }, inbox, agora)
    ).toBeNull();
  });

  it('passadas 24 h do prazo → null (o card mostra a hora)', () => {
    const prazo = (criada + 5 * 60) * 1000;
    const dia = 24 * 60 * 60 * 1000;
    expect(prazoDaConversa(aberta, inbox, prazo + dia)).not.toBeNull();
    expect(prazoDaConversa(aberta, inbox, prazo + dia + 1000)).toBeNull();
  });
});
