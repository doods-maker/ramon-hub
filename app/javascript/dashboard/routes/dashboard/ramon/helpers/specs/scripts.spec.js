import { preencherScript } from '../scripts';

describe('preencherScript', () => {
  it('troca {{nome}} pelo primeiro nome do contato', () => {
    expect(
      preencherScript('Olá {{nome}}, tudo bem?', {
        contact_name: 'Maria Aparecida Souza',
        name: 'Lead 123',
      })
    ).toBe('Olá Maria, tudo bem?');
  });

  it('aceita {{ nome }} com espaços e várias ocorrências', () => {
    expect(
      preencherScript('{{ nome }}, certo? Obrigado, {{nome}}!', {
        name: 'José Ribeiro',
      })
    ).toBe('José, certo? Obrigado, José!');
  });

  it('sem nome mantém o marcador', () => {
    expect(preencherScript('Olá {{nome}}!', { name: '  ' })).toBe(
      'Olá {{nome}}!'
    );
    expect(preencherScript('Olá {{nome}}!', null)).toBe('Olá {{nome}}!');
  });
});
