import { entraNoGanho, pulaDocumentos } from '../stage';

describe('entraNoGanho', () => {
  it('de etapa aberta (ou desconhecida) para ganho é entrar no ganho', () => {
    expect(entraNoGanho({ is_won: true }, { is_won: false })).toBe(true);
    expect(entraNoGanho({ is_won: true }, undefined)).toBe(true);
  });

  it('de ganho para ganho não é um ganho novo', () => {
    expect(entraNoGanho({ is_won: true }, { is_won: true })).toBe(false);
  });

  it('para etapa que não é de ganho, não', () => {
    expect(entraNoGanho({ is_won: false }, { is_won: false })).toBe(false);
    expect(entraNoGanho(undefined, undefined)).toBe(false);
  });
});

describe('pulaDocumentos', () => {
  const novo = { id: 1, is_won: false };
  const fechado = { id: 7, label: 'fase-fechado', is_won: true };
  const documentos = { id: 8, label: 'fase-documentos', is_won: true };
  const etapas = [novo, fechado, documentos];
  const marcado = { thesis_passa_documentos: true };

  it('entrar no ganho por outra etapa, com a tese marcada e a etapa Documentos na conta: pede o motivo', () => {
    expect(pulaDocumentos(fechado, novo, marcado, etapas)).toBe(true);
  });

  it('entrar direto em Documentos, ou andar entre ganhos, não', () => {
    expect(pulaDocumentos(documentos, novo, marcado, etapas)).toBe(false);
    expect(pulaDocumentos(fechado, documentos, marcado, etapas)).toBe(false);
  });

  it('tese sem a chave ou conta sem a etapa Documentos: fluxo de hoje', () => {
    expect(pulaDocumentos(fechado, novo, {}, etapas)).toBe(false);
    expect(pulaDocumentos(fechado, novo, marcado, [novo, fechado])).toBe(false);
  });
});
