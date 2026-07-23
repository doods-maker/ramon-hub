import axios from 'axios';
import { actions } from '../../copilotSuggestions';
import types from '../../../mutation-types';

global.axios = axios;
vi.mock('axios');

describe('copilotSuggestions actions', () => {
  const commit = vi.fn();
  beforeEach(() => vi.clearAllMocks());

  it('fetch busca e faz SET_COPILOT_SUGGESTIONS com o payload', async () => {
    const data = { reviewed_count: 32, payload: [{ id: 1, kind: 'draft' }] };
    axios.get.mockResolvedValue({ data });
    await actions.fetch({ commit });
    expect(axios.get).toHaveBeenCalledWith(
      expect.stringContaining('/copilot_suggestions')
    );
    expect(commit).toHaveBeenCalledWith(types.SET_COPILOT_SUGGESTIONS, data);
    expect(commit).toHaveBeenLastCalledWith(
      types.SET_COPILOT_SUGGESTIONS_UI_FLAG,
      { isFetching: false }
    );
  });

  it('fetch marca hasError na falha em vez de sumir calado', async () => {
    axios.get.mockRejectedValue(new Error('boom'));
    await actions.fetch({ commit });
    expect(commit).toHaveBeenCalledWith(types.SET_COPILOT_SUGGESTIONS_UI_FLAG, {
      hasError: true,
    });
  });

  it('apply posta e remove o record local', async () => {
    axios.post.mockResolvedValue({ data: { id: 1, status: 'applied' } });
    await actions.apply({ commit }, 1);
    expect(axios.post).toHaveBeenCalledWith(
      expect.stringContaining('/copilot_suggestions/1/apply')
    );
    expect(commit).toHaveBeenCalledWith(types.DELETE_COPILOT_SUGGESTION, 1);
  });

  it('apply propaga o erro (move_stage sem etapa) e mantém o record', async () => {
    axios.post.mockRejectedValue(new Error('422'));
    await expect(actions.apply({ commit }, 1)).rejects.toThrow('422');
    expect(commit).not.toHaveBeenCalledWith(types.DELETE_COPILOT_SUGGESTION, 1);
  });

  it('dismiss posta e remove o record local', async () => {
    axios.post.mockResolvedValue({ data: {} });
    await actions.dismiss({ commit }, 2);
    expect(axios.post).toHaveBeenCalledWith(
      expect.stringContaining('/copilot_suggestions/2/dismiss')
    );
    expect(commit).toHaveBeenCalledWith(types.DELETE_COPILOT_SUGGESTION, 2);
  });

  it('applyAll remove só os ids que o backend aplicou (move_stage fica)', async () => {
    axios.post.mockResolvedValue({
      data: { payload: [{ id: 1 }, { id: 3 }] },
    });
    await actions.applyAll({ commit });
    expect(axios.post).toHaveBeenCalledWith(
      expect.stringContaining('/copilot_suggestions/apply_all')
    );
    expect(commit).toHaveBeenCalledWith(
      types.DELETE_COPILOT_SUGGESTIONS,
      [1, 3]
    );
  });
});
