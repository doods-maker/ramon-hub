import { entraNoGanho } from '../stage';

describe('entraNoGanho', () => {
  it('de etapa aberta (ou desconhecida) para ganho é entrar no ganho', () => {
    expect(entraNoGanho({ is_won: true }, { is_won: false })).toBe(true);
    expect(entraNoGanho({ is_won: true }, undefined)).toBe(true);
  });

  it('de ganho para ganho não é um ganho novo', () => {
    expect(entraNoGanho({ is_won: true }, { is_won: true })).toBe(false);
  });

  it('para etapa que não é de ganho, não', () => {
    expect(entraNoGanho({ is_won: false }, { is_won: false })).toBe(false);
    expect(entraNoGanho(undefined, undefined)).toBe(false);
  });
});
