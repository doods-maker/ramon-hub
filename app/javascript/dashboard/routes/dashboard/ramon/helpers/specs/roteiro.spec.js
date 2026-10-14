import {
  destinosDe,
  limparSaida,
  listaParaTexto,
  novaSaida,
  passosDe,
  payloadDoPasso,
  slugChave,
  sugestoesQuando,
  textoParaLista,
} from '../roteiro';

const TODOS = [
  { id: 1, thesis_id: null, position: 1, chave: 'nome' },
  { id: 2, thesis_id: null, position: 0, chave: 'tem_advogado' },
  { id: 3, thesis_id: 7, position: 0, chave: 'renda' },
  { id: 4, thesis_id: 8, position: 0, chave: 'outra' },
];

describe('helpers do roteiro da IA', () => {
  it('slugChave tira acento e vira a-z, 0-9 e _', () => {
    expect(slugChave('Recebeu auxílio-doença?')).toBe('recebeu_auxilio_doenca');
    expect(slugChave('  Já tem advogado  ')).toBe('ja_tem_advogado');
  });

  it('lista e texto separados por vírgula', () => {
    expect(textoParaLista(' a, b ,, c ')).toEqual(['a', 'b', 'c']);
    expect(listaParaTexto(['a', 'b'])).toBe('a, b');
    expect(listaParaTexto(null)).toBe('');
  });

  it('passos do escopo na ordem; destinos = comuns (+ os da tese)', () => {
    expect(passosDe(TODOS, null).map(p => p.chave)).toEqual([
      'tem_advogado',
      'nome',
    ]);
    expect(destinosDe(TODOS, 7).map(p => p.chave)).toEqual([
      'tem_advogado',
      'nome',
      'renda',
    ]);
    expect(destinosDe(TODOS, null).map(p => p.chave)).toEqual([
      'tem_advogado',
      'nome',
    ]);
  });

  it('sugestões do "quando": calculadora manda; senão o tipo', () => {
    const calcs = {
      meses_ate_65: {
        campos: ['nascimento'],
        resultados: ['ja_tem_65', 'menos_de_65', 'depende'],
      },
    };
    expect(sugestoesQuando({ tipo_resposta: 'sim_nao' }, calcs)).toEqual([
      'sim',
      'nao',
      '*',
    ]);
    expect(
      sugestoesQuando({ tipo_resposta: 'escolha', opcoes: ['A', 'B'] }, calcs)
    ).toEqual(['A', 'B', '*']);
    expect(
      sugestoesQuando(
        { tipo_resposta: 'data', calculadora: 'meses_ate_65' },
        calcs
      )
    ).toEqual(['ja_tem_65', 'menos_de_65', 'depende', '*']);
    expect(sugestoesQuando({ tipo_resposta: 'texto' }, calcs)).toEqual(['*']);
  });

  it('novaSaida pega o próximo id livre', () => {
    expect(novaSaida([])).toEqual({ id: 's1', quando: '', acao: 'seguir' });
    expect(novaSaida([{ id: 's2' }]).id).toBe('s3');
  });

  it('limparSaida deixa só o que a ação usa', () => {
    const cheia = {
      id: 's1',
      quando: ' sim ',
      acao: 'seguir',
      alvo: 'x',
      motivo: 'm',
      motivo_perda: 'Outro',
      mensagem: ' ',
      efeitos: { etiqueta: '', etapa: 'Qualificação' },
    };
    expect(limparSaida(cheia)).toEqual({
      id: 's1',
      quando: 'sim',
      acao: 'seguir',
      efeitos: { etapa: 'Qualificação' },
    });
    expect(limparSaida({ ...cheia, acao: 'desqualificar' })).toEqual({
      id: 's1',
      quando: 'sim',
      acao: 'desqualificar',
      motivo: 'm',
      motivo_perda: 'Outro',
      efeitos: { etapa: 'Qualificação' },
    });
    expect(
      limparSaida({ id: 's2', quando: '*', acao: 'ir_para', alvo: 'renda' })
    ).toEqual({
      id: 's2',
      quando: '*',
      acao: 'ir_para',
      alvo: 'renda',
    });
  });

  it('payload: opções só em escolha, campos só com calculadora', () => {
    const base = {
      titulo: ' Renda ',
      chave: 'renda',
      orientacao: '',
      tipo_resposta: 'numero',
      opcoesTexto: 'a, b',
      calculadora: '',
      calculadora_campos: { x: 'y' },
      saidas: [],
    };
    expect(payloadDoPasso(base, [])).toEqual({
      titulo: 'Renda',
      chave: 'renda',
      orientacao: '',
      tipo_resposta: 'numero',
      opcoes: [],
      calculadora: '',
      calculadora_campos: {},
      saidas: [],
    });
    expect(
      payloadDoPasso(
        {
          ...base,
          tipo_resposta: 'escolha',
          calculadora: 'renda_per_capita',
          calculadora_campos: { renda_total: 'renda', moradores: '' },
        },
        ['renda_total', 'moradores']
      )
    ).toEqual(
      expect.objectContaining({
        opcoes: ['a', 'b'],
        calculadora_campos: { renda_total: 'renda' },
      })
    );
    // trocar de calculadora: o campo da anterior não vai junto
    expect(
      payloadDoPasso(
        {
          ...base,
          calculadora: 'prazo_inss',
          calculadora_campos: { renda_total: 'renda', data: 'nome' },
        },
        ['data']
      ).calculadora_campos
    ).toEqual({ data: 'nome' });
  });
});
