import { mount } from '@vue/test-utils';
import FunilConfig from '../FunilConfig.vue';

const makeStore = dispatch => ({
  dispatch,
  getters: {
    'leadConfig/getBenefitTypes': {
      value: [{ id: 1, name: 'BPC', position: 0 }],
    },
    'leadConfig/getPriorities': {
      value: [{ id: 1, name: 'Alta', weight: 3, position: 0 }],
    },
  },
});

it('adiciona um benefício ao confirmar o nome', async () => {
  const dispatch = vi.fn().mockResolvedValue({});
  const wrapper = mount(FunilConfig, {
    global: { mocks: { $t: k => k }, provide: { store: makeStore(dispatch) } },
  });
  await wrapper.find('[data-testid="benefit-new-input"]').setValue('Revisão');
  await wrapper.find('[data-testid="benefit-add"]').trigger('click');
  expect(dispatch).toHaveBeenCalledWith('leadConfig/createBenefitType', {
    name: 'Revisão',
  });
});
