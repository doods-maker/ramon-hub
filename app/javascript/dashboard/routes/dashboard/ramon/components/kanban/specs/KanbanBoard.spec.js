import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import KanbanBoard from '../KanbanBoard.vue';
import KanbanColumn from '../KanbanColumn.vue';
import RemoveStageModal from '../RemoveStageModal.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

const dispatch = vi.fn();
const buildStore = () =>
  createStore({
    modules: {
      leads: {
        namespaced: true,
        getters: {
          getLeadsByStage: () => () => [],
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
          ],
          getBenefitTypes: () => [],
          getPriorities: () => [],
          getSources: () => [],
        },
      },
      agents: {
        namespaced: true,
        getters: { getAgents: () => [] },
      },
    },
  });

const mountBoard = () => {
  const store = buildStore();
  store.dispatch = dispatch;
  return mount(KanbanBoard, {
    global: {
      plugins: [store],
      mocks: { $t: k => k },
      stubs: { LeadDrawer: true, ConversationDock: true, SavedViews: true },
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

  it('setStageType dispara updateStage com is_won/is_lost', () => {
    const wrapper = mountBoard();
    wrapper
      .findComponent(KanbanColumn)
      .vm.$emit('setStageType', { id: 1, type: 'won' });
    expect(dispatch).toHaveBeenCalledWith('leadConfig/updateStage', {
      id: 1,
      is_won: true,
      is_lost: false,
    });
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

  it('addStage pede o nome via prompt e dispara createStage', async () => {
    const promptSpy = vi.spyOn(window, 'prompt').mockReturnValue('Nova etapa');
    const wrapper = mountBoard();

    await wrapper.find('button.border-dashed').trigger('click');

    expect(promptSpy).toHaveBeenCalled();
    expect(dispatch).toHaveBeenCalledWith('leadConfig/createStage', {
      name: 'Nova etapa',
    });
    promptSpy.mockRestore();
  });

  it('addStage não dispara createStage se o prompt for cancelado', async () => {
    const promptSpy = vi.spyOn(window, 'prompt').mockReturnValue(null);
    const wrapper = mountBoard();

    await wrapper.find('button.border-dashed').trigger('click');

    expect(dispatch).not.toHaveBeenCalledWith(
      'leadConfig/createStage',
      expect.anything()
    );
    promptSpy.mockRestore();
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
});
