import { variacao, rotuloAnterior } from '../variacao';

describe('variacao', () => {
  it('percentual compara em pontos; o resto em % de mudança', () => {
    expect(variacao(62, 50, { unidade: '%' })).toEqual({
      seta: 'sobe',
      n: 12,
      pontos: true,
      tom: 'teal',
    });
    expect(variacao(12, 10, {})).toEqual({
      seta: 'sobe',
      n: 20,
      pontos: false,
      tom: 'teal',
    });
  });

  it('sentido max (menor é melhor): subir é ruim', () => {
    expect(variacao(8, 5, { unidade: 'min', sentido: 'max' })).toMatchObject({
      seta: 'sobe',
      tom: 'ruby',
    });
    expect(variacao(40, 50, {})).toMatchObject({ seta: 'desce', tom: 'ruby' });
  });

  it('sem dado ou anterior zero (fora de %): sem variação; igual arredondado', () => {
    expect(variacao(null, 5)).toBeNull();
    expect(variacao(5, null)).toBeNull();
    expect(variacao(5, 0, {})).toBeNull();
    expect(variacao(40, 0, { unidade: '%' })).toMatchObject({ n: 40 });
    expect(variacao(50.3, 50, { unidade: '%' })).toMatchObject({
      seta: 'igual',
      tom: 'slate',
    });
  });
});

describe('rotuloAnterior', () => {
  it('vários dias: de–até, com o fim exclusivo à meia-noite', () => {
    expect(
      rotuloAnterior({
        inicio: '2026-09-01T00:00:00-03:00',
        fim: '2026-10-01T00:00:00-03:00',
      })
    ).toEqual({ chave: 'VS_DIAS', params: { de: '01/09', ate: '30/09' } });
    expect(
      rotuloAnterior({
        inicio: '2026-10-01T00:00:00-03:00',
        fim: '2026-10-18T14:00:00-03:00',
      })
    ).toEqual({ chave: 'VS_DIAS', params: { de: '01/10', ate: '18/10' } });
  });

  it('um dia só: até a hora do corte', () => {
    expect(
      rotuloAnterior({
        inicio: '2026-11-17T00:00:00-03:00',
        fim: '2026-11-17T14:00:00-03:00',
      })
    ).toEqual({ chave: 'VS_ATE', params: { dia: '17/11', hora: '14' } });
  });

  it('sem período: nada', () => {
    expect(rotuloAnterior(null)).toBeNull();
  });
});
