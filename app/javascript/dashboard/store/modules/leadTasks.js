import types from '../mutation-types';
import LeadTasksAPI from '../../api/leadTasks';

export const state = {
  records: [],
  uiFlags: { isFetching: false, isCreating: false, hasError: false },
};

// Ordena por due_at ascendente; tarefas sem prazo vão para o fim.
const byDueAtAsc = (a, b) => {
  if (!a.due_at && !b.due_at) return 0;
  if (!a.due_at) return 1;
  if (!b.due_at) return -1;
  return new Date(a.due_at) - new Date(b.due_at);
};

export const getters = {
  // Só tarefas abertas (completed_at null) do lead, ordenadas por prazo.
  getByLead: _state => leadId =>
    _state.records
      .filter(task => task.lead_id === leadId && !task.completed_at)
      .sort(byDueAtAsc),
  getAccountTasks: _state => [..._state.records].sort(byDueAtAsc),
  getUIFlags: _state => _state.uiFlags,
};

export const actions = {
  fetchForLead: async ({ commit }, leadId) => {
    commit(types.SET_LEAD_TASKS_UI_FLAG, { isFetching: true });
    try {
      const { data } = await LeadTasksAPI.get(leadId);
      commit(types.MERGE_LEAD_TASKS, data.payload);
    } finally {
      commit(types.SET_LEAD_TASKS_UI_FLAG, { isFetching: false });
    }
  },

  fetchAccountScope: async ({ commit }, scope) => {
    commit(types.SET_LEAD_TASKS_UI_FLAG, { isFetching: true, hasError: false });
    try {
      const { data } = await LeadTasksAPI.getAccountScope(scope);
      commit(types.MERGE_LEAD_TASKS, data.payload);
    } catch (e) {
      // Erro fica na flag: a Agenda mostra retry em vez de "sem compromissos".
      commit(types.SET_LEAD_TASKS_UI_FLAG, { hasError: true });
    } finally {
      commit(types.SET_LEAD_TASKS_UI_FLAG, { isFetching: false });
    }
  },

  create: async ({ commit }, { leadId, title, kind, dueAt }) => {
    commit(types.SET_LEAD_TASKS_UI_FLAG, { isCreating: true });
    try {
      const { data } = await LeadTasksAPI.create(leadId, {
        title,
        kind,
        due_at: dueAt,
      });
      commit(types.MERGE_LEAD_TASK, data);
      return data;
    } finally {
      commit(types.SET_LEAD_TASKS_UI_FLAG, { isCreating: false });
    }
  },

  // Marca como concluída e atualiza só o record local. Não refaz fetch de
  // leads: o broadcast lead.updated cuida de atualizar o card no Kanban.
  complete: async ({ commit }, { leadId, taskId }) => {
    const { data } = await LeadTasksAPI.complete(leadId, taskId);
    commit(types.MERGE_LEAD_TASK, data);
    return data;
  },

  destroy: async ({ commit }, { leadId, taskId }) => {
    await LeadTasksAPI.delete(leadId, taskId);
    commit(types.DELETE_LEAD_TASK, taskId);
  },
};

// Upsert por id: nunca substitui o array inteiro, para não perder tarefas de
// outros leads já em cache quando chega uma resposta parcial.
const mergeById = (records, incoming) => {
  const index = records.findIndex(record => record.id === incoming.id);
  if (index > -1) {
    records.splice(index, 1, { ...records[index], ...incoming });
  } else {
    records.push(incoming);
  }
};

export const mutations = {
  [types.SET_LEAD_TASKS_UI_FLAG](_state, data) {
    _state.uiFlags = { ..._state.uiFlags, ...data };
  },
  [types.MERGE_LEAD_TASKS](_state, data = []) {
    data.forEach(task => mergeById(_state.records, task));
  },
  [types.MERGE_LEAD_TASK](_state, data) {
    mergeById(_state.records, data);
  },
  [types.DELETE_LEAD_TASK](_state, id) {
    _state.records = _state.records.filter(task => task.id !== id);
  },
};

export default { namespaced: true, state, getters, actions, mutations };
