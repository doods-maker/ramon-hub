import { mount } from '@vue/test-utils';
import MiniEsteira from '../MiniEsteira.vue';

const stages = [
  { id: 1, name: 'Novo', position: 1, is_lost: false },
  { id: 2, name: 'Qualificação', position: 2, is_lost: false },
  { id: 3, name: 'Reunião', position: 3, is_lost: false },
  { id: 9, name: 'Perdido', position: 9, is_lost: true },
];

describe('MiniEsteira', () => {
  it('renderiza uma barra por etapa não-perdida, na ordem de position', () => {
    const wrapper = mount(MiniEsteira, {
      props: { stages, currentId: 2 },
    });
    expect(wrapper.findAll('[data-testid="mini-esteira-barra"]')).toHaveLength(
      3
    );
  });

  it('marca feitas e atual em bronze; futuras no trilho', () => {
    const wrapper = mount(MiniEsteira, {
      props: { stages, currentId: 2 },
    });
    const barras = wrapper.findAll('[data-testid="mini-esteira-barra"]');
    expect(barras[0].classes()).toContain('bg-n-iris-9');
    expect(barras[1].classes()).toContain('bg-n-iris-9');
    expect(barras[2].classes()).toContain('bg-n-alpha-2');
  });
});
