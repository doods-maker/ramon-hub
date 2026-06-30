import axios from 'axios';
import { actions } from '../../leads';
import types from '../../../mutation-types';

global.axios = axios;
vi.mock('axios');

describe('leads actions', () => {
  it('get faz commit de SET_LEADS', async () => {
    axios.get.mockResolvedValue({
      data: { payload: [{ id: 1, name: 'João' }] },
    });
    const commit = vi.fn();
    await actions.get({ commit });
    expect(commit).toHaveBeenCalledWith(types.SET_LEAD_UI_FLAG, {
      isFetching: true,
    });
    expect(commit).toHaveBeenCalledWith(types.SET_LEADS, [
      { id: 1, name: 'João' },
    ]);
  });

  it('upsert faz commit de MERGE_LEAD', () => {
    const commit = vi.fn();
    actions.upsert({ commit }, { id: 7, name: 'Live' });
    expect(commit).toHaveBeenCalledWith(types.MERGE_LEAD, {
      id: 7,
      name: 'Live',
    });
  });

  it('select faz commit de SET_SELECTED_LEAD', () => {
    const commit = vi.fn();
    actions.select({ commit }, 42);
    expect(commit).toHaveBeenCalledWith(types.SET_SELECTED_LEAD, 42);
  });
});
