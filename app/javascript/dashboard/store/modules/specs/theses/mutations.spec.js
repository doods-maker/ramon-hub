import { mutations } from '../../theses';
import types from '../../../mutation-types';

describe('theses mutations', () => {
  it('SET_THESES_UI_FLAG mescla as flags', () => {
    const state = { uiFlags: { isFetching: false } };
    mutations[types.SET_THESES_UI_FLAG](state, { isFetching: true });
    expect(state.uiFlags).toEqual({ isFetching: true });
  });

  it('SET_THESES popula e ordena por position', () => {
    const state = { records: [] };
    mutations[types.SET_THESES](state, [
      { id: 2, position: 1 },
      { id: 1, position: 0 },
    ]);
    expect(state.records).toEqual([
      { id: 1, position: 0 },
      { id: 2, position: 1 },
    ]);
  });

  it('SET_THESES mescla payload leve (reorder/index) preservando campos enriquecidos por show', () => {
    const state = {
      records: [
        {
          id: 1,
          position: 0,
          name: 'Tese 1',
          description: 'Descrição detalhada',
          items: [{ id: 10, title: 'Item' }],
        },
        {
          id: 2,
          position: 1,
          name: 'Tese 2',
          description: 'Outra descrição',
          items: [],
        },
      ],
    };
    // payload leve de reorder/index: sem description nem items
    mutations[types.SET_THESES](state, [
      { id: 2, position: 0, name: 'Tese 2' },
      { id: 1, position: 1, name: 'Tese 1' },
    ]);
    expect(state.records).toEqual([
      {
        id: 2,
        position: 0,
        name: 'Tese 2',
        description: 'Outra descrição',
        items: [],
      },
      {
        id: 1,
        position: 1,
        name: 'Tese 1',
        description: 'Descrição detalhada',
        items: [{ id: 10, title: 'Item' }],
      },
    ]);
  });

  it('ADD_THESIS adiciona e mantém a ordenação por position', () => {
    const state = { records: [{ id: 1, position: 0 }] };
    mutations[types.ADD_THESIS](state, { id: 2, position: -1 });
    expect(state.records).toEqual([
      { id: 2, position: -1 },
      { id: 1, position: 0 },
    ]);
  });

  it('EDIT_THESIS substitui a tese existente', () => {
    const state = {
      records: [
        { id: 1, name: 'Antiga', position: 0 },
        { id: 2, name: 'Outra', position: 1 },
      ],
    };
    mutations[types.EDIT_THESIS](state, {
      id: 1,
      name: 'Nova',
      position: 0,
    });
    expect(state.records).toEqual([
      { id: 1, name: 'Nova', position: 0 },
      { id: 2, name: 'Outra', position: 1 },
    ]);
  });

  it('EDIT_THESIS adiciona a tese quando ela ainda não existe (ex.: show)', () => {
    const state = { records: [{ id: 1, name: 'Existente', position: 0 }] };
    mutations[types.EDIT_THESIS](state, {
      id: 2,
      name: 'Nova via show',
      position: 1,
    });
    expect(state.records).toEqual([
      { id: 1, name: 'Existente', position: 0 },
      { id: 2, name: 'Nova via show', position: 1 },
    ]);
  });

  it('DELETE_THESIS remove a tese pelo id', () => {
    const state = {
      records: [
        { id: 1, position: 0 },
        { id: 2, position: 1 },
      ],
    };
    mutations[types.DELETE_THESIS](state, 1);
    expect(state.records).toEqual([{ id: 2, position: 1 }]);
  });
});
