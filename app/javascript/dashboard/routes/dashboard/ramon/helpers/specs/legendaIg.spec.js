import { describe, it, expect } from 'vitest';
import { contarLegenda, tomDoLimite } from '../legendaIg';

describe('legendaIg', () => {
  it('conta caracteres por ponto de código e hashtags', () => {
    expect(contarLegenda('Oi 🤔 #inss #auxílioAcidente #')).toEqual({
      caracteres: 29,
      hashtags: 2,
    });
    expect(contarLegenda()).toEqual({ caracteres: 0, hashtags: 0 });
  });

  it('fica âmbar a partir de 90% e ruby no limite', () => {
    expect(tomDoLimite(1979, 2200)).toBe('slate');
    expect(tomDoLimite(1980, 2200)).toBe('amber');
    expect(tomDoLimite(2200, 2200)).toBe('ruby');
    expect(tomDoLimite(27, 30)).toBe('amber');
    expect(tomDoLimite(31, 30)).toBe('ruby');
  });
});
