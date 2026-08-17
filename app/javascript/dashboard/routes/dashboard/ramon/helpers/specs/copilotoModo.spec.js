import { copilotoModoDe, modoDefault } from '../copilotoModo';

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
});
