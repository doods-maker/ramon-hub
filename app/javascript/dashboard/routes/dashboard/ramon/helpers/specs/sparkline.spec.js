import { describe, it, expect } from 'vitest';
import { sparklinePath } from '../sparkline';

describe('sparklinePath', () => {
  it('retorna vazio com menos de 2 pontos', () => {
    expect(sparklinePath([])).toBe('');
    expect(sparklinePath([5])).toBe('');
  });

  it('começa com M e usa L para os demais pontos', () => {
    const d = sparklinePath([1, 2, 3], { width: 200, height: 40 });
    expect(d.startsWith('M')).toBe(true);
    expect((d.match(/L/g) || []).length).toBe(2);
  });

  it('mapeia o maior valor para o topo (y=0) e o menor para a base', () => {
    const d = sparklinePath([0, 10], { width: 100, height: 40 });
    // último ponto (valor 10 = máximo) encosta no topo: y = 0.0
    expect(d.endsWith('0.0')).toBe(true);
  });
});
