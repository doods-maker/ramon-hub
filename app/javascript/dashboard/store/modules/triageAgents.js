import types from '../mutation-types';
import TriageAgentsAPI from '../../api/triageAgents';

export const state = {
  records: [],
  uiFlags: { isFetching: false },
};

const byId = (a, b) => a.id - b.id;

export const getters = {
  getAgents: _state => [..._state.records].sort(byId),
  getUIFlags: _state => _state.uiFlags,
};

export const actions = {
  get: async ({ commit }) => {
    commit(types.SET_TRIAGE_AGENTS_UI_FLAG, { isFetching: true });
    try {
      const { data } = await TriageAgentsAPI.get();
      commit(types.SET_TRIAGE_AGENTS, data);
    } finally {
      commit(types.SET_TRIAGE_AGENTS_UI_FLAG, { isFetching: false });
    }
  },

  create: async ({ commit }, payload) => {
    const { data } = await TriageAgentsAPI.create(payload);
    commit(types.ADD_TRIAGE_AGENT, data);
    return data;
  },

  update: async ({ commit }, { id, ...payload }) => {
    const { data } = await TriageAgentsAPI.update(id, payload);
    commit(types.EDIT_TRIAGE_AGENT, data);
    return data;
  },

  delete: async ({ commit }, id) => {
    await TriageAgentsAPI.delete(id);
    commit(types.DELETE_TRIAGE_AGENT, id);
  },
};

export const mutations = {
  [types.SET_TRIAGE_AGENTS_UI_FLAG](_state, data) {
    _state.uiFlags = { ..._state.uiFlags, ...data };
  },

  [types.SET_TRIAGE_AGENTS](_state, data) {
    const existingById = _state.records.reduce((acc, record) => {
      acc[record.id] = record;
      return acc;
    }, {});
    _state.records = data
      .map(incoming => ({ ...existingById[incoming.id], ...incoming }))
      .sort(byId);
  },

  [types.ADD_TRIAGE_AGENT](_state, data) {
    _state.records = [..._state.records, data].sort(byId);
  },

  [types.EDIT_TRIAGE_AGENT](_state, data) {
    const exists = _state.records.some(a => a.id === data.id);
    _state.records = (
      exists
        ? _state.records.map(a => (a.id === data.id ? data : a))
        : [..._state.records, data]
    ).sort(byId);
  },

  [types.DELETE_TRIAGE_AGENT](_state, id) {
    _state.records = _state.records.filter(a => a.id !== id);
  },
};

export default { namespaced: true, state, getters, actions, mutations };
