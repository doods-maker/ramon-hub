import {
  filtrarCasos,
  resultadoPorCaso,
  ordenarPorAtencao,
  fmtUsd,
  fmtDuracao,
  paraLista,
} from '../casos';

const CASOS = [
  {
    id: 1,
    titulo: 'A1',
    grupo: 'a',
    ativo: true,
    mensagens: [{ content: 'Acidente de moto' }],
  },
  { id: 2, titulo: 'B1', grupo: 'b', ativo: false, mensagens: [] },
  { id: 3, titulo: 'C1', grupo: 'b', ativo: true, mensagens: [] },
];

describe('regras da tela Casos de teste', () => {
  it('filtra por busca sem acento, grupo e ativo', () => {
    expect(filtrarCasos(CASOS, { busca: 'ACIDENTE' }).map(c => c.id)).toEqual([
      1,
    ]);
    expect(filtrarCasos(CASOS, { grupo: 'b' }).map(c => c.id)).toEqual([2, 3]);
    expect(filtrarCasos(CASOS, { ativo: 'ativos' }).map(c => c.id)).toEqual([
      1, 3,
    ]);
  });

  it('marca piorou/melhorou e põe o que piorou primeiro', () => {
    const resultados = resultadoPorCaso({
      resultados: [
        { caso_id: 1, passou: true },
        { caso_id: 2, passou: false },
        { caso_id: 3, passou: false },
      ],
      comparacao: { pioraram: [3], melhoraram: [1] },
    });

    expect(resultados[3].delta).toBe('piorou');
    expect(resultados[1].delta).toBe('melhorou');
    expect(resultados[2].delta).toBeNull();
    expect(ordenarPorAtencao(CASOS, resultados).map(c => c.id)).toEqual([
      3, 2, 1,
    ]);
  });

  it('formatos', () => {
    expect(fmtUsd(2.5)).toBe('US$ 2,50');
    expect(fmtDuracao(65000)).toBe('1min 5s');
    expect(paraLista('a, b,\n c', /[,\n]/)).toEqual(['a', 'b', 'c']);
  });
});
