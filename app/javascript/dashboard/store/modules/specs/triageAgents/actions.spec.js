import axios from 'axios';
import { actions } from '../../triageAgents';
import types from '../../../mutation-types';

global.axios = axios;
vi.mock('axios');

describe('triageAgents actions', () => {
  afterEach(() => {
    vi.clearAllMocks();
  });

  it('get faz commit de SET_TRIAGE_AGENTS', async () => {
    const agents = [
      { id: 1, name: 'Triagem Previdenciária' },
      { id: 2, name: 'Triagem Trabalhista' },
    ];
    axios.get.mockResolvedValue({ data: agents });
    const commit = vi.fn();
    await actions.get({ commit });
    expect(commit).toHaveBeenCalledWith(types.SET_TRIAGE_AGENTS_UI_FLAG, {
      isFetching: true,
    });
    expect(commit).toHaveBeenCalledWith(types.SET_TRIAGE_AGENTS, agents);
    expect(commit).toHaveBeenCalledWith(types.SET_TRIAGE_AGENTS_UI_FLAG, {
      isFetching: false,
    });
  });

  it('create posta o agente e faz commit de ADD_TRIAGE_AGENT', async () => {
    const agent = { id: 3, name: 'Novo agente' };
    axios.post.mockResolvedValue({ data: agent });
    const commit = vi.fn();
    const result = await actions.create({ commit }, { name: 'Novo agente' });
    expect(commit).toHaveBeenCalledWith(types.ADD_TRIAGE_AGENT, agent);
    expect(result).toEqual(agent);
  });

  it('update faz patch e commit de EDIT_TRIAGE_AGENT', async () => {
    const agent = { id: 1, name: 'Renomeado' };
    axios.patch.mockResolvedValue({ data: agent });
    const commit = vi.fn();
    const result = await actions.update(
      { commit },
      { id: 1, name: 'Renomeado' }
    );
    expect(axios.patch).toHaveBeenCalledWith(
      expect.stringContaining('/triage_agents/1'),
      { name: 'Renomeado' }
    );
    expect(commit).toHaveBeenCalledWith(types.EDIT_TRIAGE_AGENT, agent);
    expect(result).toEqual(agent);
  });

  it('delete remove o agente e faz commit de DELETE_TRIAGE_AGENT', async () => {
    axios.delete.mockResolvedValue({});
    const commit = vi.fn();
    await actions.delete({ commit }, 1);
    expect(commit).toHaveBeenCalledWith(types.DELETE_TRIAGE_AGENT, 1);
  });
});
