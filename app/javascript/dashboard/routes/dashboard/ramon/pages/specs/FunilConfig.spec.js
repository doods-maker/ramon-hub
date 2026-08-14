import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import FunilConfig from '../FunilConfig.vue';

const buildStore = ({ updateStage = vi.fn() } = {}) =>
  createStore({
    modules: {
      leadConfig: {
        namespaced: true,
        getters: {
          getBenefitTypes: () => [{ id: 1, name: 'BPC', position: 0 }],
          getPriorities: () => [
            { id: 1, name: 'Alta', weight: 3, position: 0 },
          ],
          getStages: () => [
            { id: 1, name: 'Novo', stalled_after_days: 3, probability: 20 },
            {
              id: 2,
              name: 'Qualificação',
              stalled_after_days: null,
              probability: null,
            },
          ],
        },
        actions: {
          updateStage,
        },
      },
    },
  });

const mountPage = ({ updateStage } = {}) => {
  const store = buildStore({ updateStage });
  return mount(FunilConfig, {
    global: { plugins: [store], mocks: { $t: k => k } },
  });
};

it('adiciona um benefício ao confirmar o nome', async () => {
  const wrapper = mountPage();
  wrapper.vm.$store.dispatch = vi.fn().mockResolvedValue({});
  await wrapper.find('[data-testid="benefit-new-input"]').setValue('Revisão');
  await wrapper.find('[data-testid="benefit-add"]').trigger('click');
  expect(wrapper.vm.$store.dispatch).toHaveBeenCalledWith(
    'leadConfig/createBenefitType',
    {
      name: 'Revisão',
    }
  );
});

it('renders one cadence input per stage and saves on change', async () => {
  const updateStage = vi.fn();
  const wrapper = mountPage({ updateStage });
  const inputs = wrapper.findAll('[data-testid="stage-stalled-days"]');
  expect(inputs).toHaveLength(2);
  expect(inputs[0].element.value).toBe('3');

  await inputs[1].setValue('5');
  expect(updateStage).toHaveBeenCalledWith(expect.anything(), {
    id: 2,
    stalled_after_days: 5,
  });
});

it('truncates decimals before saving', async () => {
  const updateStage = vi.fn();
  const wrapper = mountPage({ updateStage });
  const first = wrapper.findAll('[data-testid="stage-stalled-days"]')[0];
  await first.setValue('2.5');
  expect(updateStage).toHaveBeenCalledWith(expect.anything(), {
    id: 1,
    stalled_after_days: 2,
  });
});

it('does not save when the value is unchanged', async () => {
  const updateStage = vi.fn();
  const wrapper = mountPage({ updateStage });
  const first = wrapper.findAll('[data-testid="stage-stalled-days"]')[0];
  await first.setValue('3');
  expect(updateStage).not.toHaveBeenCalled();
});

it('clears the limit when the input is emptied', async () => {
  const updateStage = vi.fn();
  const wrapper = mountPage({ updateStage });
  const first = wrapper.findAll('[data-testid="stage-stalled-days"]')[0];
  await first.setValue('');
  expect(updateStage).toHaveBeenCalledWith(expect.anything(), {
    id: 1,
    stalled_after_days: null,
  });
});

it('renders one probability input per stage and saves on change', async () => {
  const updateStage = vi.fn();
  const wrapper = mountPage({ updateStage });
  const inputs = wrapper.findAll('[data-testid="stage-probability"]');
  expect(inputs).toHaveLength(2);
  expect(inputs[0].element.value).toBe('20');

  await inputs[1].setValue('50');
  expect(updateStage).toHaveBeenCalledWith(expect.anything(), {
    id: 2,
    probability: 50,
  });
});

it('clamps probability above 100 before saving', async () => {
  const updateStage = vi.fn();
  const wrapper = mountPage({ updateStage });
  const first = wrapper.findAll('[data-testid="stage-probability"]')[0];
  await first.setValue('150');
  expect(updateStage).toHaveBeenCalledWith(expect.anything(), {
    id: 1,
    probability: 100,
  });
});

it('does not save probability when the value is unchanged', async () => {
  const updateStage = vi.fn();
  const wrapper = mountPage({ updateStage });
  const first = wrapper.findAll('[data-testid="stage-probability"]')[0];
  await first.setValue('20');
  expect(updateStage).not.toHaveBeenCalled();
});

it('clears probability when the input is emptied', async () => {
  const updateStage = vi.fn();
  const wrapper = mountPage({ updateStage });
  const first = wrapper.findAll('[data-testid="stage-probability"]')[0];
  await first.setValue('');
  expect(updateStage).toHaveBeenCalledWith(expect.anything(), {
    id: 1,
    probability: null,
  });
});
