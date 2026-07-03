import { mutations } from '../../leadTasks';
import types from '../../../mutation-types';

describe('leadTasks mutations', () => {
  it('SET_LEAD_TASKS_UI_FLAG mescla as flags', () => {
    const state = { uiFlags: { isFetching: false, isCreating: false } };
    mutations[types.SET_LEAD_TASKS_UI_FLAG](state, { isCreating: true });
    expect(state.uiFlags).toEqual({ isFetching: false, isCreating: true });
  });

  it('MERGE_LEAD_TASKS faz upsert por id sem dropar tarefas de outros leads', () => {
    const state = {
      records: [
        { id: 1, lead_id: 10, title: 'A', due_at: '2026-07-01T00:00:00Z' },
        { id: 2, lead_id: 20, title: 'B', due_at: '2026-07-02T00:00:00Z' },
      ],
    };
    // resposta parcial (só tarefas do lead 10): atualiza a 1 e insere a 3,
    // mas NÃO pode apagar a 2 (de outro lead).
    mutations[types.MERGE_LEAD_TASKS](state, [
      { id: 1, lead_id: 10, title: 'A editada' },
      { id: 3, lead_id: 10, title: 'C' },
    ]);
    expect(state.records).toHaveLength(3);
    expect(state.records.find(t => t.id === 1)).toEqual({
      id: 1,
      lead_id: 10,
      title: 'A editada',
      due_at: '2026-07-01T00:00:00Z',
    });
    expect(state.records.find(t => t.id === 2)).toEqual({
      id: 2,
      lead_id: 20,
      title: 'B',
      due_at: '2026-07-02T00:00:00Z',
    });
    expect(state.records.find(t => t.id === 3)).toMatchObject({ id: 3 });
  });

  it('MERGE_LEAD_TASKS tolera payload vazio/ausente', () => {
    const state = { records: [{ id: 1 }] };
    mutations[types.MERGE_LEAD_TASKS](state, undefined);
    expect(state.records).toEqual([{ id: 1 }]);
  });

  it('MERGE_LEAD_TASK atualiza o record local (ex.: complete)', () => {
    const state = {
      records: [{ id: 1, lead_id: 10, title: 'A', completed_at: null }],
    };
    mutations[types.MERGE_LEAD_TASK](state, {
      id: 1,
      completed_at: '2026-07-03T12:00:00Z',
    });
    expect(state.records[0]).toEqual({
      id: 1,
      lead_id: 10,
      title: 'A',
      completed_at: '2026-07-03T12:00:00Z',
    });
  });

  it('MERGE_LEAD_TASK insere quando a tarefa ainda não existe', () => {
    const state = { records: [] };
    mutations[types.MERGE_LEAD_TASK](state, { id: 9, lead_id: 10 });
    expect(state.records).toEqual([{ id: 9, lead_id: 10 }]);
  });

  it('DELETE_LEAD_TASK remove a tarefa pelo id', () => {
    const state = { records: [{ id: 1 }, { id: 2 }] };
    mutations[types.DELETE_LEAD_TASK](state, 1);
    expect(state.records).toEqual([{ id: 2 }]);
  });
});
