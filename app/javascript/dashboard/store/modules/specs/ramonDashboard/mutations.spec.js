import { mutations } from '../../ramonDashboard';
import types from '../../../mutation-types';

describe('ramonDashboard mutations', () => {
  it('SET_RAMON_DASHBOARD guarda o payload inteiro em data', () => {
    const baseState = { data: null, uiFlags: { isFetching: false } };
    const payload = { today: {}, funnel: [], week: {} };
    mutations[types.SET_RAMON_DASHBOARD](baseState, payload);
    expect(baseState.data).toEqual(payload);
  });

  it('SET_RAMON_DASHBOARD_UI_FLAG faz merge sem apagar flags anteriores', () => {
    const baseState = { data: null, uiFlags: { isFetching: false } };
    mutations[types.SET_RAMON_DASHBOARD_UI_FLAG](baseState, {
      isFetching: true,
    });
    expect(baseState.uiFlags).toEqual({ isFetching: true });
  });
});
