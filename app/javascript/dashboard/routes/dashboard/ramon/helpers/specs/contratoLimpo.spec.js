import { contratoLimpoStatus } from '../contratoLimpo';

const agora = new Date('2026-11-10T12:00:00Z').getTime();

describe('contratoLimpoStatus', () => {
  it('lead sem assinatura não tem selo', () => {
    expect(contratoLimpoStatus({ won_at: null }, agora)).toBeNull();
  });

  it('carimbado = limpo', () => {
    expect(
      contratoLimpoStatus({ won_at: 'x', contrato_limpo_em: 'y' }, agora)
    ).toEqual({ key: 'LIMPO' });
  });

  it('checklist incompleta conta os docs que faltam', () => {
    const lead = {
      won_at: '2026-11-01T12:00:00Z',
      docs_total: 5,
      docs_received: 3,
    };
    expect(contratoLimpoStatus(lead, agora)).toEqual({
      key: 'FALTAM_DOCS',
      count: 2,
    });
  });

  it('lead sem checklist avisa', () => {
    expect(
      contratoLimpoStatus(
        { won_at: '2026-11-01T12:00:00Z', docs_total: 0 },
        agora
      )
    ).toEqual({ key: 'SEM_CHECKLIST' });
  });

  it('docs completos: dias até assinatura + 7', () => {
    const lead = {
      won_at: '2026-11-08T12:00:00Z',
      docs_completos_em: '2026-11-09T12:00:00Z',
    };
    expect(contratoLimpoStatus(lead, agora)).toEqual({
      key: 'EM_DIAS',
      count: 5,
    });
  });
});
