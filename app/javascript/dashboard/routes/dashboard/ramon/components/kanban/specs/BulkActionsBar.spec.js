import { mount } from '@vue/test-utils';
import BulkActionsBar from '../BulkActionsBar.vue';
import LostReasonModal from '../LostReasonModal.vue';
import ConfirmModal from '../../ConfirmModal.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
}));

const dispatch = vi.fn().mockResolvedValue();

const stubStore = {
  getters: {
    'leads/getSelectedIds': [10, 11],
    'leads/getDockConversationId': null,
    'leadConfig/getStages': [
      { id: 1, name: 'Novo', color: '#000' },
      { id: 9, name: 'Perdido', color: '#111', is_lost: true },
      { id: 8, name: 'Ganho', color: '#222', is_won: true },
    ],
    'leadConfig/getLostReasons': [{ id: 5, name: 'Preço' }],
    'agents/getAgents': [{ id: 3, name: 'Eduardo' }],
    getCurrentRole: 'administrator',
  },
  dispatch,
};

const mountBar = () =>
  mount(BulkActionsBar, {
    global: {
      mocks: { $t: k => k },
      stubs: { transition: true, RouterLink: true },
      plugins: [
        {
          install: app => {
            app.config.globalProperties.$store = stubStore;
          },
        },
      ],
    },
  });

describe('BulkActionsBar', () => {
  beforeEach(() => dispatch.mockClear());

  it('mostra a contagem de selecionados', () => {
    const wrapper = mountBar();
    expect(wrapper.find('[data-testid="bulk-count"]').text()).toContain(
      'RAMON.KANBAN.BULK.SELECTED'
    );
  });

  it('mover para etapa comum dispara bulkAction com lead_stage_id', async () => {
    const wrapper = mountBar();
    await wrapper.find('[data-testid="bulk-move-stage"]').trigger('click');
    await wrapper.find('[data-testid="bulk-stage-option"]').trigger('click');
    expect(dispatch).toHaveBeenCalledWith('leads/bulkAction', {
      fields: { lead_stage_id: 1 },
    });
  });

  it('mover para etapa de perda exige o motivo UMA vez e aplica a todos', async () => {
    const wrapper = mountBar();
    await wrapper.find('[data-testid="bulk-move-stage"]').trigger('click');
    const options = wrapper.findAll('[data-testid="bulk-stage-option"]');
    await options[1].trigger('click');

    // nada disparado ainda — o modal de motivo segura o lote
    expect(dispatch).not.toHaveBeenCalled();
    const modal = wrapper.findComponent(LostReasonModal);
    expect(modal.exists()).toBe(true);

    modal.vm.$emit('confirmMove', { lostReason: 'Preço' });
    await wrapper.vm.$nextTick();
    expect(dispatch).toHaveBeenCalledWith('leads/bulkAction', {
      fields: { lead_stage_id: 9, lost_reason: 'Preço' },
    });
  });

  it('mover para etapa de ganho pede confirmação antes do lote', async () => {
    const wrapper = mountBar();
    await wrapper.find('[data-testid="bulk-move-stage"]').trigger('click');
    const options = wrapper.findAll('[data-testid="bulk-stage-option"]');
    await options[2].trigger('click');

    // ganho dispara automações: nada sai sem o confirmar
    expect(dispatch).not.toHaveBeenCalled();
    const modal = wrapper.findComponent(ConfirmModal);
    expect(modal.exists()).toBe(true);
    expect(modal.props('title')).toBe('RAMON.KANBAN.BULK.WON_TITLE');

    modal.vm.$emit('confirm');
    await wrapper.vm.$nextTick();
    expect(dispatch).toHaveBeenCalledWith('leads/bulkAction', {
      fields: { lead_stage_id: 8 },
    });
  });

  it('cancelar a confirmação de ganho não dispara o lote', async () => {
    const wrapper = mountBar();
    await wrapper.find('[data-testid="bulk-move-stage"]').trigger('click');
    await wrapper
      .findAll('[data-testid="bulk-stage-option"]')[2]
      .trigger('click');
    wrapper.findComponent(ConfirmModal).vm.$emit('cancel');
    await wrapper.vm.$nextTick();
    expect(wrapper.findComponent(ConfirmModal).exists()).toBe(false);
    expect(dispatch).not.toHaveBeenCalled();
  });

  it('atribuir SDR dispara bulkAction com sdr_id', async () => {
    const wrapper = mountBar();
    await wrapper.find('[data-testid="bulk-assign-sdr"]').trigger('click');
    await wrapper.find('[data-testid="bulk-sdr-option"]').trigger('click');
    expect(dispatch).toHaveBeenCalledWith('leads/bulkAction', {
      fields: { sdr_id: 3 },
    });
  });

  it('agendar follow-up dispara bulkAction com task.due_at', async () => {
    const wrapper = mountBar();
    await wrapper.find('[data-testid="bulk-follow-up"]').trigger('click');
    await wrapper
      .find('[data-testid="bulk-task-date"]')
      .setValue('2026-08-01T09:00');
    await wrapper.find('[data-testid="bulk-task-confirm"]').trigger('click');
    const [, payload] = dispatch.mock.calls.find(
      ([action]) => action === 'leads/bulkAction'
    );
    expect(payload.task.due_at).toBe(
      new Date('2026-08-01T09:00').toISOString()
    );
  });

  it('Limpar dispara clearSelection', async () => {
    const wrapper = mountBar();
    await wrapper.find('[data-testid="bulk-clear"]').trigger('click');
    expect(dispatch).toHaveBeenCalledWith('leads/clearSelection');
  });

  it('Esc limpa a seleção quando não há menu nem modal aberto', async () => {
    mountBar();
    window.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }));
    expect(dispatch).toHaveBeenCalledWith('leads/clearSelection');
  });
});
