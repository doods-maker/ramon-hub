import axios from 'axios';
import { actions } from '../../leads';
import types from '../../../mutation-types';

global.axios = axios;
vi.mock('axios');

describe('leads filters', () => {
  const commit = vi.fn();
  const dispatch = vi.fn();
  beforeEach(() => {
    vi.clearAllMocks();
    localStorage.clear();
  });

  it('setFilters comita, persiste e re-busca', async () => {
    await actions.setFilters({ commit, dispatch }, { benefitTypeId: 5 });
    expect(commit).toHaveBeenCalledWith(types.SET_LEAD_FILTERS, {
      benefitTypeId: 5,
    });
    expect(JSON.parse(localStorage.getItem('ramon_lead_filters'))).toEqual({
      benefitTypeId: 5,
    });
    expect(dispatch).toHaveBeenCalledWith('get');
  });

  it('get envia os filtros como params snake_case, omitindo vazios', async () => {
    axios.get.mockResolvedValue({ data: { payload: [] } });
    const state = {
      filters: { benefitTypeId: 5, agentId: null, source: '', q: 'ana' },
    };
    await actions.get({ commit, state });
    expect(axios.get).toHaveBeenCalledWith(expect.any(String), {
      params: { benefit_type_id: 5, q: 'ana' },
    });
  });

  it('get envia os filtros de cadência, omitindo booleanos false', async () => {
    axios.get.mockResolvedValue({ data: { payload: [] } });
    const state = {
      filters: {
        leadStageId: 7,
        createdAfter: '2026-07-01',
        createdBefore: null,
        stalled: true,
        noOpenTask: false,
      },
    };
    await actions.get({ commit, state });
    expect(axios.get).toHaveBeenCalledWith(expect.any(String), {
      params: {
        lead_stage_id: 7,
        created_after: '2026-07-01',
        stalled: true,
      },
    });
  });

  it('loadFilters lê do localStorage e busca', async () => {
    localStorage.setItem('ramon_lead_filters', JSON.stringify({ q: 'x' }));
    await actions.loadFilters({ commit, dispatch });
    expect(commit).toHaveBeenCalledWith(types.SET_LEAD_FILTERS, { q: 'x' });
    expect(dispatch).toHaveBeenCalledWith('get');
  });
});
