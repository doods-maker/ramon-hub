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
  const marcado = { thesis_passa_documentos: true, docs_total: 3 };

  it('chave ligada, etapa Documentos na conta, tese marcada e com checklist: pede o motivo', () => {
    expect(pulaDocumentos(fechado, novo, marcado, etapas, true)).toBe(true);
  });

  it('chave desligada: nada muda', () => {
    expect(pulaDocumentos(fechado, novo, marcado, etapas, false)).toBe(false);
  });

  it('tese marcada sem checklist de documentos: o ganho cai em Fechado mesmo, sem motivo', () => {
    const semChecklist = { thesis_passa_documentos: true, docs_total: 0 };
    expect(pulaDocumentos(fechado, novo, semChecklist, etapas, true)).toBe(
      false
    );
  });

  it('entrar direto em Documentos, ou andar entre ganhos, não', () => {
    expect(pulaDocumentos(documentos, novo, marcado, etapas, true)).toBe(false);
    expect(pulaDocumentos(fechado, documentos, marcado, etapas, true)).toBe(
      false
    );
  });

  it('tese sem a chave ou conta sem a etapa Documentos: fluxo de hoje', () => {
    expect(pulaDocumentos(fechado, novo, { docs_total: 3 }, etapas, true)).toBe(
      false
    );
    expect(pulaDocumentos(fechado, novo, marcado, [novo, fechado], true)).toBe(
      false
    );
  });
});
