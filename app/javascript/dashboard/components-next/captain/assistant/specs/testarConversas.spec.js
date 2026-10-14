import {
  conversaDe,
  garantirConversa,
  limparConversa,
  roteiroDe,
} from '../testarConversas';

describe('conversas do Testar (I-PG3)', () => {
  beforeEach(() => {
    limparConversa(1);
    limparConversa(2);
  });

  it('cada assistente guarda a sua; limpar zera só a dele', () => {
    garantirConversa(1);
    garantirConversa(2);
    conversaDe(1).push({ content: 'oi' });
    expect(conversaDe(1)).toHaveLength(1);
    expect(conversaDe(2)).toHaveLength(0);
    limparConversa(1);
    expect(conversaDe(1)).toHaveLength(0);
  });

  it('garantir não apaga o que já existe', () => {
    garantirConversa(1);
    conversaDe(1).push({ content: 'oi' });
    garantirConversa(1);
    expect(conversaDe(1)).toHaveLength(1);
  });

  it('roteiro do Testar: limpar a conversa zera o estado e mantém a tese', () => {
    garantirConversa(1);
    Object.assign(roteiroDe(1), {
      thesisId: 3,
      estado: { a: 1 },
      painel: { passos: [] },
    });
    limparConversa(1);
    expect(roteiroDe(1)).toEqual({ thesisId: 3, estado: null, painel: null });
    roteiroDe(1).thesisId = null;
  });
});
