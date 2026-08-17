import { mount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import LeadNextAction from '../LeadNextAction.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const task = {
  id: 3,
  lead_id: 7,
  title: 'Ligar após perícia',
  due_at: '2026-07-22T09:00:00Z',
  completed_at: null,
};

const build = ({
  tasks = [task],
  complete = vi.fn(),
  update = vi.fn(),
  fetchForLead = vi.fn(),
} = {}) =>
  createStore({
    modules: {
      leadTasks: {
        namespaced: true,
        getters: { getByLead: () => () => tasks },
        actions: { fetchForLead, complete, update },
      },
    },
  });

const mountCard = (storeOpts = {}) =>
  mount(LeadNextAction, {
    props: { leadId: 7 },
    global: {
      plugins: [build(storeOpts)],
      mocks: { $t: k => k },
      stubs: { TaskBellMenu: true, RouterLink: true },
    },
  });

describe('LeadNextAction', () => {
  it('busca as tarefas do lead ao montar', () => {
    const fetchForLead = vi.fn();
    mountCard({ fetchForLead });
    expect(fetchForLead).toHaveBeenCalledWith(expect.anything(), 7);
  });

  it('mostra a 1ª tarefa aberta com o rótulo de vencida', () => {
    const wrapper = mountCard();
    expect(wrapper.find('[data-testid="lead-next-action"]').exists()).toBe(
      true
    );
    expect(wrapper.text()).toContain('Ligar após perícia');
    // due_at no passado (2026-07-22 < hoje 23/07) → vencida
    expect(wrapper.text()).toContain('RAMON.TASKS.OVERDUE');
  });

  it('reunião marcada mostra o cabeçalho de reunião com dia e hora absolutos', () => {
    const futuro = new Date(Date.now() + 3 * 86400000);
    futuro.setHours(14, 0, 0, 0);
    const wrapper = mountCard({
      tasks: [{ ...task, kind: 'meeting', due_at: futuro.toISOString() }],
    });
    expect(wrapper.text()).toContain(
      'RAMON.LEAD_PANEL.NEXT_ACTION.MEETING_TITLE'
    );
    const when = wrapper.find('[data-testid="next-action-meeting-when"]');
    expect(when.exists()).toBe(true);
    expect(when.text()).toContain('14:00');
    expect(
      wrapper.find('[data-testid="next-action-agenda-link"]').exists()
    ).toBe(true);
  });

  it('não renderiza nada sem tarefa aberta', () => {
    const wrapper = mountCard({ tasks: [] });
    expect(wrapper.find('[data-testid="lead-next-action"]').exists()).toBe(
      false
    );
  });

  it('Feito ✓ conclui a tarefa pela store', async () => {
    const complete = vi.fn().mockResolvedValue({});
    const wrapper = mountCard({ complete });
    await wrapper.find('[data-testid="next-action-done"]').trigger('click');
    await flushPromises();
    expect(complete).toHaveBeenCalledWith(expect.anything(), {
      leadId: 7,
      taskId: 3,
    });
  });

  it('Adiar 1d atualiza o due_at somando 24h', async () => {
    const update = vi.fn().mockResolvedValue({});
    const wrapper = mountCard({ update });
    await wrapper.find('[data-testid="next-action-snooze"]').trigger('click');
    await flushPromises();
    expect(update).toHaveBeenCalledWith(expect.anything(), {
      leadId: 7,
      taskId: 3,
      payload: { due_at: '2026-07-23T09:00:00.000Z' },
    });
  });

  it('Reagendar usa a data escolhida no TaskBellMenu', async () => {
    const update = vi.fn().mockResolvedValue({});
    const wrapper = mountCard({ update });
    wrapper
      .findComponent({ name: 'TaskBellMenu' })
      .vm.$emit('schedule', { dueAt: '2026-08-01T12:00:00.000Z', title: 'x' });
    await flushPromises();
    expect(update).toHaveBeenCalledWith(expect.anything(), {
      leadId: 7,
      taskId: 3,
      payload: { due_at: '2026-08-01T12:00:00.000Z' },
    });
  });
});
