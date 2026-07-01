import axios from 'axios';
import { actions } from '../../leadConfig';
import types from '../../../mutation-types';

global.axios = axios;
vi.mock('axios');

describe('leadConfig actions', () => {
  const commit = vi.fn();
  beforeEach(() => vi.clearAllMocks());

  it('createStage commita ADD_LEAD_STAGE', async () => {
    axios.post.mockResolvedValue({ data: { id: 9, name: 'Nova' } });
    await actions.createStage({ commit }, { name: 'Nova' });
    expect(commit).toHaveBeenCalledWith(types.ADD_LEAD_STAGE, {
      id: 9,
      name: 'Nova',
    });
  });

  it('deleteStage commita DELETE_LEAD_STAGE com o id', async () => {
    axios.delete.mockResolvedValue({});
    await actions.deleteStage({ commit }, { id: 3, moveToStageId: 4 });
    expect(commit).toHaveBeenCalledWith(types.DELETE_LEAD_STAGE, 3);
    expect(axios.delete).toHaveBeenCalledWith(
      expect.stringContaining('/lead_stages/3'),
      { params: { move_to_stage_id: 4 } }
    );
  });

  it('reorderStages commita SET_LEAD_STAGES com a coleção', async () => {
    axios.post.mockResolvedValue({ data: [{ id: 2 }, { id: 1 }] });
    await actions.reorderStages({ commit }, [2, 1]);
    expect(commit).toHaveBeenCalledWith(types.SET_LEAD_STAGES, [
      { id: 2 },
      { id: 1 },
    ]);
  });
});
