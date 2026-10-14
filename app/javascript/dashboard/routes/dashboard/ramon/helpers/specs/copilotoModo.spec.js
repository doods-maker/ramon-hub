import { copilotoModoDe, modoDefault, tomDoModo } from '../copilotoModo';
import { TOM } from '../ui';

describe('copilotoModo', () => {
  afterEach(() => {
    delete window.chatwootConfig;
  });
  it('cai em rascunho sem config', () => {
    expect(modoDefault()).toBe('rascunho');
    expect(copilotoModoDe({})).toBe('rascunho');
  });
  it('usa o default da config e ignora invalido', () => {
    window.chatwootConfig = { ramonCopilotoModoDefault: 'piloto_limitado' };
    expect(copilotoModoDe({ custom_attributes: {} })).toBe('piloto_limitado');
    expect(
      copilotoModoDe({ custom_attributes: { copiloto_modo: 'xablau' } })
    ).toBe('piloto_limitado');
    window.chatwootConfig = { ramonCopilotoModoDefault: 'xablau' };
    expect(modoDefault()).toBe('rascunho');
  });
  it('atributo da conversa vence', () => {
    window.chatwootConfig = { ramonCopilotoModoDefault: 'piloto_limitado' };
    expect(
      copilotoModoDe({ custom_attributes: { copiloto_modo: 'manual' } })
    ).toBe('manual');
  });
  it('aceita os modos "sozinha até…"', () => {
    expect(
      copilotoModoDe({
        custom_attributes: { copiloto_modo: 'piloto_ate_reuniao' },
      })
    ).toBe('piloto_ate_reuniao');
  });
  it('sem atributo vale o padrão da caixa, antes do padrão do servidor (como Ramon::CopilotoModo.of)', () => {
    window.chatwootConfig = { ramonCopilotoModoDefault: 'piloto_limitado' };
    expect(
      copilotoModoDe({}, { ramon_copiloto_modo: 'piloto_ate_reuniao' })
    ).toBe('piloto_ate_reuniao');
    expect(copilotoModoDe({}, { ramon_copiloto_modo: null })).toBe(
      'piloto_limitado'
    );
    expect(
      copilotoModoDe(
        { custom_attributes: { copiloto_modo: 'manual' } },
        { ramon_copiloto_modo: 'piloto_total' }
      )
    ).toBe('manual');
  });
  it('tomDoModo: uma cor por família de modo', () => {
    expect(tomDoModo('manual')).toBe(TOM.slate);
    expect(tomDoModo('rascunho')).toBe(TOM.blue);
    expect(tomDoModo('piloto_limitado')).toBe(TOM.amber);
    expect(tomDoModo('piloto_ate_contrato')).toBe(TOM.ruby);
  });
});
