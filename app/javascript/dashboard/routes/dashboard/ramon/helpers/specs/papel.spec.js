import { papelDe } from '../papel';

describe('papelDe', () => {
  it('admin é gestor mesmo com time', () => {
    expect(papelDe({ isAdmin: true, nomesDosTimes: ['sdr'] })).toBe('gestor');
  });
  it('recepção com acento, maiúscula e espaço', () => {
    expect(papelDe({ isAdmin: false, nomesDosTimes: [' Recepção '] })).toBe(
      'recepcao'
    );
    expect(papelDe({ isAdmin: false, nomesDosTimes: ['RECEPCAO '] })).toBe(
      'recepcao'
    );
  });
  it('controladoria entra como recepção', () => {
    expect(papelDe({ isAdmin: false, nomesDosTimes: ['controladoria'] })).toBe(
      'recepcao'
    );
  });
  it('closer vence sdr quando a pessoa está nos dois', () => {
    expect(papelDe({ isAdmin: false, nomesDosTimes: ['sdr', 'closer'] })).toBe(
      'closer'
    );
  });
  it('sdr', () => {
    expect(papelDe({ isAdmin: false, nomesDosTimes: ['sdr'] })).toBe('sdr');
  });
  it('advogados vira advogada', () => {
    expect(papelDe({ isAdmin: false, nomesDosTimes: ['advogados'] })).toBe(
      'advogada'
    );
  });
  it('sem time é equipe', () => {
    expect(papelDe({ isAdmin: false, nomesDosTimes: [] })).toBe('equipe');
    expect(papelDe({ isAdmin: false })).toBe('equipe');
  });
});
