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

  it('ensureForConversation posts to for_conversation, merges and selects the lead', async () => {
    const lead = { id: 7, conversation_id: 99 };
    axios.post.mockResolvedValue({ data: lead });
    const commit = vi.fn();
    const result = await actions.ensureForConversation(
      { commit },
      { conversationId: 99 }
    );
    expect(result).toEqual(lead);
    expect(commit).toHaveBeenCalledWith(types.MERGE_LEAD, lead);
    expect(commit).toHaveBeenCalledWith(types.SET_SELECTED_LEAD, 7);
  });

  it('fetchActivities gets activities for a lead and returns the payload array', async () => {
    const activities = [{ id: 1, kind: 'created' }];
    axios.get.mockResolvedValue({ data: { payload: activities } });
    const result = await actions.fetchActivities({}, 7);
    expect(result).toEqual(activities);
  });
});
