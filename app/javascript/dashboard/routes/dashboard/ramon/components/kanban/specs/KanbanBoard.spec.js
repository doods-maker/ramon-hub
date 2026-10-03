import { mount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import KanbanBoard from '../KanbanBoard.vue';
import KanbanColumn from '../KanbanColumn.vue';
import RemoveStageModal from '../RemoveStageModal.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

import { useAlert } from 'dashboard/composables';

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
}));

// ?filtro=pos_venda|prescricao (Pós-venda e Radar viraram filtros do funil)
const mockRoute = { query: {} };
const mockReplace = vi.fn();
vi.mock('vue-router', async importOriginal => ({
  ...(await importOriginal()),
  useRoute: () => mockRoute,
  useRouter: () => ({ push: vi.fn(), replace: mockReplace }),
}));

vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ accountScopedRoute: name => ({ name }) }),
}));
vi.mock('dashboard/api/ramonPrescriptionRadar', () => ({
  default: {
    get: vi.fn().mockResolvedValue({ data: { summary: {}, items: [] } }),
  },
}));
vi.mock('dashboard/api/ramonPosVenda', () => ({
  default: {
    get: vi.fn().mockResolvedValue({ data: { pendentes: [], concluidos: [] } }),
  },
}));
const pendentesDoLead = vi.fn();
const marcarSolicitados = vi.fn();
vi.mock('../../../composables/useCobrarDocs', () => ({
  useCobrarDocs: () => ({ pendentesDoLead, marcarSolicitados }),
}));

let mockFilters = {};
const LEADS_STAGE_1 = [
  { id: 10, lead_stage_id: 1, position: 0 },
  {
    id: 11,
    lead_stage_id: 1,
    position: 1,
    won_at: '2026-09-01T10:00:00Z',
    docs_received: 2,
    docs_total: 5,
  },
];

const dispatch = vi.fn();
const buildStore = () =>
  createStore({
    modules: {
      leads: {
        namespaced: true,
        getters: {
          getLeadsByStage: () => stageId =>
            stageId === 1 ? LEADS_STAGE_1 : [],
          getLeads: () => LEADS_STAGE_1,
          getSelectedIds: () => [],
          getDockConversationId: () => null,
          getUIFlags: () => ({ isFetching: false }),
          getFilters: () => ({
            q: '',
            benefitTypeId: null,
            leadPriorityId: null,
            agentId: null,
            source: '',
            ...mockFilters,
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

const mountBoard = () => {
  const store = buildStore();
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
  beforeEach(() => {
    dispatch.mockClear();
    mockReplace.mockClear();
    mockRoute.query = {};
    mockFilters = {};
  });

  describe('filtros de pós-venda e prescrição', () => {
    it('sem ?filtro mostra todos os leads da etapa', () => {
      const wrapper = mountBoard();
      expect(wrapper.findComponent(KanbanColumn).props('leads')).toHaveLength(
        2
      );
    });

    it('?filtro=pos_venda mostra só os ganhos com docs pendentes', () => {
      mockRoute.query = { filtro: 'pos_venda' };
      const wrapper = mountBoard();
      const ids = wrapper
        .findComponent(KanbanColumn)
        .props('leads')
        .map(l => l.id);
      expect(ids).toEqual([11]);
      expect(
        wrapper.find('[data-testid="filtro-pos_venda"]').classes()
      ).toContain('text-n-amber-11');
    });

    it('?filtro=prescricao ordena por sangramento e passa o filtro ao card', () => {
      mockRoute.query = { filtro: 'prescricao' };
      LEADS_STAGE_1.push(
        { id: 20, lead_stage_id: 1, position: 2, dcb_em: '2022-01-10' },
        {
          id: 21,
          lead_stage_id: 1,
          position: 3,
          dcb_em: '2018-01-10',
          benefit_monthly_value: 900,
        }
      );
      const wrapper = mountBoard();
      LEADS_STAGE_1.splice(2);
      const coluna = wrapper.findComponent(KanbanColumn);
      expect(coluna.props('leads').map(l => l.id)).toEqual([21, 20]);
      expect(coluna.props('filtro')).toBe('prescricao');
      expect(wrapper.find('[data-testid="faixa-filtro"]').exists()).toBe(true);
    });

    it('com filtro de servidor ligado a faixa oferece limpar tudo', async () => {
      mockRoute.query = { filtro: 'pos_venda' };
      mockFilters = { agentId: 3, stalled: true };
      const wrapper = mountBoard();
      await wrapper.find('[data-testid="faixa-limpar"]').trigger('click');
      expect(dispatch).toHaveBeenCalledWith(
        'leads/setFilters',
        expect.objectContaining({ agentId: null, stalled: false, q: '' })
      );
    });

    it('"Mais filtros · N" não conta Tese/Responsável/Origem', () => {
      mockFilters = {
        agentId: 3,
        thesisId: 2,
        channel: 'meta_ads',
        stalled: true,
      };
      const wrapper = mountBoard();
      expect(
        wrapper.find('[data-testid="filters-active-count"]').text()
      ).toContain('1');
    });

    it('o chip liga e desliga o filtro na URL', async () => {
      const wrapper = mountBoard();
      await wrapper.find('[data-testid="filtro-pos_venda"]').trigger('click');
      expect(mockReplace).toHaveBeenCalledWith({
        query: { filtro: 'pos_venda' },
      });
    });
  });

  describe('cobrar documentos do card ganho', () => {
    it('com conversa: abre o dock com o rascunho e marca solicitados', async () => {
      pendentesDoLead.mockResolvedValue([
        { id: 1, title: 'Laudo', status: 'pendente' },
      ]);
      const wrapper = mountBoard();
      wrapper
        .findComponent(KanbanColumn)
        .vm.$emit('cobrarDocs', { id: 11, name: 'Ivone', conversation_id: 9 });
      await flushPromises();
      expect(dispatch).toHaveBeenCalledWith('leads/openDock', 9);
      expect(marcarSolicitados).toHaveBeenCalledWith(11, [
        { id: 1, title: 'Laudo', status: 'pendente' },
      ]);
      expect(
        wrapper.findComponent({ name: 'ConversationDock' }).props('rascunho')
      ).toContain('RAMON.DOCS.DRAFT.ITEM');
    });

    it('sem conversa: abre a gaveta', () => {
      const wrapper = mountBoard();
      wrapper
        .findComponent(KanbanColumn)
        .vm.$emit('cobrarDocs', { id: 11, conversation_id: null });
      expect(dispatch).toHaveBeenCalledWith('leads/select', 11);
    });
  });

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
