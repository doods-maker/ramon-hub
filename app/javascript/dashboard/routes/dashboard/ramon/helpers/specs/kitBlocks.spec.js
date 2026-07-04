import { stageMode, kitBlocks } from '../kitBlocks';

describe('stageMode', () => {
  it('é encerrado quando o lead tem won_at ou lost_at', () => {
    expect(stageMode({ won_at: '2026-07-04', stage_name: 'Fechado' })).toBe('encerrado');
    expect(stageMode({ lost_at: '2026-07-04', stage_name: 'Perdido' })).toBe('encerrado');
  });

  it('é closer da reunião agendada até a última chance', () => {
    ['Reunião agendada', 'Reunião realizada', 'Negociação', 'Última chance'].forEach(stage => {
      expect(stageMode({ stage_name: stage })).toBe('closer');
    });
  });

  it('é sdr por padrão (Novo, Qualificação, etapa desconhecida, sem etapa)', () => {
    expect(stageMode({ stage_name: 'Novo' })).toBe('sdr');
    expect(stageMode({ stage_name: 'Qualificação' })).toBe('sdr');
    expect(stageMode({ stage_name: 'Etapa custom' })).toBe('sdr');
    expect(stageMode({})).toBe('sdr');
  });
});

describe('kitBlocks', () => {
  it('sdr vê roteiro e próximo passo', () => {
    expect(kitBlocks('sdr')).toEqual(['roteiro', 'proximo_passo']);
  });

  it('closer vê resumo, venda/objeções, documentos e próximo passo', () => {
    expect(kitBlocks('closer')).toEqual(['resumo', 'venda_objecoes', 'documentos', 'proximo_passo']);
  });

  it('encerrado não vê nada', () => {
    expect(kitBlocks('encerrado')).toEqual([]);
  });
});
