import { mutations } from '../../ramonDashboard';
import types from '../../../mutation-types';

describe('ramonDashboard mutations', () => {
  it('SET_RAMON_DASHBOARD guarda o payload inteiro em data', () => {
    const _state = { data: null, uiFlags: { isFetching: false } };
    const payload = { today: {}, funnel: [], week: {} };
    mutations[types.SET_RAMON_DASHBOARD](_state, payload);
    expect(_state.data).toEqual(payload);
  });

  it('SET_RAMON_DASHBOARD_UI_FLAG faz merge sem apagar flags anteriores', () => {
    const _state = { data: null, uiFlags: { isFetching: false } };
    mutations[types.SET_RAMON_DASHBOARD_UI_FLAG](_state, { isFetching: true });
    expect(_state.uiFlags).toEqual({ isFetching: true });
  });
});
