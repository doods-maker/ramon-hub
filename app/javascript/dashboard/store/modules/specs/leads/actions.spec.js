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

  it('upsert ignora caso de cálculo (broadcast não injeta o card no board)', () => {
    const commit = vi.fn();
    actions.upsert({ commit }, { id: 8, source: 'calculo-advbox' });
    expect(commit).not.toHaveBeenCalled();
  });

  it('select faz commit de SET_SELECTED_LEAD', () => {
    const commit = vi.fn();
    actions.select({ commit }, 42);
    expect(commit).toHaveBeenCalledWith(types.SET_SELECTED_LEAD, 42);
  });

  it('ensureForConversation posts to for_conversation, merges and does NOT select the lead', async () => {
    const lead = { id: 7, conversation_id: 99 };
    axios.post.mockResolvedValue({ data: lead });
    const commit = vi.fn();
    const result = await actions.ensureForConversation(
      { commit },
      { conversationId: 99 }
    );
    expect(result).toEqual(lead);
    expect(commit).toHaveBeenCalledWith(types.MERGE_LEAD, lead);
    expect(commit).not.toHaveBeenCalledWith(types.SET_SELECTED_LEAD, 7);
  });

  it('ensureForConversation devolve null e não mescla nada no 204 (caixa com Portaria)', async () => {
    axios.post.mockResolvedValue({ status: 204, data: '' });
    const commit = vi.fn();
    const result = await actions.ensureForConversation(
      { commit },
      { conversationId: 99 }
    );
    expect(result).toBeNull();
    expect(commit).not.toHaveBeenCalled();
  });

  it('encaminharComercial posta e mescla o lead devolvido', async () => {
    const lead = { id: 9, conversation_id: 99, channel: 'indicacao' };
    axios.post.mockResolvedValue({ data: lead });
    const commit = vi.fn();
    const result = await actions.encaminharComercial(
      { commit },
      { conversationId: 99 }
    );
    expect(axios.post).toHaveBeenCalledWith(
      expect.stringContaining('/leads/encaminhar_comercial'),
      { conversation_id: 99 }
    );
    expect(result).toEqual(lead);
    expect(commit).toHaveBeenCalledWith(types.MERGE_LEAD, lead);
  });

  it('peekForConversation merges the lead without selecting it', async () => {
    const lead = { id: 7, conversation_id: 99 };
    axios.post.mockResolvedValue({ status: 200, data: lead });
    const commit = vi.fn();
    const result = await actions.peekForConversation(
      { commit },
      { conversationId: 99 }
    );
    expect(result).toEqual(lead);
    expect(commit).toHaveBeenCalledWith(types.MERGE_LEAD, lead);
    expect(commit).not.toHaveBeenCalledWith(types.SET_SELECTED_LEAD, 7);
  });

  it('peekForConversation returns null on 204 without committing', async () => {
    axios.post.mockResolvedValue({ status: 204, data: '' });
    const commit = vi.fn();
    const result = await actions.peekForConversation(
      { commit },
      { conversationId: 99 }
    );
    expect(result).toBeNull();
    expect(commit).not.toHaveBeenCalled();
  });

  it('fetchActivities gets activities for a lead and returns the payload array', async () => {
    const activities = [{ id: 1, kind: 'created' }];
    axios.get.mockResolvedValue({ data: { payload: activities } });
    const result = await actions.fetchActivities({}, 7);
    expect(result).toEqual(activities);
  });

  it('fetchNotes gets notes and returns the payload array', async () => {
    const notes = [{ id: 1, body: 'a' }];
    axios.get.mockResolvedValue({ data: { payload: notes } });
    const result = await actions.fetchNotes({}, 5);
    expect(result).toEqual(notes);
  });

  it('createNote posts a note and returns it', async () => {
    const note = { id: 9, body: 'nova' };
    axios.post.mockResolvedValue({ data: note });
    const result = await actions.createNote({}, { leadId: 5, body: 'nova' });
    expect(result).toEqual(note);
    expect(axios.post).toHaveBeenCalledWith(
      expect.stringContaining('/5/notes'),
      { body: 'nova' }
    );
  });
});

describe('leads/openDock & closeDock', () => {
  it('openDock commits SET_DOCK_CONVERSATION with the id', () => {
    const commit = vi.fn();
    actions.openDock({ commit }, 42);
    expect(commit).toHaveBeenCalledWith(types.SET_DOCK_CONVERSATION, 42);
  });

  it('closeDock commits SET_DOCK_CONVERSATION with null', () => {
    const commit = vi.fn();
    actions.closeDock({ commit });
    expect(commit).toHaveBeenCalledWith(types.SET_DOCK_CONVERSATION, null);
  });

  it('toggleDock opens when a different conversation is shown', () => {
    const commit = vi.fn();
    actions.toggleDock({ commit, state: { dockConversationId: null } }, 42);
    expect(commit).toHaveBeenCalledWith(types.SET_DOCK_CONVERSATION, 42);
  });

  it('toggleDock closes when the same conversation is already shown', () => {
    const commit = vi.fn();
    actions.toggleDock({ commit, state: { dockConversationId: 42 } }, 42);
    expect(commit).toHaveBeenCalledWith(types.SET_DOCK_CONVERSATION, null);
  });
});
