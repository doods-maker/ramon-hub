import { mutations } from '../../triageAgents';
import types from '../../../mutation-types';

describe('triageAgents mutations', () => {
  it('SET_TRIAGE_AGENTS_UI_FLAG mescla as flags', () => {
    const state = { uiFlags: { isFetching: false } };
    mutations[types.SET_TRIAGE_AGENTS_UI_FLAG](state, { isFetching: true });
    expect(state.uiFlags).toEqual({ isFetching: true });
  });

  it('SET_TRIAGE_AGENTS popula e ordena por id', () => {
    const state = { records: [] };
    mutations[types.SET_TRIAGE_AGENTS](state, [
      { id: 2, name: 'Agente 2' },
      { id: 1, name: 'Agente 1' },
    ]);
    expect(state.records).toEqual([
      { id: 1, name: 'Agente 1' },
      { id: 2, name: 'Agente 2' },
    ]);
  });

  it('SET_TRIAGE_AGENTS mescla payload preservando campos existentes', () => {
    const state = {
      records: [{ id: 1, name: 'Agente 1', system_prompt: 'Prompt longo' }],
    };
    mutations[types.SET_TRIAGE_AGENTS](state, [{ id: 1, name: 'Renomeado' }]);
    expect(state.records).toEqual([
      { id: 1, name: 'Renomeado', system_prompt: 'Prompt longo' },
    ]);
  });

  it('ADD_TRIAGE_AGENT adiciona e mantém a ordenação por id', () => {
    const state = { records: [{ id: 2, name: 'Agente 2' }] };
    mutations[types.ADD_TRIAGE_AGENT](state, { id: 1, name: 'Agente 1' });
    expect(state.records).toEqual([
      { id: 1, name: 'Agente 1' },
      { id: 2, name: 'Agente 2' },
    ]);
  });

  it('EDIT_TRIAGE_AGENT substitui o agente existente', () => {
    const state = {
      records: [
        { id: 1, name: 'Antigo' },
        { id: 2, name: 'Outro' },
      ],
    };
    mutations[types.EDIT_TRIAGE_AGENT](state, { id: 1, name: 'Novo' });
    expect(state.records).toEqual([
      { id: 1, name: 'Novo' },
      { id: 2, name: 'Outro' },
    ]);
  });

  it('EDIT_TRIAGE_AGENT adiciona o agente quando ele ainda não existe', () => {
    const state = { records: [{ id: 1, name: 'Existente' }] };
    mutations[types.EDIT_TRIAGE_AGENT](state, { id: 2, name: 'Novo' });
    expect(state.records).toEqual([
      { id: 1, name: 'Existente' },
      { id: 2, name: 'Novo' },
    ]);
  });

  it('DELETE_TRIAGE_AGENT remove o agente pelo id', () => {
    const state = {
      records: [
        { id: 1, name: 'Agente 1' },
        { id: 2, name: 'Agente 2' },
      ],
    };
    mutations[types.DELETE_TRIAGE_AGENT](state, 1);
    expect(state.records).toEqual([{ id: 2, name: 'Agente 2' }]);
  });
});
