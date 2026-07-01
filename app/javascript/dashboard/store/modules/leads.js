import * as MutationHelpers from 'shared/helpers/vuex/mutationHelpers';
import types from '../mutation-types';
import LeadsAPI from '../../api/leads';

export const state = {
  records: [],
  selectedId: null,
  uiFlags: {
    isFetching: false,
    isCreating: false,
    isUpdating: false,
    isDeleting: false,
  },
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
  getSelectedLead(_state) {
    return _state.records.find(lead => lead.id === _state.selectedId) || null;
  },
  getLeadByConversationId: _state => conversationId =>
    _state.records.find(lead => lead.conversation_id === conversationId),
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
    const response = await LeadsAPI.update(id, {
      lead_stage_id: leadStageId,
      position,
    });
    commit(types.EDIT_LEAD, response.data);
  },
  upsert: ({ commit }, lead) => {
    commit(types.MERGE_LEAD, lead);
  },
  select: ({ commit }, id) => {
    commit(types.SET_SELECTED_LEAD, id);
  },
  delete: async ({ commit }, id) => {
    await LeadsAPI.delete(id);
    commit(types.DELETE_LEAD, id);
  },
  ensureForConversation: async ({ commit }, { conversationId }) => {
    const response = await LeadsAPI.forConversation(conversationId);
    const lead = response.data;
    commit(types.MERGE_LEAD, lead);
    commit(types.SET_SELECTED_LEAD, lead.id);
    return lead;
  },
  fetchActivities: async (_ctx, leadId) => {
    const response = await LeadsAPI.getActivities(leadId);
    return response.data.payload;
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
  [types.MERGE_LEAD](_state, data) {
    const index = _state.records.findIndex(record => record.id === data.id);
    if (index > -1) {
      _state.records[index] = { ..._state.records[index], ...data };
    } else {
      _state.records.push(data);
    }
  },
  [types.SET_SELECTED_LEAD](_state, id) {
    _state.selectedId = id;
  },
};

export default { namespaced: true, state, getters, actions, mutations };
