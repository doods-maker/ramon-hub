import * as MutationHelpers from 'shared/helpers/vuex/mutationHelpers';
import types from '../mutation-types';
import LeadsAPI from '../../api/leads';

export const state = {
  records: [],
  uiFlags: { isFetching: false, isCreating: false, isUpdating: false, isDeleting: false },
};

export const getters = {
  getLeads(_state) {
    return _state.records;
  },
  getLeadsByStage: _state => stageId =>
    _state.records
      .filter(lead => lead.lead_stage_id === stageId)
      .sort((a, b) => a.position - b.position),
  getUIFlags(_state) {
    return _state.uiFlags;
  },
};

export const actions = {
  get: async ({ commit }) => {
    commit(types.SET_LEAD_UI_FLAG, { isFetching: true });
    try {
      const response = await LeadsAPI.get();
      commit(types.SET_LEADS, response.data.payload);
    } finally {
      commit(types.SET_LEAD_UI_FLAG, { isFetching: false });
    }
  },
  create: async ({ commit }, payload) => {
    commit(types.SET_LEAD_UI_FLAG, { isCreating: true });
    try {
      const response = await LeadsAPI.create(payload);
      commit(types.ADD_LEAD, response.data);
      return response.data;
    } finally {
      commit(types.SET_LEAD_UI_FLAG, { isCreating: false });
    }
  },
  update: async ({ commit }, { id, ...payload }) => {
    const response = await LeadsAPI.update(id, payload);
    commit(types.EDIT_LEAD, response.data);
    return response.data;
  },
  move: async ({ commit }, { id, leadStageId, position }) => {
    const response = await LeadsAPI.update(id, { lead_stage_id: leadStageId, position });
    commit(types.EDIT_LEAD, response.data);
  },
  upsert: ({ commit }, lead) => {
    commit(types.EDIT_LEAD, lead);
  },
  delete: async ({ commit }, id) => {
    await LeadsAPI.delete(id);
    commit(types.DELETE_LEAD, id);
  },
};

export const mutations = {
  [types.SET_LEAD_UI_FLAG](_state, data) {
    _state.uiFlags = { ..._state.uiFlags, ...data };
  },
  [types.SET_LEADS]: MutationHelpers.set,
  [types.ADD_LEAD]: MutationHelpers.create,
  [types.EDIT_LEAD]: MutationHelpers.setSingleRecord,
  [types.DELETE_LEAD]: MutationHelpers.destroy,
};

export default { namespaced: true, state, getters, actions, mutations };
