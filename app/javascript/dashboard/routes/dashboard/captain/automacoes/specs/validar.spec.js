import { validar } from '../validar';

const g = (config = { tipo: 'manual' }) => ({
  id: 'g',
  tipo: 'gatilho',
  config,
  posicao: { x: 0, y: 0 },
});
const p = (id, tipo, config = {}) => ({
  id,
  tipo,
  config,
  posicao: { x: 0, y: 0 },
});
const linear = (...passos) => ({
  nos: [g(), ...passos],
  setas: passos.map((passo, i) => ({
    de: i ? passos[i - 1].id : 'g',
    saida: 's',
    para: passo.id,
  })),
});
const codigos = desenho => validar(desenho).map(e => [e.no, e.codigo]);

describe('validar (espelho do Grafo#erros)', () => {
  it('desenho válido não tem erro', () => {
    expect(
      validar(
        linear(p('p1', 'nota_privada', { texto: 'oi' }), p('p2', 'parar'))
      )
    ).toEqual([]);
  });

  it('exatamente 1 gatilho (e para por aí)', () => {
    expect(codigos({ nos: [], setas: [] })).toEqual([[null, 'UM_GATILHO']]);
    expect(codigos({ nos: [g(), { ...g(), id: 'g2' }], setas: [] })).toEqual([
      [null, 'UM_GATILHO'],
    ]);
  });

  it('gatilho fora da lista da B1', () => {
    expect(codigos({ nos: [g({ tipo: 'inventado' })], setas: [] })).toEqual([
      ['g', 'GATILHO_DESCONHECIDO'],
    ]);
  });

  it('seta para passo inexistente e duas setas na mesma porta', () => {
    const d = linear(p('p1', 'parar'));
    d.setas.push({ de: 'g', saida: 's', para: 'fantasma' });
    expect(validar(d)).toEqual(
      expect.arrayContaining([
        { no: null, codigo: 'SETA_FANTASMA', params: { id: 'fantasma' } },
        { no: 'g', codigo: 'SETA_REPETIDA', params: { saida: 's' } },
      ])
    );
  });

  it('laço vira só "CICLO" (sem listar soltos)', () => {
    const d = linear(
      p('p1', 'nota_privada', { texto: 'a' }),
      p('p2', 'nota_privada', { texto: 'b' })
    );
    d.setas.push({ de: 'p2', saida: 's', para: 'p1' });
    expect(codigos(d)).toEqual([[null, 'CICLO']]);
  });

  it('passo solto', () => {
    const d = linear(p('p1', 'parar'));
    d.nos.push(p('p9', 'parar'));
    expect(codigos(d)).toEqual([['p9', 'SOLTO']]);
  });

  it('tipo desconhecido', () => {
    expect(codigos(linear(p('p1', 'inventado', {})))).toEqual([
      ['p1', 'TIPO_DESCONHECIDO'],
    ]);
  });

  it('gatilhos e passos da B2b válidos', () => {
    const d = linear(
      p('p1', 'registrar_atividade', { texto: 'a' }),
      p('p2', 'preencher_campo', { chave: 'beneficio', valor: 'BPC' }),
      p('p3', 'advbox', {
        acao: 'movimentacao',
        descricao: 'Contrato assinado no hub',
      }),
      p('p4', 'webhook', { url: 'https://hooks.exemplo.com.br/x' })
    );
    d.nos[0].config = { tipo: 'relogio', hora: '09:00' };
    expect(codigos(d)).toEqual([]);
  });

  it('relógio sem hora / hora torta', () => {
    const d = linear();
    d.nos[0].config = { tipo: 'relogio' };
    expect(codigos(d)).toEqual([['g', 'GATILHO_HORA']]);
    d.nos[0].config = { tipo: 'lead_parado', hora: '25:00' };
    expect(codigos(d)).toEqual([['g', 'GATILHO_HORA']]);
    d.nos[0].config = { tipo: 'lead_parado' };
    expect(codigos(d)).toEqual([]);
  });

  it('webhook só https e só no fim; advbox; chave do campo; IA sem saída', () => {
    expect(
      codigos(
        linear(
          p('p1', 'webhook', { url: 'http://x.com' }),
          p('p2', 'nota_privada', { texto: 'a' })
        )
      )
    ).toEqual([
      ['p1', 'WEBHOOK_HTTPS'],
      ['p1', 'WEBHOOK_ULTIMO'],
    ]);
    expect(codigos(linear(p('p1', 'advbox', {})))).toEqual([
      ['p1', 'ADVBOX_ACAO'],
    ]);
    expect(codigos(linear(p('p1', 'advbox', { acao: 'tarefa' })))).toEqual([
      ['p1', 'FALTA'],
      ['p1', 'FALTA'],
    ]);
    expect(
      codigos(
        linear(p('p1', 'advbox', { acao: 'movimentacao', descricao: 'curta' }))
      )
    ).toEqual([['p1', 'ADVBOX_DESCRICAO']]);
    expect(
      codigos(linear(p('p1', 'preencher_campo', { chave: 'Benefício' })))
    ).toEqual([['p1', 'CAMPO_CHAVE']]);
    // nome reservado do hub (Contexto::RESERVADAS)
    expect(
      codigos(linear(p('p1', 'preencher_campo', { chave: 'telefone' })))
    ).toEqual([['p1', 'CAMPO_CHAVE']]);
    expect(codigos(linear(p('p1', 'perguntar_ia', { pergunta: 'x' })))).toEqual(
      [['p1', 'SE_SEM_SAIDA']]
    );
    expect(codigos(linear(p('p1', 'rodar_skill', {})))).toEqual([
      ['p1', 'FALTA'],
      ['p1', 'FALTA'],
    ]);
  });

  it('obrigatórios em branco (blank? do Rails: nil, "", só espaço)', () => {
    expect(
      validar(linear(p('p1', 'rascunho_texto', { texto: '   ' })))
    ).toEqual([{ no: 'p1', codigo: 'FALTA', params: { campo: 'texto' } }]);
    expect(codigos(linear(p('p1', 'mover_etapa', {})))).toEqual([
      ['p1', 'FALTA'],
    ]);
    expect(codigos(linear(p('p1', 'criar_tarefa', { titulo: '' })))).toEqual([
      ['p1', 'FALTA'],
    ]);
    expect(codigos(linear(p('p1', 'avisar_sino', {})))).toEqual([
      ['p1', 'FALTA'],
    ]);
    expect(codigos(linear(p('p1', 'avisar_push', {})))).toEqual([
      ['p1', 'FALTA'],
    ]);
  });

  it('se: sem condições e sem nenhuma saída', () => {
    const d = {
      nos: [g(), p('p1', 'se', { condicoes: [] })],
      setas: [{ de: 'g', saida: 's', para: 'p1' }],
    };
    expect(codigos(d)).toEqual([
      ['p1', 'SE_SEM_CONDICOES'],
      ['p1', 'SE_SEM_SAIDA'],
    ]);
  });

  it('escolha: menos de 2 casos, chave repetida, valor repetido (sem caixa)', () => {
    const um = linear(
      p('p1', 'escolha', {
        campo: 'tese',
        casos: [{ chave: 'c1', valores: ['A'] }],
      })
    );
    expect(codigos(um)).toEqual([['p1', 'ESCOLHA_POUCOS_CASOS']]);
    const dup = linear(
      p('p1', 'escolha', {
        campo: 'tese',
        casos: [
          { chave: 'c1', valores: ['BPC'] },
          { chave: 'c1', valores: ['bpc'] },
        ],
      })
    );
    expect(codigos(dup)).toEqual([
      ['p1', 'ESCOLHA_CHAVE_REPETIDA'],
      ['p1', 'ESCOLHA_VALOR_REPETIDO'],
    ]);
    expect(
      codigos(
        linear(
          p('p1', 'escolha', { casos: [{ chave: 'c1' }, { chave: 'c2' }] })
        )
      )
    ).toEqual([['p1', 'FALTA']]);
  });

  it('esperar: quantidade > 0 com unidade válida, ou até o horário comercial', () => {
    expect(
      validar(linear(p('p1', 'esperar', { quantidade: '2', unidade: 'dias' })))
    ).toEqual([]);
    expect(
      validar(linear(p('p1', 'esperar', { ate: 'horario_comercial' })))
    ).toEqual([]);
    expect(
      codigos(linear(p('p1', 'esperar', { quantidade: 0, unidade: 'dias' })))
    ).toEqual([['p1', 'ESPERA_SEM_TEMPO']]);
    expect(
      codigos(linear(p('p1', 'esperar', { quantidade: 2, unidade: 'semanas' })))
    ).toEqual([['p1', 'ESPERA_SEM_TEMPO']]);
  });

  it('ação do Chatwoot: vazia, mensagem ao cliente, proibida, desconhecida', () => {
    const acao = (...nomes) =>
      linear(
        p('p1', 'acao_chatwoot', {
          acoes: nomes.map(action_name => ({ action_name, action_params: [] })),
        })
      );
    expect(codigos(acao())).toEqual([['p1', 'CHATWOOT_SEM_ACAO']]);
    expect(codigos(acao('add_label', 'send_message'))).toEqual([
      ['p1', 'CHATWOOT_MENSAGEM'],
    ]);
    expect(validar(acao('send_webhook_event'))).toEqual([
      {
        no: 'p1',
        codigo: 'CHATWOOT_PROIBIDA',
        params: { nome: 'send_webhook_event' },
      },
    ]);
    expect(validar(acao('apagar_tudo'))).toEqual([
      {
        no: 'p1',
        codigo: 'CHATWOOT_DESCONHECIDA',
        params: { nome: 'apagar_tudo' },
      },
    ]);
    expect(validar(acao('add_label', 'add_sla', 'add_private_note'))).toEqual(
      []
    );
  });
});
