import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import FunilConfig from '../FunilConfig.vue';

const buildStore = () =>
  createStore({
    modules: {
      leadConfig: {
        namespaced: true,
        getters: {
          getBenefitTypes: () => [{ id: 1, name: 'BPC', position: 0 }],
          getPriorities: () => [
            { id: 1, name: 'Alta', weight: 3, position: 0 },
          ],
        },
      },
    },
  });

it('adiciona um benefício ao confirmar o nome', async () => {
  const store = buildStore();
  store.dispatch = vi.fn().mockResolvedValue({});
  const wrapper = mount(FunilConfig, {
    global: { plugins: [store], mocks: { $t: k => k } },
  });
  await wrapper.find('[data-testid="benefit-new-input"]').setValue('Revisão');
  await wrapper.find('[data-testid="benefit-add"]').trigger('click');
  expect(store.dispatch).toHaveBeenCalledWith('leadConfig/createBenefitType', {
    name: 'Revisão',
  });
});
