import {
  adicionarPasso,
  caminhoAceso,
  deVueFlow,
  duplicarPasso,
  idDoErro,
  ligar,
  novaChave,
  paraVueFlow,
  podarSetas,
  saidasDe,
  trocarConfig,
} from '../fluxo';

const DESENHO = {
  nos: [
    {
      id: 'n1',
      tipo: 'gatilho',
      config: { tipo: 'lead_mudou_etapa', para_etapa_ids: [3] },
      posicao: { x: 0, y: 0 },
    },
    {
      id: 'n2',
      tipo: 'se',
      config: {
        juncao: 'e',
        condicoes: [{ campo: 'tese', operador: 'igual', valor: 'BPC' }],
      },
      posicao: { x: 0, y: 140 },
    },
    {
      id: 'n3',
      tipo: 'escolha',
      config: {
        campo: 'tese',
        casos: [
          { chave: 'c1', rotulo: 'BPC', valores: ['BPC'] },
          { chave: 'c2', rotulo: 'Acidente', valores: ['Auxílio-acidente'] },
        ],
      },
      posicao: { x: -130, y: 300 },
    },
    {
      id: 'n4',
      tipo: 'nota_privada',
      config: { texto: 'oi {nome}', rotulo: 'Aviso' },
      posicao: { x: 130, y: 300 },
    },
    { id: 'n5', tipo: 'parar', config: {}, posicao: { x: -260, y: 460 } },
  ],
  setas: [
    { de: 'n1', saida: 's', para: 'n2' },
    { de: 'n2', saida: 'sim', para: 'n3' },
    { de: 'n2', saida: 'nao', para: 'n4' },
    { de: 'n3', saida: 'c2', para: 'n5' },
    { de: 'n3', saida: 'outro', para: 'n4' },
  ],
};

describe('conversor desenho ↔ Vue Flow', () => {
  it('salvar e reabrir devolve o mesmo desenho', () => {
    const { nodes, edges } = paraVueFlow(DESENHO);
    expect(deVueFlow(nodes, edges)).toEqual(DESENHO);
  });

  it('gera nós do tipo passo, gatilho não apagável e setas com id de porta', () => {
    const { nodes, edges } = paraVueFlow(DESENHO);
    expect(nodes[0]).toEqual({
      id: 'n1',
      type: 'passo',
      position: { x: 0, y: 0 },
      data: {
        tipo: 'gatilho',
        config: { tipo: 'lead_mudou_etapa', para_etapa_ids: [3] },
      },
      deletable: false,
    });
    expect(nodes[1].deletable).toBe(true);
    expect(edges[1]).toEqual({
      id: 'n2:sim',
      source: 'n2',
      sourceHandle: 'sim',
      target: 'n3',
      targetHandle: 'e',
    });
  });

  it('desenho sem posicao/config/setas abre em (0,0) com config vazia', () => {
    const { nodes, edges } = paraVueFlow({
      nos: [{ id: 'g', tipo: 'gatilho', config: null }],
    });
    expect(nodes[0].position).toEqual({ x: 0, y: 0 });
    expect(nodes[0].data.config).toEqual({});
    expect(edges).toEqual([]);
    expect(paraVueFlow(undefined)).toEqual({ nodes: [], edges: [] });
  });

  it('arredonda a posição ao salvar (arrasto com zoom dá fração)', () => {
    const { nodes, edges } = paraVueFlow(DESENHO);
    nodes[1] = { ...nodes[1], position: { x: 10.4, y: 139.6 } };
    expect(deVueFlow(nodes, edges).nos[1].posicao).toEqual({ x: 10, y: 140 });
  });

  it('seta de um caso apagado do escolha some ao salvar', () => {
    const { nodes, edges } = paraVueFlow(DESENHO);
    const semC2 = trocarConfig(nodes, 'n3', {
      campo: 'tese',
      casos: [
        { chave: 'c1', rotulo: 'BPC', valores: ['BPC'] },
        { chave: 'c3', rotulo: 'Idade', valores: ['Aposentadoria'] },
      ],
    });
    const setas = deVueFlow(semC2, edges).setas;
    expect(setas.find(s => s.saida === 'c2')).toBeUndefined();
    expect(setas.find(s => s.saida === 'outro')).toBeDefined();
  });

  it('apagar um caso do escolha tira a seta dele do quadro na hora', () => {
    const { nodes, edges } = paraVueFlow(DESENHO);
    const semC2 = trocarConfig(nodes, 'n3', {
      campo: 'tese',
      casos: [{ chave: 'c1', rotulo: 'BPC', valores: ['BPC'] }],
    });
    const novas = podarSetas(
      edges,
      semC2.find(n => n.id === 'n3')
    );
    expect(novas.map(e => e.id)).toEqual(
      edges.map(e => e.id).filter(id => id !== 'n3:c2')
    );
    // passo que não perdeu porta: devolve todas as setas
    expect(
      podarSetas(
        edges,
        nodes.find(n => n.id === 'n2')
      )
    ).toEqual(edges);
  });
});

describe('portas de saída', () => {
  it('por tipo de passo', () => {
    expect(saidasDe('gatilho', {})).toEqual(['s']);
    expect(saidasDe('se', {})).toEqual(['sim', 'nao']);
    expect(
      saidasDe('escolha', { casos: [{ chave: 'c1' }, { chave: 'c2' }] })
    ).toEqual(['c1', 'c2', 'outro']);
    expect(saidasDe('escolha', {})).toEqual(['outro']);
    expect(saidasDe('parar', {})).toEqual([]);
    expect(saidasDe('esperar', {})).toEqual(['s']);
  });

  it('nova chave de caso não repete', () => {
    expect(novaChave([{ chave: 'c1' }, { chave: 'c4' }])).toBe('c5');
    expect(novaChave([])).toBe('c1');
  });
});

describe('ligar', () => {
  const { edges } = paraVueFlow(DESENHO);

  it('2ª seta na mesma porta substitui a anterior', () => {
    const novas = ligar(edges, {
      source: 'n2',
      sourceHandle: 'nao',
      target: 'n5',
    });
    expect(
      novas.filter(e => e.source === 'n2' && e.sourceHandle === 'nao')
    ).toEqual([
      {
        id: 'n2:nao',
        source: 'n2',
        sourceHandle: 'nao',
        target: 'n5',
        targetHandle: 'e',
      },
    ]);
    expect(novas).toHaveLength(edges.length);
  });

  it('recusa ligar o passo nele mesmo', () => {
    expect(
      ligar(edges, { source: 'n4', sourceHandle: 's', target: 'n4' })
    ).toBeNull();
  });

  it('recusa fechar laço (voltar para um passo anterior)', () => {
    expect(
      ligar(edges, { source: 'n4', sourceHandle: 's', target: 'n2' })
    ).toBeNull();
  });

  it('aceita dois ramos chegando no mesmo passo', () => {
    expect(
      ligar(edges, { source: 'n3', sourceHandle: 'c1', target: 'n4' })
    ).toHaveLength(edges.length + 1);
  });
});

describe('adicionar, duplicar, trocar config', () => {
  it('com passo selecionado: entra embaixo dele e liga na 1ª porta livre', () => {
    const { nodes, edges } = paraVueFlow(DESENHO);
    const r = adicionarPasso(nodes, edges, { tipo: 'esperar' }, 'n3');
    expect(r.id).toBe('n6');
    const novo = r.nodes.find(n => n.id === 'n6');
    expect(novo.position).toEqual({ x: -130, y: 440 });
    expect(novo.data).toEqual({
      tipo: 'esperar',
      config: { quantidade: 1, unidade: 'dias' },
    });
    expect(r.edges).toContainEqual({
      id: 'n3:c1',
      source: 'n3',
      sourceHandle: 'c1',
      target: 'n6',
      targetHandle: 'e',
    });
  });

  it('sem seleção: entra abaixo do passo mais baixo, solto', () => {
    const { nodes, edges } = paraVueFlow(DESENHO);
    const r = adicionarPasso(
      nodes,
      edges,
      {
        tipo: 'acao_chatwoot',
        config: { acoes: [{ action_name: 'add_label', action_params: [] }] },
      },
      null
    );
    expect(r.nodes.find(n => n.id === r.id).position).toEqual({
      x: -260,
      y: 600,
    });
    expect(r.edges).toBe(edges);
  });

  it('a config do item da paleta é copiada (não compartilhada)', () => {
    const item = {
      tipo: 'acao_chatwoot',
      config: { acoes: [{ action_name: 'add_label', action_params: [] }] },
    };
    const { nodes, edges } = paraVueFlow(DESENHO);
    const r = adicionarPasso(nodes, edges, item, null);
    r.nodes
      .find(n => n.id === r.id)
      .data.config.acoes[0].action_params.push('x');
    expect(item.config.acoes[0].action_params).toEqual([]);
  });

  it('duplicar cria cópia deslocada, sem setas', () => {
    const { nodes } = paraVueFlow(DESENHO);
    const r = duplicarPasso(nodes, 'n4');
    const copia = r.nodes.find(n => n.id === r.id);
    expect(r.id).toBe('n6');
    expect(copia.position).toEqual({ x: 170, y: 340 });
    expect(copia.data).toEqual(nodes.find(n => n.id === 'n4').data);
    expect(copia.data).not.toBe(nodes.find(n => n.id === 'n4').data);
  });

  it('não duplica o gatilho', () => {
    const { nodes } = paraVueFlow(DESENHO);
    const gatilho = nodes.find(n => n.data.tipo === 'gatilho');
    expect(duplicarPasso(nodes, gatilho.id)).toEqual({ nodes, id: gatilho.id });
  });

  it('quadro vazio: o passo entra na origem, sem quebrar', () => {
    const r = adicionarPasso([], [], { tipo: 'parar' }, null);
    expect(r.nodes[0].position).toEqual({ x: 0, y: 0 });
    expect(r.edges).toEqual([]);
  });
});

describe('erros do back e caminho aceso', () => {
  it('acha o passo na mensagem do back', () => {
    expect(idDoErro('Passo n3: falta texto')).toBe('n3');
    expect(idDoErro('Passo n3 (Se) precisa de condições')).toBe('n3');
    expect(idDoErro('Passo n12 não está ligado ao gatilho')).toBe('n12');
    expect(idDoErro('O fluxo precisa de exatamente 1 gatilho')).toBeNull();
  });

  it('acende os passos da trilha e as setas percorridas', () => {
    const trilha = [
      { no: 'n1', tipo: 'gatilho', saida: 's' },
      { no: 'n2', tipo: 'se', saida: 'nao' },
      { no: 'n4', tipo: 'nota_privada', saida: 's' },
    ];
    const { nos, setas } = caminhoAceso(trilha, DESENHO);
    expect([...nos]).toEqual(['n1', 'n2', 'n4']);
    expect([...setas]).toEqual(['n1:s', 'n2:nao']);
  });
});
