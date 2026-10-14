import {
  SEM_TESE,
  conversaDe,
  escolherRoteiro,
  garantirConversa,
  limparConversa,
  pedidoDoRoteiro,
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

  it('roteiro do Testar: limpar zera o estado e volta à tese da seleção', () => {
    garantirConversa(1);
    escolherRoteiro(1, SEM_TESE);
    // o "assunto" escolheu a tese 3 durante a conversa
    Object.assign(roteiroDe(1), { thesisId: 3, estado: { a: 1 }, painel: {} });
    limparConversa(1);
    expect(roteiroDe(1)).toEqual({
      selecao: SEM_TESE,
      modo: 'rascunho',
      thesisId: null,
      estado: null,
      painel: null,
    });
    escolherRoteiro(1, '');
  });

  it('pedidoDoRoteiro: nada sem seleção; lead sem tese manda thesis_id nulo e o modo', () => {
    garantirConversa(1);
    expect(pedidoDoRoteiro(roteiroDe(1))).toBeNull();
    escolherRoteiro(1, '5');
    roteiroDe(1).modo = 'piloto_total';
    expect(pedidoDoRoteiro(roteiroDe(1))).toEqual({
      thesis_id: 5,
      estado: null,
      modo: 'piloto_total',
    });
    escolherRoteiro(1, SEM_TESE);
    expect(pedidoDoRoteiro(roteiroDe(1)).thesis_id).toBeNull();
    escolherRoteiro(1, '');
    roteiroDe(1).modo = 'rascunho';
  });
});
