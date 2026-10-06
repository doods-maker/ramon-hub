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
  remarcarReuniao = vi.fn(),
  cancelarReuniao = vi.fn(),
  registrarReuniao = vi.fn(),
  role = 'agent',
  userId = 1,
} = {}) =>
  createStore({
    getters: {
      getCurrentRole: () => role,
      getCurrentUserID: () => userId,
    },
    modules: {
      leads: { namespaced: true, actions: { registrarReuniao } },
      leadTasks: {
        namespaced: true,
        getters: { getByLead: () => () => tasks },
        actions: {
          fetchForLead,
          complete,
          update,
          remarcarReuniao,
          cancelarReuniao,
        },
      },
    },
  });

const mountCard = (storeOpts = {}) =>
  mount(LeadNextAction, {
    props: { leadId: 7 },
    global: {
      plugins: [build(storeOpts)],
      mocks: { $t: k => k },
      stubs: {
        TaskBellMenu: true,
        teleport: true,
        // router-link custom: o stub precisa entregar o slot com navigate
        RouterLink: { template: '<slot :navigate="() => {}" />' },
      },
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

  describe('reunião', () => {
    const futuro = new Date(Date.now() + 3 * 86400000);
    futuro.setHours(14, 0, 0, 0);
    const reuniao = { ...task, kind: 'meeting', due_at: futuro.toISOString() };

    it('Feito pergunta como foi; Qualificada registra o resultado com a tarefa', async () => {
      const registrarReuniao = vi.fn().mockResolvedValue({});
      const complete = vi.fn();
      const wrapper = mountCard({
        tasks: [reuniao],
        registrarReuniao,
        complete,
      });
      await wrapper.find('[data-testid="next-action-done"]').trigger('click');
      expect(complete).not.toHaveBeenCalled();
      await wrapper
        .find('[data-testid="resultado-qualificada"]')
        .trigger('click');
      await flushPromises();
      expect(registrarReuniao).toHaveBeenCalledWith(expect.anything(), {
        id: 7,
        resultado: 'qualificada',
        taskId: 3,
      });
    });

    it('Não compareceu conclui a tarefa com no-show', async () => {
      const complete = vi.fn().mockResolvedValue({});
      const wrapper = mountCard({ tasks: [reuniao], complete });
      await wrapper.find('[data-testid="next-action-done"]').trigger('click');
      await wrapper
        .find('[data-testid="resultado-nao-compareceu"]')
        .trigger('click');
      await flushPromises();
      expect(complete).toHaveBeenCalledWith(expect.anything(), {
        leadId: 7,
        taskId: 3,
        resultado: 'nao_compareceu',
      });
    });

    it('quem não é o Closer do lead só marca Não compareceu', async () => {
      const wrapper = mountCard({
        tasks: [{ ...reuniao, closer_id: 99 }],
        userId: 1,
      });
      await wrapper.find('[data-testid="next-action-done"]').trigger('click');
      expect(
        wrapper
          .find('[data-testid="resultado-qualificada"]')
          .attributes('disabled')
      ).toBeDefined();
      expect(
        wrapper
          .find('[data-testid="resultado-nao-compareceu"]')
          .attributes('disabled')
      ).toBeUndefined();
      expect(wrapper.find('[data-testid="resultado-so-closer"]').exists()).toBe(
        true
      );
    });

    it('troca Adiar/Reagendar por Remarcar', () => {
      const wrapper = mountCard({ tasks: [reuniao] });
      expect(wrapper.find('[data-testid="next-action-snooze"]').exists()).toBe(
        false
      );
      expect(
        wrapper.find('[data-testid="next-action-reschedule"]').exists()
      ).toBe(false);
      expect(
        wrapper.find('[data-testid="next-action-remarcar"]').exists()
      ).toBe(true);
    });

    it('Remarcar manda o horário novo pela store e avisa o painel', async () => {
      const remarcarReuniao = vi.fn().mockResolvedValue({});
      const wrapper = mountCard({ tasks: [reuniao], remarcarReuniao });
      await wrapper
        .find('[data-testid="next-action-remarcar"]')
        .trigger('click');
      expect(wrapper.find('[data-testid="remarcar-calcom"]').exists()).toBe(
        false
      );
      await wrapper
        .find('[data-testid="remarcar-data"]')
        .setValue('2026-12-10T15:30');
      await wrapper.find('[data-testid="remarcar-confirmar"]').trigger('click');
      await flushPromises();
      expect(remarcarReuniao).toHaveBeenCalledWith(expect.anything(), {
        leadId: 7,
        taskId: 3,
        startsAt: new Date('2026-12-10T15:30').toISOString(),
      });
      expect(wrapper.emitted('notesChanged')).toHaveLength(1);
      expect(wrapper.find('[data-testid="remarcar-janela"]').exists()).toBe(
        false
      );
    });

    it('Cancelar reunião pede confirmação e cancela pela store', async () => {
      const cancelarReuniao = vi.fn().mockResolvedValue({});
      const wrapper = mountCard({
        tasks: [{ ...reuniao, title: 'Reunião Cal.com: Consulta' }],
        cancelarReuniao,
      });
      await wrapper
        .find('[data-testid="next-action-cancelar"]')
        .trigger('click');
      expect(cancelarReuniao).not.toHaveBeenCalled();
      // mensagem leva o aviso do Cal.com
      expect(wrapper.text()).toContain(
        'RAMON.LEAD_PANEL.NEXT_ACTION.CALCOM_CANCELAR'
      );
      await wrapper
        .find('[data-testid="confirm-modal-confirm"]')
        .trigger('click');
      await flushPromises();
      expect(cancelarReuniao).toHaveBeenCalledWith(expect.anything(), {
        leadId: 7,
        taskId: 3,
      });
    });

    it('reunião do Cal.com avisa pra remarcar lá também', async () => {
      const wrapper = mountCard({
        tasks: [{ ...reuniao, title: 'Reunião Cal.com: Consulta' }],
      });
      await wrapper
        .find('[data-testid="next-action-remarcar"]')
        .trigger('click');
      expect(wrapper.find('[data-testid="remarcar-calcom"]').exists()).toBe(
        true
      );
    });
  });
});
