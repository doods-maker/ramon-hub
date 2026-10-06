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
    expect(codigos({ nos: [g({ tipo: 'relogio' })], setas: [] })).toEqual([
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

  it('tipo desconhecido (ex.: passo da B2b)', () => {
    expect(codigos(linear(p('p1', 'webhook', { url: 'x' })))).toEqual([
      ['p1', 'TIPO_DESCONHECIDO'],
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
