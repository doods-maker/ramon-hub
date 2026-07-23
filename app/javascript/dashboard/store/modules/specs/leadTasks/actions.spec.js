import axios from 'axios';
import { actions } from '../../leadTasks';
import types from '../../../mutation-types';

global.axios = axios;
vi.mock('axios');

describe('leadTasks actions', () => {
  const commit = vi.fn();
  beforeEach(() => vi.clearAllMocks());

  it('fetchForLead busca e faz MERGE_LEAD_TASKS com o payload', async () => {
    const payload = [{ id: 1, lead_id: 10 }];
    axios.get.mockResolvedValue({ data: { payload } });
    await actions.fetchForLead({ commit }, 10);
    expect(axios.get).toHaveBeenCalledWith(
      expect.stringContaining('/leads/10/tasks')
    );
    expect(commit).toHaveBeenCalledWith(types.SET_LEAD_TASKS_UI_FLAG, {
      isFetching: true,
    });
    expect(commit).toHaveBeenCalledWith(types.MERGE_LEAD_TASKS, payload);
    expect(commit).toHaveBeenCalledWith(types.SET_LEAD_TASKS_UI_FLAG, {
      isFetching: false,
    });
  });

  it('fetchAccountScope envia o scope e faz MERGE_LEAD_TASKS', async () => {
    const payload = [{ id: 2, lead_id: 20 }];
    axios.get.mockResolvedValue({ data: { payload } });
    await actions.fetchAccountScope({ commit }, 'overdue');
    expect(axios.get).toHaveBeenCalledWith(
      expect.stringContaining('/lead_tasks'),
      { params: { scope: 'overdue' } }
    );
    expect(commit).toHaveBeenCalledWith(types.MERGE_LEAD_TASKS, payload);
  });

  it('fetchAccountScope marca hasError e desliga o isFetching na falha', async () => {
    axios.get.mockRejectedValue(new Error('boom'));
    await actions.fetchAccountScope({ commit });
    expect(commit).toHaveBeenCalledWith(types.SET_LEAD_TASKS_UI_FLAG, {
      hasError: true,
    });
    expect(commit).toHaveBeenLastCalledWith(types.SET_LEAD_TASKS_UI_FLAG, {
      isFetching: false,
    });
  });

  it('create posta com due_at snake_case e faz MERGE_LEAD_TASK', async () => {
    const task = { id: 3, lead_id: 10, title: 'Ligar' };
    axios.post.mockResolvedValue({ data: task });
    const result = await actions.create(
      { commit },
      { leadId: 10, title: 'Ligar', kind: 'follow_up', dueAt: '2026-07-04' }
    );
    expect(axios.post).toHaveBeenCalledWith(
      expect.stringContaining('/leads/10/tasks'),
      { title: 'Ligar', kind: 'follow_up', due_at: '2026-07-04' }
    );
    expect(commit).toHaveBeenCalledWith(types.MERGE_LEAD_TASK, task);
    expect(result).toEqual(task);
  });

  it('update faz PATCH parcial (adiar/reagendar) e MERGE_LEAD_TASK', async () => {
    const task = { id: 3, due_at: '2026-07-24T09:00:00Z' };
    axios.patch.mockResolvedValue({ data: task });
    const result = await actions.update(
      { commit },
      { leadId: 10, taskId: 3, payload: { due_at: '2026-07-24T09:00:00Z' } }
    );
    expect(axios.patch).toHaveBeenCalledWith(
      expect.stringContaining('/leads/10/tasks/3'),
      { due_at: '2026-07-24T09:00:00Z' }
    );
    expect(commit).toHaveBeenCalledWith(types.MERGE_LEAD_TASK, task);
    expect(result).toEqual(task);
  });

  it('complete atualiza o record local e não refaz fetch de leads', async () => {
    const task = { id: 3, completed_at: '2026-07-03T12:00:00Z' };
    axios.post.mockResolvedValue({ data: task });
    await actions.complete({ commit }, { leadId: 10, taskId: 3 });
    expect(axios.post).toHaveBeenCalledWith(
      expect.stringContaining('/leads/10/tasks/3/complete')
    );
    expect(commit).toHaveBeenCalledWith(types.MERGE_LEAD_TASK, task);
  });

  it('destroy apaga e faz DELETE_LEAD_TASK com o id', async () => {
    axios.delete.mockResolvedValue({});
    await actions.destroy({ commit }, { leadId: 10, taskId: 3 });
    expect(axios.delete).toHaveBeenCalledWith(
      expect.stringContaining('/leads/10/tasks/3')
    );
    expect(commit).toHaveBeenCalledWith(types.DELETE_LEAD_TASK, 3);
  });
});
