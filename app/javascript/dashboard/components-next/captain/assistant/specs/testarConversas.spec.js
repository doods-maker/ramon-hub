import {
  conversaDe,
  garantirConversa,
  limparConversa,
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
});
