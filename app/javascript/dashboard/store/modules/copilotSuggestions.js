import types from '../mutation-types';
import CopilotSuggestionsAPI from '../../api/copilotSuggestions';

// Copiloto noturno (mock 4b): records = só sugestões pendentes; aplicar ou
// descartar remove do array (o bloco some sozinho quando zera).
export const state = {
  records: [],
  meta: { reviewedCount: 0 },
  uiFlags: { isFetching: false, isApplying: false, hasError: false },
};

export const getters = {
  getSuggestions: _state => _state.records,
  getMeta: _state => _state.meta,
  getUIFlags: _state => _state.uiFlags,
};

export const actions = {
  fetch: async ({ commit }) => {
    commit(types.SET_COPILOT_SUGGESTIONS_UI_FLAG, {
      isFetching: true,
      hasError: false,
    });
    try {
      const { data } = await CopilotSuggestionsAPI.get();
      commit(types.SET_COPILOT_SUGGESTIONS, data);
    } catch (e) {
      // Erro fica na flag: o bloco mostra retry em vez de sumir calado.
      commit(types.SET_COPILOT_SUGGESTIONS_UI_FLAG, { hasError: true });
    } finally {
      commit(types.SET_COPILOT_SUGGESTIONS_UI_FLAG, { isFetching: false });
    }
  },

  apply: async ({ commit }, id) => {
    commit(types.SET_COPILOT_SUGGESTIONS_UI_FLAG, { isApplying: true });
    try {
      await CopilotSuggestionsAPI.apply(id);
      commit(types.DELETE_COPILOT_SUGGESTION, id);
    } finally {
      commit(types.SET_COPILOT_SUGGESTIONS_UI_FLAG, { isApplying: false });
    }
  },

  dismiss: async ({ commit }, id) => {
    await CopilotSuggestionsAPI.dismiss(id);
    commit(types.DELETE_COPILOT_SUGGESTION, id);
  },

  // Só drafts/alerts saem daqui (regra do backend): move_stage fica no card.
  applyAll: async ({ commit }) => {
    commit(types.SET_COPILOT_SUGGESTIONS_UI_FLAG, { isApplying: true });
    try {
      const { data } = await CopilotSuggestionsAPI.applyAll();
      commit(
        types.DELETE_COPILOT_SUGGESTIONS,
        (data.payload || []).map(s => s.id)
      );
    } finally {
      commit(types.SET_COPILOT_SUGGESTIONS_UI_FLAG, { isApplying: false });
    }
  },
};

export const mutations = {
  [types.SET_COPILOT_SUGGESTIONS_UI_FLAG](_state, data) {
    _state.uiFlags = { ..._state.uiFlags, ...data };
  },
  [types.SET_COPILOT_SUGGESTIONS](_state, data) {
    _state.records = data.payload || [];
    _state.meta = { reviewedCount: data.reviewed_count || 0 };
  },
  [types.DELETE_COPILOT_SUGGESTION](_state, id) {
    _state.records = _state.records.filter(s => s.id !== id);
  },
  [types.DELETE_COPILOT_SUGGESTIONS](_state, ids) {
    _state.records = _state.records.filter(s => !ids.includes(s.id));
  },
};

export default { namespaced: true, state, getters, actions, mutations };
