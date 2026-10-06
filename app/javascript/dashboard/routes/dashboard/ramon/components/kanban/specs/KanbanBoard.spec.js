import { mount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import KanbanBoard from '../KanbanBoard.vue';
import KanbanColumn from '../KanbanColumn.vue';
import RemoveStageModal from '../RemoveStageModal.vue';
import WonValueModal from '../WonValueModal.vue';
import ConfirmModal from '../../ConfirmModal.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

import { useAlert } from 'dashboard/composables';

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
}));

const dispatch = vi.fn();
const buildStore = ({ role = 'administrator', wonRequest = null } = {}) =>
  createStore({
    getters: { getCurrentRole: () => role },
    modules: {
      leads: {
        namespaced: true,
        getters: {
          getLeadsByStage: () => () => [],
          getLeads: () => [{ id: 10, lead_stage_id: 1, position: 0 }],
          getSelectedIds: () => [],
          getDockConversationId: () => null,
          getWonRequest: () => wonRequest,
          getUIFlags: () => ({ isFetching: false }),
          getFilters: () => ({
            q: '',
            benefitTypeId: null,
            leadPriorityId: null,
            agentId: null,
            source: '',
          }),
        },
      },
      leadConfig: {
        namespaced: true,
        getters: {
          getStages: () => [
            { id: 1, name: 'Novo', color: '#000' },
            { id: 2, name: 'Qualificado', color: '#111' },
            { id: 9, name: 'Perdido', color: '#222', is_lost: true },
          ],
          getLostReasons: () => [],
          getBenefitTypes: () => [],
          getPriorities: () => [],
          getSources: () => [],
          getChannels: () => [],
        },
      },
      agents: {
        namespaced: true,
        getters: { getAgents: () => [] },
      },
    },
  });

const mountBoard = options => {
  const store = buildStore(options);
  store.dispatch = dispatch;
  return mount(KanbanBoard, {
    global: {
      plugins: [store],
      mocks: { $t: k => k },
      stubs: {
        LeadDrawer: true,
        ConversationDock: true,
        SavedViews: true,
        // sem stub, o leave dos modais em <Transition> atrasa o unmount
        transition: true,
        // LostReasonModal linka pra Config do Funil; sem router no teste
        RouterLink: true,
      },
    },
  });
};

describe('KanbanBoard.vue', () => {
  beforeEach(() => dispatch.mockClear());

  it('toggles the dock (dispatch leads/toggleDock) when a column emits open-conversation', async () => {
    const wrapper = mountBoard();
    wrapper.findComponent(KanbanColumn).vm.$emit('openConversation', 55);
    await wrapper.vm.$nextTick();
    expect(dispatch).toHaveBeenCalledWith('leads/toggleDock', 55);
  });

  it('mounts the ConversationDock', () => {
    const wrapper = mountBoard();
    expect(wrapper.findComponent({ name: 'ConversationDock' }).exists()).toBe(
      true
    );
  });

  it('busca leadConfig, filtros de leads e agents no mount', () => {
    mountBoard();
    expect(dispatch).toHaveBeenCalledWith('leadConfig/get');
    expect(dispatch).toHaveBeenCalledWith('leads/loadFilters');
    expect(dispatch).toHaveBeenCalledWith('agents/get');
  });

  it('seleciona o lead ao receber open-lead de uma coluna', () => {
    const wrapper = mountBoard();
    wrapper.findComponent(KanbanColumn).vm.$emit('openLead', { id: 33 });
    expect(dispatch).toHaveBeenCalledWith('leads/select', 33);
  });

  it('renameStage dispara updateStage', () => {
    const wrapper = mountBoard();
    wrapper
      .findComponent(KanbanColumn)
      .vm.$emit('renameStage', { id: 1, name: 'X' });
    expect(dispatch).toHaveBeenCalledWith('leadConfig/updateStage', {
      id: 1,
      name: 'X',
    });
  });

  it('recolorStage dispara updateStage', () => {
    const wrapper = mountBoard();
    wrapper
      .findComponent(KanbanColumn)
      .vm.$emit('recolorStage', { id: 1, color: '#fff' });
    expect(dispatch).toHaveBeenCalledWith('leadConfig/updateStage', {
      id: 1,
      color: '#fff',
    });
  });

  it('setStageClientName salva o nome para o cliente', () => {
    const wrapper = mountBoard();
    wrapper
      .findComponent(KanbanColumn)
      .vm.$emit('setStageClientName', { id: 1, nomeCliente: 'Em análise' });
    expect(dispatch).toHaveBeenCalledWith('leadConfig/updateStage', {
      id: 1,
      nome_cliente: 'Em análise',
    });
  });

  it('setStageType ganho pede confirmação antes de salvar e recarrega as etapas', async () => {
    dispatch.mockResolvedValue({});
    const wrapper = mountBoard();
    wrapper
      .findComponent(KanbanColumn)
      .vm.$emit('setStageType', { id: 1, type: 'won' });
    await wrapper.vm.$nextTick();
    expect(dispatch).not.toHaveBeenCalledWith(
      'leadConfig/updateStage',
      expect.anything()
    );
    const modal = wrapper.findComponent(ConfirmModal);
    expect(modal.props('message')).toContain(
      'RAMON.FUNIL.STAGE.CONFIRM_WON_EFFECT'
    );
    dispatch.mockClear();
    modal.vm.$emit('confirm');
    await flushPromises();
    expect(dispatch).toHaveBeenCalledWith('leadConfig/updateStage', {
      id: 1,
      is_won: true,
      is_lost: false,
    });
    expect(dispatch).toHaveBeenCalledWith('leadConfig/get');
  });

  it('setStageType perda avisa que a etapa de perda atual deixa de ser', async () => {
    const wrapper = mountBoard();
    wrapper
      .findComponent(KanbanColumn)
      .vm.$emit('setStageType', { id: 2, type: 'lost' });
    await wrapper.vm.$nextTick();
    expect(wrapper.findComponent(ConfirmModal).props('message')).toContain(
      'RAMON.FUNIL.STAGE.CONFIRM_LOST_PREVIOUS'
    );
  });

  it('setStageType normal salva direto', () => {
    const wrapper = mountBoard();
    wrapper
      .findComponent(KanbanColumn)
      .vm.$emit('setStageType', { id: 9, type: 'normal' });
    expect(dispatch).toHaveBeenCalledWith('leadConfig/updateStage', {
      id: 9,
      is_won: false,
      is_lost: false,
    });
  });

  it('mostra a mensagem do servidor quando renomear falha', async () => {
    const wrapper = mountBoard();
    dispatch.mockRejectedValueOnce({
      response: { data: { message: 'Nome já está em uso' } },
    });
    wrapper
      .findComponent(KanbanColumn)
      .vm.$emit('renameStage', { id: 1, name: 'Qualificado' });
    await flushPromises();
    expect(useAlert).toHaveBeenCalledWith('Nome já está em uso');
  });

  it('removeStage abre o RemoveStageModal e confirm dispara deleteStage', async () => {
    const wrapper = mountBoard();
    expect(wrapper.findComponent(RemoveStageModal).exists()).toBe(false);

    wrapper
      .findComponent(KanbanColumn)
      .vm.$emit('removeStage', { id: 1, name: 'Novo' });
    await wrapper.vm.$nextTick();

    const modal = wrapper.findComponent(RemoveStageModal);
    expect(modal.exists()).toBe(true);
    modal.vm.$emit('confirm', { id: 1, moveToStageId: 2 });
    await wrapper.vm.$nextTick();

    expect(dispatch).toHaveBeenCalledWith('leadConfig/deleteStage', {
      id: 1,
      moveToStageId: 2,
    });
  });

  it('removeStage cancel fecha o modal sem dispatch de deleteStage', async () => {
    const wrapper = mountBoard();
    wrapper
      .findComponent(KanbanColumn)
      .vm.$emit('removeStage', { id: 1, name: 'Novo' });
    await wrapper.vm.$nextTick();

    wrapper.findComponent(RemoveStageModal).vm.$emit('cancel');
    await wrapper.vm.$nextTick();

    expect(wrapper.findComponent(RemoveStageModal).exists()).toBe(false);
    expect(dispatch).not.toHaveBeenCalledWith(
      'leadConfig/deleteStage',
      expect.anything()
    );
  });

  it('addStage abre o modal de nome e confirma criando a etapa', async () => {
    const wrapper = mountBoard();

    await wrapper.find('[data-testid="add-stage"]').trigger('click');

    const modal = wrapper.findComponent({ name: 'NamePromptModal' });
    expect(modal.exists()).toBe(true);
    await modal
      .find('[data-testid="name-prompt-input"]')
      .setValue('Nova etapa');
    await modal.find('[data-testid="name-prompt-confirm"]').trigger('click');

    expect(dispatch).toHaveBeenCalledWith('leadConfig/createStage', {
      name: 'Nova etapa',
    });
  });

  it('addStage cancelado fecha o modal sem criar etapa', async () => {
    const wrapper = mountBoard();

    await wrapper.find('[data-testid="add-stage"]').trigger('click');
    const modal = wrapper.findComponent({ name: 'NamePromptModal' });
    await modal.find('[data-testid="name-prompt-cancel"]').trigger('click');
    await wrapper.vm.$nextTick();

    expect(wrapper.findComponent({ name: 'NamePromptModal' }).exists()).toBe(
      false
    );
    expect(dispatch).not.toHaveBeenCalledWith(
      'leadConfig/createStage',
      expect.anything()
    );
  });

  it('carrega filtros no mount e reage ao update dos filtros', () => {
    const wrapper = mountBoard();
    expect(dispatch).toHaveBeenCalledWith('leads/loadFilters');
    wrapper.findComponent({ name: 'KanbanFilters' }).vm.$emit('update', {
      q: 'ana',
    });
    expect(dispatch).toHaveBeenCalledWith('leads/setFilters', { q: 'ana' });
  });

  it('reordenar colunas dispara reorderStages com a nova ordem de ids', async () => {
    const wrapper = mountBoard();
    const draggable = wrapper.findComponent({ name: 'draggable' });

    await draggable.vm.$emit('update:modelValue', [
      { id: 2, name: 'Qualificado', color: '#111' },
      { id: 1, name: 'Novo', color: '#000' },
    ]);
    await draggable.vm.$emit('change');

    expect(dispatch).toHaveBeenCalledWith('leadConfig/reorderStages', [2, 1]);
  });

  it('pedido de ganho do Ctrl K abre o modal de valor e grava no confirmar', async () => {
    const wrapper = mountBoard({ wonRequest: { id: 10, leadStageId: 5 } });
    await wrapper.vm.$nextTick();
    // consome o pedido para não reabrir
    expect(dispatch).toHaveBeenCalledWith('leads/requestWon', null);
    const modal = wrapper.findComponent(WonValueModal);
    expect(modal.exists()).toBe(true);

    modal.vm.$emit('confirmValue', { value: 1500 });
    await wrapper.vm.$nextTick();
    expect(dispatch).toHaveBeenCalledWith(
      'leads/update',
      expect.objectContaining({ id: 10, lead_stage_id: 5, value: 1500 })
    );
  });

  it('agente não vê + Etapa nem o menu da etapa e não reordena colunas', () => {
    const wrapper = mountBoard({ role: 'agent' });
    expect(wrapper.find('[data-testid="add-stage"]').exists()).toBe(false);
    expect(wrapper.findComponent(KanbanColumn).props('editable')).toBe(false);
    expect(wrapper.find('[data-testid="stage-menu-toggle"]').exists()).toBe(
      false
    );
  });

  it('admin edita etapas', () => {
    const wrapper = mountBoard();
    expect(wrapper.find('[data-testid="add-stage"]').exists()).toBe(true);
    expect(wrapper.findComponent(KanbanColumn).props('editable')).toBe(true);
  });

  it('busca do header atualiza o filtro q com debounce', async () => {
    vi.useFakeTimers();
    const wrapper = mountBoard();
    await wrapper.find('[data-testid="funil-search"]').setValue('99812-3456');
    expect(dispatch).not.toHaveBeenCalledWith(
      'leads/setFilters',
      expect.anything()
    );
    vi.advanceTimersByTime(300);
    expect(dispatch).toHaveBeenCalledWith('leads/setFilters', {
      q: '99812-3456',
    });
    vi.useRealTimers();
  });

  describe('undo do drag & drop', () => {
    beforeEach(() => useAlert.mockClear());

    it('dispara toast com Desfazer após mover para etapa comum', async () => {
      const wrapper = mountBoard();
      wrapper
        .findComponent(KanbanColumn)
        .vm.$emit('move', { id: 10, leadStageId: 2, newIndex: 3 });
      await wrapper.vm.$nextTick();
      await wrapper.vm.$nextTick();

      expect(dispatch).toHaveBeenCalledWith('leads/move', {
        id: 10,
        leadStageId: 2,
        position: 3,
      });
      expect(useAlert).toHaveBeenCalled();
      const [, action] = useAlert.mock.calls.at(-1);
      expect(action.type).toBe('button');
    });

    it('o onClick do toast reverte para a etapa e posição originais', async () => {
      const wrapper = mountBoard();
      wrapper
        .findComponent(KanbanColumn)
        .vm.$emit('move', { id: 10, leadStageId: 2, newIndex: 3 });
      await wrapper.vm.$nextTick();
      await wrapper.vm.$nextTick();

      const [, action] = useAlert.mock.calls.at(-1);
      dispatch.mockClear();
      action.onClick();

      expect(dispatch).toHaveBeenCalledWith('leads/move', {
        id: 10,
        leadStageId: 1,
        position: 0,
      });
    });

    it('NÃO mostra toast quando o movimento cai no modal de perda', async () => {
      const wrapper = mountBoard();
      wrapper
        .findComponent(KanbanColumn)
        .vm.$emit('move', { id: 10, leadStageId: 9, newIndex: 0 });
      await wrapper.vm.$nextTick();
      await wrapper.vm.$nextTick();

      expect(useAlert).not.toHaveBeenCalled();
    });
  });
});
