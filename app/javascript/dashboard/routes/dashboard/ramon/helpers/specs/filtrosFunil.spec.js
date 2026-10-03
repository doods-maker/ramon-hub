import { FILTROS_FUNIL, contarFiltros } from '../filtrosFunil';

const ganho = (received, total) => ({
  won_at: '2026-09-01T10:00:00Z',
  docs_received: received,
  docs_total: total,
});

describe('filtrosFunil', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date(2026, 9, 3));
  });
  afterEach(() => vi.useRealTimers());

  it('pós-venda: só ganho com documento faltando', () => {
    const { pos_venda: posVenda } = FILTROS_FUNIL;
    expect(posVenda(ganho(3, 5))).toBe(true);
    expect(posVenda(ganho(5, 5))).toBe(false);
    expect(posVenda(ganho(0, 0))).toBe(false);
    expect(posVenda({ won_at: null, docs_received: 1, docs_total: 5 })).toBe(
      false
    );
  });

  it('prescrição: sangrando ou penhasco em até 3 meses, nunca ganho', () => {
    const { prescricao } = FILTROS_FUNIL;
    expect(prescricao({ dcb_em: '2019-01-10' })).toBe(true); // já perde parcelas
    expect(prescricao({ dcb_em: '2021-12-10' })).toBe(true); // 2 meses pro penhasco
    expect(prescricao({ dcb_em: '2024-01-10' })).toBe(false);
    expect(prescricao({ dcb_em: null })).toBe(false);
    expect(prescricao({ dcb_em: '2019-01-10', won_at: '2026-09-01' })).toBe(
      false
    );
  });

  it('conta os dois filtros', () => {
    expect(
      contarFiltros([ganho(1, 2), ganho(2, 2), { dcb_em: '2019-01-10' }])
    ).toEqual({ posVenda: 1, prescricao: 1 });
  });
});
