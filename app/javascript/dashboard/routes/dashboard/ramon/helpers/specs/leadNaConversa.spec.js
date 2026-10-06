import { semEtiquetasDoLead, partesDaLinha } from '../leadNaConversa';

describe('semEtiquetasDoLead', () => {
  it('tira fase-* e tese-* quando a conversa tem lead', () => {
    expect(
      semEtiquetasDoLead(['fase-novo', 'tese-bpc-loas', 'urgente'], { id: 1 })
    ).toEqual(['urgente']);
  });

  it('sem lead, mantém todas as etiquetas', () => {
    expect(semEtiquetasDoLead(['fase-novo', 'urgente'], null)).toEqual([
      'fase-novo',
      'urgente',
    ]);
    expect(semEtiquetasDoLead(undefined, null)).toEqual([]);
  });
});

describe('partesDaLinha', () => {
  it('etapa · tese · closer (ou SDR quando não há closer)', () => {
    const lead = {
      stage_name: 'Qualificação',
      thesis_name: 'BPC/LOAS',
      sdr_name: 'Ana',
    };
    expect(partesDaLinha(lead)).toEqual(['Qualificação', 'BPC/LOAS', 'Ana']);
    expect(partesDaLinha({ ...lead, closer_name: 'Bruno' })[2]).toBe('Bruno');
  });

  it('pula o que falta e aceita lead nulo', () => {
    expect(partesDaLinha({ stage_name: 'Novo' })).toEqual(['Novo']);
    expect(partesDaLinha(null)).toEqual([]);
  });
});
