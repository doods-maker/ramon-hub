import types from '../mutation-types';
import ThesesAPI from '../../api/theses';

export const state = {
  records: [],
  uiFlags: { isFetching: false },
};

const bySortedPosition = (a, b) => a.position - b.position;

export const getters = {
  getTheses: _state => [..._state.records].sort(bySortedPosition),
  getThesis: _state => id => _state.records.find(t => t.id === id),
  getUIFlags: _state => _state.uiFlags,
};

export const actions = {
  get: async ({ commit }) => {
    commit(types.SET_THESES_UI_FLAG, { isFetching: true });
    try {
      const { data } = await ThesesAPI.get();
      commit(types.SET_THESES, data);
    } finally {
      commit(types.SET_THESES_UI_FLAG, { isFetching: false });
    }
  },

  show: async ({ commit }, thesisId) => {
    const { data } = await ThesesAPI.show(thesisId);
    commit(types.EDIT_THESIS, data);
    return data;
  },

  create: async ({ commit }, payload) => {
    const { data } = await ThesesAPI.create(payload);
    commit(types.ADD_THESIS, data);
    return data;
  },

  update: async ({ commit }, { id, ...payload }) => {
    const { data } = await ThesesAPI.update(id, payload);
    commit(types.EDIT_THESIS, data);
    return data;
  },

  delete: async ({ commit }, id) => {
    await ThesesAPI.delete(id);
    commit(types.DELETE_THESIS, id);
  },

  reorder: async ({ commit }, ids) => {
    const { data } = await ThesesAPI.reorder(ids);
    commit(types.SET_THESES, data);
  },

  createItem: async ({ dispatch }, { thesisId, ...payload }) => {
    await ThesesAPI.createItem(thesisId, payload);
    return dispatch('show', thesisId);
  },

  updateItem: async ({ dispatch }, { thesisId, id, ...payload }) => {
    await ThesesAPI.updateItem(thesisId, id, payload);
    return dispatch('show', thesisId);
  },

  deleteItem: async ({ dispatch }, { thesisId, id }) => {
    await ThesesAPI.deleteItem(thesisId, id);
    return dispatch('show', thesisId);
  },

  reorderItems: async ({ dispatch }, { thesisId, ids }) => {
    await ThesesAPI.reorderItems(thesisId, ids);
    return dispatch('show', thesisId);
  },
};

export const mutations = {
  [types.SET_THESES_UI_FLAG](_state, data) {
    _state.uiFlags = { ..._state.uiFlags, ...data };
  },

  [types.SET_THESES](_state, data) {
    _state.records = [...data].sort(bySortedPosition);
  },

  [types.ADD_THESIS](_state, data) {
    _state.records = [..._state.records, data].sort(bySortedPosition);
  },

  [types.EDIT_THESIS](_state, data) {
    const exists = _state.records.some(t => t.id === data.id);
    _state.records = (
      exists
        ? _state.records.map(t => (t.id === data.id ? data : t))
        : [..._state.records, data]
    ).sort(bySortedPosition);
  },

  [types.DELETE_THESIS](_state, id) {
    _state.records = _state.records.filter(t => t.id !== id);
  },
};

export default { namespaced: true, state, getters, actions, mutations };
