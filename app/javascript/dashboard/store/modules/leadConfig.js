import types from '../mutation-types';
import LeadConfigAPI from '../../api/leadConfig';
import LeadStagesAPI from '../../api/leadStages';
import BenefitTypesAPI from '../../api/benefitTypes';
import LeadPrioritiesAPI from '../../api/leadPriorities';

export const state = {
  stages: [],
  benefitTypes: [],
  priorities: [],
  uiFlags: { isFetching: false },
};

export const getters = {
  getStages: _state => _state.stages,
  getBenefitTypes: _state => _state.benefitTypes,
  getPriorities: _state => _state.priorities,
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

  createBenefitType: async ({ commit }, payload) => {
    const { data } = await BenefitTypesAPI.create(payload);
    commit(types.ADD_BENEFIT_TYPE, data);
    return data;
  },
  updateBenefitType: async ({ commit }, { id, ...payload }) => {
    const { data } = await BenefitTypesAPI.update(id, payload);
    commit(types.EDIT_BENEFIT_TYPE, data);
    return data;
  },
  deleteBenefitType: async ({ commit }, id) => {
    await BenefitTypesAPI.delete(id);
    commit(types.DELETE_BENEFIT_TYPE, id);
  },
  reorderBenefitTypes: async ({ commit }, ids) => {
    const { data } = await BenefitTypesAPI.reorder(ids);
    commit(types.SET_BENEFIT_TYPES, data);
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
    _state.benefitTypes = data.benefit_types || [];
    _state.priorities = data.priorities || [];
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

  [types.SET_BENEFIT_TYPES](_state, data) {
    _state.benefitTypes = [...data].sort(bySortedPosition);
  },
  [types.ADD_BENEFIT_TYPE](_state, data) {
    _state.benefitTypes = [..._state.benefitTypes, data].sort(bySortedPosition);
  },
  [types.EDIT_BENEFIT_TYPE](_state, data) {
    _state.benefitTypes = _state.benefitTypes
      .map(b => (b.id === data.id ? data : b))
      .sort(bySortedPosition);
  },
  [types.DELETE_BENEFIT_TYPE](_state, id) {
    _state.benefitTypes = _state.benefitTypes.filter(b => b.id !== id);
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
