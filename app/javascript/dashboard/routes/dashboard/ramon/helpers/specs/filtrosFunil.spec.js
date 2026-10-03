import {
  FILTROS_FUNIL,
  ORDEM_FILTRO,
  contarFiltros,
  pctConsumido,
} from '../filtrosFunil';

const ganho = (received, total, wonAt = '2026-09-01T10:00:00Z') => ({
  won_at: wonAt,
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

  it('prescrição: critério do Radar (sangrando ou > 50% do prazo), sem ganhos', () => {
    const { prescricao } = FILTROS_FUNIL;
    expect(prescricao({ dcb_em: '2019-01-10' })).toBe(true); // já perde parcelas
    expect(prescricao({ dcb_em: '2023-01-10' })).toBe(true); // 44 meses (73%)
    expect(prescricao({ dcb_em: '2024-06-10' })).toBe(false); // 27 meses (45%)
    expect(prescricao({ dcb_em: null })).toBe(false);
    expect(prescricao({ dcb_em: '2019-01-10', won_at: '2026-09-01' })).toBe(
      false
    );
  });

  it('prescrição inclui lead perdido com DCB (o prazo continua correndo)', () => {
    expect(
      FILTROS_FUNIL.prescricao({
        dcb_em: '2019-01-10',
        lost_at: '2026-05-01T10:00:00Z',
      })
    ).toBe(true);
  });

  it('ordena pós-venda do ganho mais antigo e radar por sangramento', () => {
    const novo = ganho(1, 2, '2026-09-20T10:00:00Z');
    const antigo = ganho(1, 2, '2026-08-01T10:00:00Z');
    expect([novo, antigo].sort(ORDEM_FILTRO.pos_venda)).toEqual([antigo, novo]);
    const muito = { id: 1, dcb_em: '2018-01-10', benefit_monthly_value: 1000 };
    const pouco = { id: 2, dcb_em: '2020-06-10', benefit_monthly_value: 1000 };
    const risco = { id: 3, dcb_em: '2022-01-10' };
    expect(
      [risco, pouco, muito].sort(ORDEM_FILTRO.prescricao).map(l => l.id)
    ).toEqual([1, 2, 3]);
  });

  it('pctConsumido arredonda e trava em 100', () => {
    expect(pctConsumido({ dcb_em: '2023-01-10' })).toBe(73);
    expect(pctConsumido({ dcb_em: '2018-01-10' })).toBe(100);
    expect(pctConsumido({})).toBeNull();
  });

  it('conta os dois filtros', () => {
    expect(
      contarFiltros([ganho(1, 2), ganho(2, 2), { dcb_em: '2019-01-10' }])
    ).toEqual({ posVenda: 1, prescricao: 1 });
  });
});
