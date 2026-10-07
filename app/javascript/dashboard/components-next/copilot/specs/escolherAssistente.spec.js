import { escolherAssistente } from '../escolherAssistente';

const ATENDIMENTO = { id: 1, name: 'Atendimento' };
const COPILOTO = { id: 2, name: 'Copiloto do Escritório' };
const base = {
  assistants: [ATENDIMENTO, COPILOTO],
  preferredId: null,
  equipeIds: [2],
  inboxAssistantId: 1,
};

describe('assistente do painel do Copiloto', () => {
  it('abre no assistente da equipe, mesmo com a caixa ligada ao Atendimento', () => {
    expect(escolherAssistente(base)).toBe(COPILOTO);
  });

  it('a escolha da pessoa vence', () => {
    expect(escolherAssistente({ ...base, preferredId: 1 })).toBe(ATENDIMENTO);
  });

  it('sem assistente da equipe (ou stats falhou): o da caixa, como antes', () => {
    expect(escolherAssistente({ ...base, equipeIds: [] })).toBe(ATENDIMENTO);
  });

  it('sem nada: o primeiro; sem assistentes: nenhum', () => {
    expect(
      escolherAssistente({ ...base, equipeIds: [], inboxAssistantId: null })
    ).toBe(ATENDIMENTO);
    expect(escolherAssistente({ ...base, assistants: [] })).toBeUndefined();
  });
});
