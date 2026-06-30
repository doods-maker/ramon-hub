import { shallowMount } from '@vue/test-utils';
import { createStore } from 'vuex';
import KanbanBoard from '../KanbanBoard.vue';
import KanbanColumn from '../KanbanColumn.vue';

const dispatch = vi.fn();
const buildStore = () =>
  createStore({
    modules: {
      leads: {
        namespaced: true,
        getters: { getLeadsByStage: () => () => [] },
      },
      leadConfig: {
        namespaced: true,
        getters: { getStages: () => [{ id: 1, name: 'Novo', color: '#000' }] },
      },
    },
  });

const mountBoard = () => {
  const store = buildStore();
  store.dispatch = dispatch;
  return shallowMount(KanbanBoard, {
    global: { plugins: [store], mocks: { $t: k => k } },
  });
};

describe('KanbanBoard.vue', () => {
  beforeEach(() => dispatch.mockClear());

  it('busca leadConfig, leads e agents no mount', () => {
    mountBoard();
    expect(dispatch).toHaveBeenCalledWith('leadConfig/get');
    expect(dispatch).toHaveBeenCalledWith('leads/get');
    expect(dispatch).toHaveBeenCalledWith('agents/get');
  });

  it('seleciona o lead ao receber open-lead de uma coluna', () => {
    const wrapper = mountBoard();
    wrapper.findComponent(KanbanColumn).vm.$emit('open-lead', { id: 33 });
    expect(dispatch).toHaveBeenCalledWith('leads/select', 33);
  });
});
