import { blocosDoTexto, descreverPedido } from '../pedidoAgente';

describe('blocosDoTexto', () => {
  it('separa as seções em rótulo e texto, mantendo as listas', () => {
    expect(
      blocosDoTexto(
        'SITUAÇÃO: Parou.\n\nDOCUMENTOS QUE FALTAM:\n1. Laudo\n2. CTPS\n\nTexto solto'
      )
    ).toEqual([
      { rotulo: 'SITUAÇÃO', texto: 'Parou.' },
      { rotulo: 'DOCUMENTOS QUE FALTAM', texto: '1. Laudo\n2. CTPS' },
      { rotulo: null, texto: 'Texto solto' },
    ]);
  });

  it('não confunde início de frase com rótulo', () => {
    expect(blocosDoTexto('Esteira: rota inviável.')).toEqual([
      { rotulo: null, texto: 'Esteira: rota inviável.' },
    ]);
  });

  it('sem texto, sem blocos', () => {
    expect(blocosDoTexto(undefined)).toEqual([]);
  });
});

describe('descreverPedido', () => {
  it('tarefa do ADVBOX: ação, cliente, número, nomes e prazo', () => {
    expect(
      descreverPedido({
        caso: 'Maria Exemplo #100200',
        ferramenta: 'mcp__advbox__advbox_criar_tarefa',
        nomes: { responsavel: 'Eduardo', tipo: 'Solicitar documentos' },
        entrada: {
          responsavel_id: 5,
          tipo_tarefa_id: 9,
          processo_id: 188,
          prazo: '2026-11-30',
          descricao: 'SITUAÇÃO: Parou.',
        },
      })
    ).toMatchObject({
      chave: 'TAREFA',
      conhecida: true,
      cliente: 'Maria Exemplo',
      numero: '100200',
      campos: [
        { chave: 'PARA', valor: 'Eduardo' },
        { chave: 'TIPO', valor: 'Solicitar documentos' },
        { chave: 'PROCESSO', valor: '#188' },
        { chave: 'PRAZO', valor: '30/11/2026' },
      ],
      blocos: [{ rotulo: 'SITUAÇÃO', texto: 'Parou.' }],
    });
  });

  it('sem o nome no ADVBOX, mostra o número', () => {
    const { campos } = descreverPedido({
      ferramenta: 'mcp__advbox__advbox_criar_tarefa',
      entrada: { responsavel_id: 5, tipo_tarefa_id: 9 },
    });
    expect(campos).toEqual([
      { chave: 'PARA', valor: '#5' },
      { chave: 'TIPO', valor: '#9' },
    ]);
  });

  it('site mostra o endereço', () => {
    expect(
      descreverPedido({
        caso: '123',
        ferramenta: 'WebFetch',
        entrada: { url: 'https://exemplo.gov.br' },
      })
    ).toMatchObject({
      chave: 'SITE',
      linha: 'https://exemplo.gov.br',
      numero: '123',
    });
  });

  it('ferramenta desconhecida fica marcada para abrir os detalhes', () => {
    expect(
      descreverPedido({ ferramenta: 'mcp__x__apagar_tudo', entrada: {} })
    ).toMatchObject({
      chave: 'OUTRA',
      conhecida: false,
      ferramenta: 'apagar_tudo',
    });
  });
});
