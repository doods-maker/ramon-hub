import { formatarKpi, statusKpi } from '../painelTime';

const pct = (alvo, sentido = 'min') => ({ alvo, sentido, unidade: '%' });

describe('statusKpi', () => {
  it.each([
    [75, pct(75), 'ok'],
    [66, pct(75), 'atencao'],
    [65, pct(75), 'atencao'],
    [64.9, pct(75), 'cobrar'],
    [15, pct(15, 'max'), 'ok'],
    [25, pct(15, 'max'), 'atencao'],
    [25.1, pct(15, 'max'), 'cobrar'],
  ])('%s contra %o = %s', (valor, meta, esperado) => {
    expect(statusKpi(valor, meta)).toBe(esperado);
  });

  it('1ª resposta: até 2 min acima da meta é âmbar', () => {
    const meta = { alvo: 5, sentido: 'max', unidade: 'min' };
    expect(statusKpi(4.5, meta)).toBe('ok');
    expect(statusKpi(7, meta)).toBe('atencao');
    expect(statusKpi(7.5, meta)).toBe('cobrar');
  });

  it('contagem sem folga: acima de 0 já é cobrar; sem dado não tem status', () => {
    const meta = { alvo: 0, sentido: 'max', unidade: 'n' };
    expect(statusKpi(0, meta)).toBe('ok');
    expect(statusKpi(1, meta)).toBe('cobrar');
    expect(statusKpi(null, meta)).toBeNull();
  });
});

describe('formatarKpi', () => {
  it('formata por unidade e mostra travessão sem dado', () => {
    expect(formatarKpi(66.7, '%')).toBe('67%');
    expect(formatarKpi(6.5, 'min')).toBe('6,5min');
    expect(formatarKpi(2, 'n')).toBe('2');
    expect(formatarKpi(null, '%')).toBe('—');
  });
});
