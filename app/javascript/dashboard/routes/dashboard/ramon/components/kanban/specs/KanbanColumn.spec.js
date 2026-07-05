import { shallowMount, mount } from '@vue/test-utils';
import Draggable from 'vuedraggable';
import KanbanColumn from '../KanbanColumn.vue';
import LeadCard from '../LeadCard.vue';

const stage = { id: 5, name: 'Qualificação' };
const leads = [{ id: 10, name: 'João', lead_stage_id: 5, position: 0 }];

const mountColumn = (props = {}) =>
  shallowMount(KanbanColumn, {
    props: { stage, leads, ...props },
    global: { mocks: { $t: k => k } },
  });

describe('KanbanColumn.vue', () => {
  it('emite "move" com a etapa de destino quando um card chega (evt.added)', () => {
    const wrapper = mountColumn();
    wrapper
      .findComponent(Draggable)
      .vm.$emit('change', { added: { element: { id: 10 }, newIndex: 2 } });

    expect(wrapper.emitted('move')).toBeTruthy();
    expect(wrapper.emitted('move')[0][0]).toEqual({
      id: 10,
      leadStageId: 5,
      newIndex: 2,
    });
  });

  it('emite "move" ao reordenar na própria coluna (evt.moved)', () => {
    const wrapper = mountColumn();
    wrapper
      .findComponent(Draggable)
      .vm.$emit('change', { moved: { element: { id: 10 }, newIndex: 1 } });

    expect(wrapper.emitted('move')[0][0]).toEqual({
      id: 10,
      leadStageId: 5,
      newIndex: 1,
    });
  });

  it('NÃO emite "move" para a coluna de origem (evt.removed)', () => {
    const wrapper = mountColumn();
    wrapper
      .findComponent(Draggable)
      .vm.$emit('change', { removed: { element: { id: 10 }, oldIndex: 0 } });

    expect(wrapper.emitted('move')).toBeFalsy();
  });

  it('sincroniza a contagem local quando a prop leads muda', async () => {
    const wrapper = mountColumn();
    expect(wrapper.find('[data-testid="stage-count"]').text()).toBe('1');

    await wrapper.setProps({
      leads: [...leads, { id: 11, name: 'Ana', lead_stage_id: 5, position: 1 }],
    });
    expect(wrapper.find('[data-testid="stage-count"]').text()).toBe('2');
  });

  it('re-emite openLead vindo do LeadCard', () => {
    const wrapper = mount(KanbanColumn, {
      props: { stage, leads },
      global: { mocks: { $t: k => k } },
    });
    wrapper.findComponent(LeadCard).vm.$emit('openLead', { id: 10 });
    expect(wrapper.emitted('openLead')[0][0]).toEqual({ id: 10 });
  });

  it('mostra a soma dos valores em BRL', () => {
    const wrapper = mount(KanbanColumn, {
      props: {
        stage: { id: 1, name: 'Novo', color: '#fff' },
        leads: [
          { id: 1, lead_stage_id: 1, value: 1500 },
          { id: 2, lead_stage_id: 1, value: null },
          { id: 3, lead_stage_id: 1, value: 500.5 },
        ],
      },
      global: { mocks: { $t: k => k } },
    });
    // 2000,50 formatado em pt-BR
    expect(wrapper.find('[data-testid="stage-total"]').text()).toContain(
      '2.000,50'
    );
  });

  describe('coluna colapsável', () => {
    beforeEach(() => localStorage.clear());

    it('colapsa ao clicar no toggle e esconde a lista de cards', async () => {
      const wrapper = mount(KanbanColumn, {
        props: { stage, leads },
        global: { mocks: { $t: k => k } },
      });
      await wrapper
        .find('[data-testid="stage-collapse-toggle"]')
        .trigger('click');
      expect(wrapper.findComponent(Draggable).exists()).toBe(false);
      // contador continua visível na faixa colapsada
      expect(wrapper.find('[data-testid="stage-count"]').text()).toBe('1');
    });

    it('expande de volta ao clicar na faixa colapsada', async () => {
      const wrapper = mount(KanbanColumn, {
        props: { stage, leads },
        global: { mocks: { $t: k => k } },
      });
      await wrapper
        .find('[data-testid="stage-collapse-toggle"]')
        .trigger('click');
      await wrapper.find('[data-testid="stage-expand"]').trigger('click');
      expect(wrapper.findComponent(Draggable).exists()).toBe(true);
    });

    it('persiste o estado em localStorage por stage id', async () => {
      const wrapper = mount(KanbanColumn, {
        props: { stage, leads },
        global: { mocks: { $t: k => k } },
      });
      await wrapper
        .find('[data-testid="stage-collapse-toggle"]')
        .trigger('click');
      expect(
        JSON.parse(localStorage.getItem('ramon_kanban_collapsed'))
      ).toContain(stage.id);

      // um remount da mesma etapa nasce colapsado
      const wrapper2 = mount(KanbanColumn, {
        props: { stage, leads },
        global: { mocks: { $t: k => k } },
      });
      expect(wrapper2.findComponent(Draggable).exists()).toBe(false);
    });
  });

  describe('empty state da coluna', () => {
    beforeEach(() => localStorage.clear());

    it('mostra hint quando não há leads', () => {
      const wrapper = mount(KanbanColumn, {
        props: { stage, leads: [] },
        global: { mocks: { $t: k => k } },
      });
      expect(wrapper.find('[data-testid="column-empty"]').exists()).toBe(true);
    });

    it('não mostra hint quando há leads', () => {
      const wrapper = mount(KanbanColumn, {
        props: { stage, leads },
        global: { mocks: { $t: k => k } },
      });
      expect(wrapper.find('[data-testid="column-empty"]').exists()).toBe(false);
    });
  });
});
