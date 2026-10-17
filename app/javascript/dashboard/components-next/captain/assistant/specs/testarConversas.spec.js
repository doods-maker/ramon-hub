import {
  SEM_TESE,
  conversaDe,
  escolherRoteiro,
  garantirConversa,
  limparConversa,
  pararTesteDoPerfil,
  pedidoDoRoteiro,
  roteiroDe,
  testarPerfil,
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
      thesisId: null,
      estado: null,
      painel: null,
      perfil: null,
    });
    escolherRoteiro(1, '');
  });

  it('pedidoDoRoteiro: nada sem seleção; lead sem tese manda thesis_id nulo', () => {
    garantirConversa(1);
    expect(pedidoDoRoteiro(roteiroDe(1))).toBeNull();
    escolherRoteiro(1, '5');
    expect(pedidoDoRoteiro(roteiroDe(1))).toEqual({
      thesis_id: 5,
      estado: null,
    });
    escolherRoteiro(1, SEM_TESE);
    expect(pedidoDoRoteiro(roteiroDe(1)).thesis_id).toBeNull();
    escolherRoteiro(1, '');
  });

  it('Testar este perfil: recomeça a conversa na tese do alvo e o cfg vai no pedido até parar', () => {
    garantirConversa(1);
    conversaDe(1).push({ content: 'velha' });
    testarPerfil(1, { base: 'acelerada' }, 4);
    expect(conversaDe(1)).toHaveLength(0);
    expect(pedidoDoRoteiro(roteiroDe(1))).toEqual({
      thesis_id: 4,
      estado: null,
      perfil: { base: 'acelerada' },
    });
    limparConversa(1);
    expect(roteiroDe(1).perfil).toEqual({ base: 'acelerada' });
    pararTesteDoPerfil(1);
    expect(pedidoDoRoteiro(roteiroDe(1))).toEqual({
      thesis_id: 4,
      estado: null,
    });

    testarPerfil(1, { base: 'cautelosa' }, null);
    expect(roteiroDe(1).selecao).toBe(SEM_TESE);
    escolherRoteiro(1, '');
    expect(roteiroDe(1).perfil).toBeNull();
  });
});
