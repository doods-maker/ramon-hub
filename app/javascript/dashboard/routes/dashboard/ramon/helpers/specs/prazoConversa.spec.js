import { prazoDaConversa } from '../prazoConversa';

const inbox = { auto_create_lead: true, first_response_sla_minutes: null };
const criada = 1759496400; // 2025-10-03T13:00:00Z em segundos

describe('prazoDaConversa', () => {
  it('criação + 5 min por padrão', () => {
    expect(
      prazoDaConversa({ created_at: criada, first_reply_created_at: 0 }, inbox)
    ).toBe('2025-10-03T13:05:00.000Z');
  });

  it('usa o SLA da caixa', () => {
    expect(
      prazoDaConversa(
        { created_at: criada, first_reply_created_at: 0 },
        { ...inbox, first_response_sla_minutes: 60 }
      )
    ).toBe('2025-10-03T14:00:00.000Z');
  });

  it('respondida (número ou ISO do websocket) ou caixa sem lead → null', () => {
    expect(
      prazoDaConversa(
        { created_at: criada, first_reply_created_at: criada + 30 },
        inbox
      )
    ).toBeNull();
    expect(
      prazoDaConversa(
        { created_at: criada, first_reply_created_at: '2025-10-03T13:01:00Z' },
        inbox
      )
    ).toBeNull();
    expect(
      prazoDaConversa(
        { created_at: criada, first_reply_created_at: null },
        { auto_create_lead: false }
      )
    ).toBeNull();
  });
});
