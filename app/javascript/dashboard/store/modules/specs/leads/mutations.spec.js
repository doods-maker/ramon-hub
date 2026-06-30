import { mutations } from '../../leads';
import types from '../../../mutation-types';

describe('leads mutations', () => {
  it('MERGE_LEAD funde sobre o registro existente sem dropar campos', () => {
    const state = { records: [{ id: 1, name: 'Ana', notes: 'manter' }] };
    mutations[types.MERGE_LEAD](state, {
      id: 1,
      name: 'Ana Maria',
      value: 100,
    });
    expect(state.records[0]).toEqual({
      id: 1,
      name: 'Ana Maria',
      notes: 'manter',
      value: 100,
    });
  });

  it('MERGE_LEAD insere quando o lead não existe', () => {
    const state = { records: [] };
    mutations[types.MERGE_LEAD](state, { id: 9, name: 'Novo' });
    expect(state.records).toHaveLength(1);
    expect(state.records[0].id).toBe(9);
  });

  it('SET_SELECTED_LEAD guarda o id selecionado', () => {
    const state = { selectedId: null };
    mutations[types.SET_SELECTED_LEAD](state, 5);
    expect(state.selectedId).toBe(5);
  });
});
