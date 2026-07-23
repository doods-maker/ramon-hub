import axios from 'axios';
import { actions, mutations, state as defaultState } from '../../leads';
import types from '../../../mutation-types';

global.axios = axios;
vi.mock('axios');

describe('leads selection (lote)', () => {
  it('estado inicial tem selectedIds vazio', () => {
    expect(defaultState.selectedIds).toEqual([]);
  });

  it('toggleSelection adiciona um id ainda não selecionado', () => {
    const commit = vi.fn();
    actions.toggleSelection({ commit, state: { selectedIds: [1] } }, 2);
    expect(commit).toHaveBeenCalledWith(types.SET_LEAD_SELECTION, [1, 2]);
  });

  it('toggleSelection remove um id já selecionado', () => {
    const commit = vi.fn();
    actions.toggleSelection({ commit, state: { selectedIds: [1, 2] } }, 1);
    expect(commit).toHaveBeenCalledWith(types.SET_LEAD_SELECTION, [2]);
  });

  it('selectMany une sem duplicar', () => {
    const commit = vi.fn();
    actions.selectMany({ commit, state: { selectedIds: [1, 2] } }, [2, 3]);
    expect(commit).toHaveBeenCalledWith(types.SET_LEAD_SELECTION, [1, 2, 3]);
  });

  it('clearSelection zera a seleção', () => {
    const commit = vi.fn();
    actions.clearSelection({ commit });
    expect(commit).toHaveBeenCalledWith(types.SET_LEAD_SELECTION, []);
  });

  it('bulkAction envia POST bulk_actions com type Lead e limpa a seleção', async () => {
    axios.post.mockResolvedValue({ data: {} });
    const commit = vi.fn();
    await actions.bulkAction(
      { commit, state: { selectedIds: [4, 5] } },
      { fields: { lead_stage_id: 9 }, triage: true }
    );
    expect(axios.post).toHaveBeenCalledWith(
      expect.stringContaining('bulk_actions'),
      { type: 'Lead', ids: [4, 5], fields: { lead_stage_id: 9 }, triage: true }
    );
    expect(commit).toHaveBeenCalledWith(types.SET_LEAD_SELECTION, []);
  });

  it('bulkAction NÃO limpa a seleção quando o POST falha', async () => {
    axios.post.mockRejectedValue(new Error('500'));
    const commit = vi.fn();
    await expect(
      actions.bulkAction(
        { commit, state: { selectedIds: [4] } },
        { fields: { sdr_id: 1 } }
      )
    ).rejects.toThrow();
    expect(commit).not.toHaveBeenCalled();
  });

  it('mutation SET_LEAD_SELECTION substitui a lista', () => {
    const moduleState = { selectedIds: [1] };
    mutations[types.SET_LEAD_SELECTION](moduleState, [7, 8]);
    expect(moduleState.selectedIds).toEqual([7, 8]);
  });

  it('setFilters limpa a seleção em lote (outro universo de cards)', async () => {
    const commit = vi.fn();
    const dispatch = vi.fn();
    await actions.setFilters({ commit, dispatch }, { q: 'ana' });
    expect(commit).toHaveBeenCalledWith(types.SET_LEAD_SELECTION, []);
  });

  it('mutation DELETE_LEAD expurga o id da seleção', () => {
    const moduleState = {
      records: [{ id: 1 }, { id: 2 }],
      selectedIds: [1, 2],
    };
    mutations[types.DELETE_LEAD](moduleState, 1);
    expect(moduleState.records.map(r => r.id)).toEqual([2]);
    expect(moduleState.selectedIds).toEqual([2]);
  });
});
