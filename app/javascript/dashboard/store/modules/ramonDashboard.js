import types from '../mutation-types';
import RamonDashboardAPI from '../../api/ramonDashboard';

export const state = {
  data: null,
  uiFlags: { isFetching: false, hasError: false },
};

export const getters = {
  getData: _state => _state.data,
  getUIFlags: _state => _state.uiFlags,
};

export const actions = {
  fetch: async ({ commit }) => {
    commit(types.SET_RAMON_DASHBOARD_UI_FLAG, {
      isFetching: true,
      hasError: false,
    });
    try {
      const response = await RamonDashboardAPI.get();
      commit(types.SET_RAMON_DASHBOARD, response.data);
    } catch (e) {
      // Erro fica na flag: a página mostra retry em vez de "tudo em dia".
      commit(types.SET_RAMON_DASHBOARD_UI_FLAG, { hasError: true });
    } finally {
      commit(types.SET_RAMON_DASHBOARD_UI_FLAG, { isFetching: false });
    }
  },
};

export const mutations = {
  [types.SET_RAMON_DASHBOARD_UI_FLAG](_state, data) {
    _state.uiFlags = { ..._state.uiFlags, ...data };
  },
  [types.SET_RAMON_DASHBOARD](_state, data) {
    _state.data = data;
  },
};

export default { namespaced: true, state, getters, actions, mutations };
