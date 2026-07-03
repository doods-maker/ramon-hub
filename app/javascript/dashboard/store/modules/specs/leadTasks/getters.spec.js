import { getters } from '../../leadTasks';

describe('leadTasks getters', () => {
  it('getByLead retorna só as abertas do lead, ordenadas por due_at asc', () => {
    const state = {
      records: [
        { id: 1, lead_id: 10, due_at: '2026-07-05', completed_at: null },
        { id: 2, lead_id: 10, due_at: '2026-07-02', completed_at: null },
        // concluída → excluída
        { id: 3, lead_id: 10, due_at: '2026-07-01', completed_at: 'x' },
        // outro lead → excluída
        { id: 4, lead_id: 20, due_at: '2026-07-03', completed_at: null },
      ],
    };
    const result = getters.getByLead(state)(10);
    expect(result.map(t => t.id)).toEqual([2, 1]);
  });

  it('getByLead joga tarefas sem prazo para o fim', () => {
    const state = {
      records: [
        { id: 1, lead_id: 10, due_at: null, completed_at: null },
        { id: 2, lead_id: 10, due_at: '2026-07-02', completed_at: null },
      ],
    };
    expect(getters.getByLead(state)(10).map(t => t.id)).toEqual([2, 1]);
  });

  it('getAccountTasks retorna todos os records ordenados por due_at asc', () => {
    const state = {
      records: [
        { id: 1, due_at: '2026-07-05T00:00:00Z' },
        { id: 2, due_at: '2026-07-01T00:00:00Z' },
      ],
    };
    expect(getters.getAccountTasks(state).map(t => t.id)).toEqual([2, 1]);
  });

  it('getUIFlags retorna as uiFlags do estado', () => {
    const state = { uiFlags: { isFetching: true, isCreating: false } };
    expect(getters.getUIFlags(state)).toEqual({
      isFetching: true,
      isCreating: false,
    });
  });
});
