import { shallowMount } from '@vue/test-utils';
import Draggable from 'vuedraggable';
import KanbanColumn from '../KanbanColumn.vue';

const stage = { id: 5, name: 'Qualificação' };
const leads = [{ id: 10, name: 'João', lead_stage_id: 5, position: 0 }];

const mountColumn = (props = {}) =>
  shallowMount(KanbanColumn, {
    props: { stage, leads, benefitTypes: [], priorities: [], ...props },
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
    expect(wrapper.find('.text-n-slate-9').text()).toBe('1');

    await wrapper.setProps({
      leads: [...leads, { id: 11, name: 'Ana', lead_stage_id: 5, position: 1 }],
    });
    expect(wrapper.find('.text-n-slate-9').text()).toBe('2');
  });
});
