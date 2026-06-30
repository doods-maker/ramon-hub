import { mount } from '@vue/test-utils';
import StageHeaderMenu from '../StageHeaderMenu.vue';

const stage = {
  id: 1,
  name: 'Novo',
  color: '#fff',
  is_won: false,
  is_lost: false,
};

const stub = (props = {}) =>
  mount(StageHeaderMenu, {
    props: { stage, ...props },
    global: { mocks: { $t: k => k } },
  });

describe('StageHeaderMenu', () => {
  it('emite remove com a etapa ao clicar em remover', async () => {
    const wrapper = stub();
    await wrapper.find('[data-testid="stage-menu-toggle"]').trigger('click');
    await wrapper.find('[data-testid="stage-remove"]').trigger('click');
    expect(wrapper.emitted().remove[0]).toEqual([stage]);
  });

  it('emite setType ao escolher ganho', async () => {
    const wrapper = stub();
    await wrapper.find('[data-testid="stage-menu-toggle"]').trigger('click');
    await wrapper.find('[data-testid="stage-type-won"]').trigger('click');
    expect(wrapper.emitted().setType[0]).toEqual(['won']);
  });
});
