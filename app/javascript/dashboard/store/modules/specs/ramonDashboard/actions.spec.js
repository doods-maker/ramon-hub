import axios from 'axios';
import { actions } from '../../ramonDashboard';
import types from '../../../mutation-types';

global.axios = axios;
vi.mock('axios');

describe('ramonDashboard actions', () => {
  const commit = vi.fn();
  beforeEach(() => vi.clearAllMocks());

  it('fetch busca o agregado, popula data e cicla o isFetching', async () => {
    const data = {
      today: { tasks_overdue: { count: 0, items: [] } },
      funnel: [{ stage_id: 1, name: 'Novo', count: 3 }],
      week: { created: 2, won: 1, lost: 0 },
    };
    axios.get.mockResolvedValue({ data });

    await actions.fetch({ commit });

    expect(axios.get).toHaveBeenCalledWith(
      expect.stringContaining('/ramon_dashboard')
    );
    expect(commit).toHaveBeenCalledWith(types.SET_RAMON_DASHBOARD_UI_FLAG, {
      isFetching: true,
    });
    expect(commit).toHaveBeenCalledWith(types.SET_RAMON_DASHBOARD, data);
    expect(commit).toHaveBeenLastCalledWith(types.SET_RAMON_DASHBOARD_UI_FLAG, {
      isFetching: false,
    });
  });

  it('fetch desliga o isFetching mesmo quando a requisição falha', async () => {
    axios.get.mockRejectedValue(new Error('boom'));

    await expect(actions.fetch({ commit })).rejects.toThrow('boom');

    expect(commit).toHaveBeenLastCalledWith(types.SET_RAMON_DASHBOARD_UI_FLAG, {
      isFetching: false,
    });
  });
});
