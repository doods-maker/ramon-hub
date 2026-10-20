import types from '../mutation-types';
import LeadConfigAPI from '../../api/leadConfig';
import LeadStagesAPI from '../../api/leadStages';
import LeadPrioritiesAPI from '../../api/leadPriorities';

export const state = {
  stages: [],
  priorities: [],
  sources: [],
  channels: [],
  lostReasons: [],
  uiFlags: { isFetching: false },
};

export const getters = {
  // stages guarda o objeto inteiro do stage → probability e
  // stalled_after_days fazem pass-through sem tratamento extra.
  getStages: _state => _state.stages,
  getPriorities: _state => _state.priorities,
  getSources: _state => _state.sources,
  getChannels: _state => _state.channels,
  getLostReasons: _state => _state.lostReasons,
};

const bySortedPosition = (a, b) => a.position - b.position;

export const actions = {
  get: async ({ commit }) => {
    commit(types.SET_LEAD_UI_FLAG, { isFetching: true });
    try {
      const response = await LeadConfigAPI.get();
      commit(types.SET_LEAD_CONFIG, response.data);
    } finally {
      commit(types.SET_LEAD_UI_FLAG, { isFetching: false });
    }
  },

  createStage: async ({ commit }, payload) => {
    const { data } = await LeadStagesAPI.create(payload);
    commit(types.ADD_LEAD_STAGE, data);
    return data;
  },
  updateStage: async ({ commit }, { id, ...payload }) => {
    const { data } = await LeadStagesAPI.update(id, payload);
    commit(types.EDIT_LEAD_STAGE, data);
    return data;
  },
  deleteStage: async ({ commit }, { id, moveToStageId }) => {
    await LeadStagesAPI.delete(id, {
      params: { move_to_stage_id: moveToStageId },
    });
    commit(types.DELETE_LEAD_STAGE, id);
  },
  reorderStages: async ({ commit }, ids) => {
    const { data } = await LeadStagesAPI.reorder(ids);
    commit(types.SET_LEAD_STAGES, data);
  },

  createPriority: async ({ commit }, payload) => {
    const { data } = await LeadPrioritiesAPI.create(payload);
    commit(types.ADD_LEAD_PRIORITY, data);
    return data;
  },
  updatePriority: async ({ commit }, { id, ...payload }) => {
    const { data } = await LeadPrioritiesAPI.update(id, payload);
    commit(types.EDIT_LEAD_PRIORITY, data);
    return data;
  },
  deletePriority: async ({ commit }, id) => {
    await LeadPrioritiesAPI.delete(id);
    commit(types.DELETE_LEAD_PRIORITY, id);
  },
  reorderPriorities: async ({ commit }, ids) => {
    const { data } = await LeadPrioritiesAPI.reorder(ids);
    commit(types.SET_LEAD_PRIORITIES, data);
  },
};

export const mutations = {
  [types.SET_LEAD_UI_FLAG](_state, data) {
    _state.uiFlags = { ..._state.uiFlags, ...data };
  },
  [types.SET_LEAD_CONFIG](_state, data) {
    _state.stages = data.stages || [];
    _state.priorities = data.priorities || [];
    _state.sources = data.sources || [];
    _state.channels = data.channels || [];
    _state.lostReasons = data.lost_reasons || [];
  },

  [types.SET_LEAD_STAGES](_state, data) {
    _state.stages = [...data].sort(bySortedPosition);
  },
  [types.ADD_LEAD_STAGE](_state, data) {
    _state.stages = [..._state.stages, data].sort(bySortedPosition);
  },
  [types.EDIT_LEAD_STAGE](_state, data) {
    _state.stages = _state.stages
      .map(s => (s.id === data.id ? data : s))
      .sort(bySortedPosition);
  },
  [types.DELETE_LEAD_STAGE](_state, id) {
    _state.stages = _state.stages.filter(s => s.id !== id);
  },

  [types.SET_LEAD_PRIORITIES](_state, data) {
    _state.priorities = [...data].sort(bySortedPosition);
  },
  [types.ADD_LEAD_PRIORITY](_state, data) {
    _state.priorities = [..._state.priorities, data].sort(bySortedPosition);
  },
  [types.EDIT_LEAD_PRIORITY](_state, data) {
    _state.priorities = _state.priorities
      .map(p => (p.id === data.id ? data : p))
      .sort(bySortedPosition);
  },
  [types.DELETE_LEAD_PRIORITY](_state, id) {
    _state.priorities = _state.priorities.filter(p => p.id !== id);
  },
};

export default { namespaced: true, state, getters, actions, mutations };
