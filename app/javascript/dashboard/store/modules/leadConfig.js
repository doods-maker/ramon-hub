import types from '../mutation-types';
import LeadConfigAPI from '../../api/leadConfig';

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
};

export default { namespaced: true, state, getters, actions, mutations };
