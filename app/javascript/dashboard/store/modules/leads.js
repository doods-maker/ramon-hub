import * as MutationHelpers from 'shared/helpers/vuex/mutationHelpers';
import types from '../mutation-types';
import LeadsAPI from '../../api/leads';

const FILTERS_KEY = 'ramon_lead_filters';

const toParams = (filters = {}) => {
  const map = {
    benefit_type_id: filters.benefitTypeId,
    lead_priority_id: filters.leadPriorityId,
    agent_id: filters.agentId,
    source: filters.source,
    channel: filters.channel,
    q: filters.q,
    lead_stage_id: filters.leadStageId,
    created_after: filters.createdAfter,
    created_before: filters.createdBefore,
    // booleanos só entram na query quando true, para não sujar a URL.
    stalled: filters.stalled || undefined,
    no_open_task: filters.noOpenTask || undefined,
  };
  return Object.fromEntries(
    Object.entries(map).filter(
      ([, v]) => v !== null && v !== undefined && v !== '' && v !== false
    )
  );
};

export const state = {
  records: [],
  selectedId: null,
  dockConversationId: null,
  filters: {
    benefitTypeId: null,
    leadPriorityId: null,
    agentId: null,
    source: '',
    channel: '',
    q: '',
    leadStageId: null,
    createdAfter: null,
    createdBefore: null,
    stalled: false,
    noOpenTask: false,
  },
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
  getDockConversationId(_state) {
    return _state.dockConversationId;
  },
  getFilters(_state) {
    return _state.filters;
  },
};

export const actions = {
  get: async ({ commit, state: moduleState = {} }) => {
    commit(types.SET_LEAD_UI_FLAG, { isFetching: true });
    try {
      const response = await LeadsAPI.get(toParams(moduleState.filters));
      commit(types.SET_LEADS, response.data.payload);
    } finally {
      commit(types.SET_LEAD_UI_FLAG, { isFetching: false });
    }
  },
  setFilters: async ({ commit, dispatch }, partial) => {
    commit(types.SET_LEAD_FILTERS, partial);
    try {
      const merged = JSON.parse(localStorage.getItem(FILTERS_KEY) || '{}');
      localStorage.setItem(
        FILTERS_KEY,
        JSON.stringify({ ...merged, ...partial })
      );
    } catch (e) {
      // localStorage indisponível: seguimos sem persistir
    }
    await dispatch('get');
  },
  loadFilters: async ({ commit, dispatch }) => {
    try {
      const saved = JSON.parse(localStorage.getItem(FILTERS_KEY) || '{}');
      if (Object.keys(saved).length) commit(types.SET_LEAD_FILTERS, saved);
    } catch (e) {
      // localStorage indisponível/corrompido: ignora
    }
    await dispatch('get');
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
  openDock: ({ commit }, conversationId) => {
    commit(types.SET_DOCK_CONVERSATION, conversationId);
  },
  closeDock: ({ commit }) => {
    commit(types.SET_DOCK_CONVERSATION, null);
  },
  // Alterna: se o dock já mostra esta conversa, fecha; senão, abre.
  toggleDock: ({ commit, state: dockState }, conversationId) => {
    const isSame =
      Number(dockState.dockConversationId) === Number(conversationId);
    commit(types.SET_DOCK_CONVERSATION, isSame ? null : conversationId);
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
  fetchNotes: async (_ctx, leadId) => {
    const response = await LeadsAPI.getNotes(leadId);
    return response.data.payload;
  },
  createNote: async (_ctx, { leadId, body }) => {
    const response = await LeadsAPI.createNote(leadId, body);
    return response.data;
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
  [types.SET_DOCK_CONVERSATION](_state, id) {
    _state.dockConversationId = id;
  },
  [types.SET_LEAD_FILTERS](_state, partial) {
    _state.filters = { ..._state.filters, ...partial };
  },
};

export default { namespaced: true, state, getters, actions, mutations };
