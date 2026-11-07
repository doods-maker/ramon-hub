import { mount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import CaptainAssistantAPI from 'dashboard/api/captain/assistant';
import FunilConfig from '../FunilConfig.vue';

vi.mock('dashboard/api/captain/assistant', () => ({
  default: { get: vi.fn(() => Promise.reject(new Error('sem Captain'))) },
}));

const STAGES = [
  { id: 1, name: 'Novo', stalled_after_days: 3, probability: 20 },
  {
    id: 2,
    name: 'Qualificação',
    stalled_after_days: null,
    probability: null,
  },
];

const buildStore = ({ updateStage = vi.fn(), stages = STAGES } = {}) =>
  createStore({
    modules: {
      leadConfig: {
        namespaced: true,
        getters: {
          getPriorities: () => [
            { id: 1, name: 'Alta', weight: 3, position: 0 },
          ],
          getStages: () => stages,
        },
        actions: {
          updateStage,
        },
      },
    },
  });

const mountPage = ({ updateStage, stages } = {}) => {
  const store = buildStore({ updateStage, stages });
  return mount(FunilConfig, {
    global: {
      plugins: [store],
      mocks: { $t: k => k },
      stubs: { RouterLink: true },
    },
  });
};

it('aponta as teses para Playbooks (sem tipos de benefício)', () => {
  const wrapper = mountPage();
  expect(wrapper.text()).toContain('RAMON.FUNIL_CONFIG.THESES_HINT');
  expect(wrapper.find('[data-testid="benefit-new-input"]').exists()).toBe(
    false
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

it('dias até parado: 0 vira 1 (o servidor exige > 0)', async () => {
  const updateStage = vi.fn();
  const wrapper = mountPage({ updateStage });
  const first = wrapper.findAll('[data-testid="stage-stalled-days"]')[0];
  expect(first.attributes('min')).toBe('1');
  await first.setValue('0');
  expect(updateStage).toHaveBeenCalledWith(expect.anything(), {
    id: 1,
    stalled_after_days: 1,
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

it('etapa de ganho escolhe o assistente da etapa (vazio = o da caixa)', async () => {
  CaptainAssistantAPI.get.mockResolvedValueOnce({
    data: { payload: [{ id: 5, name: 'Documentos' }] },
  });
  const updateStage = vi.fn();
  const wrapper = mountPage({
    updateStage,
    stages: [
      ...STAGES,
      { id: 3, name: 'Documentos', is_won: true, captain_assistant_id: null },
      { id: 4, name: 'Jurídico', is_won: true, captain_assistant_id: 5 },
    ],
  });
  await flushPromises();
  const selects = wrapper.findAll('[data-testid="stage-assistente"]');
  expect(selects).toHaveLength(2);

  await selects[0].setValue('5');
  expect(updateStage).toHaveBeenLastCalledWith(expect.anything(), {
    id: 3,
    captain_assistant_id: 5,
  });
  await selects[1].setValue('');
  expect(updateStage).toHaveBeenLastCalledWith(expect.anything(), {
    id: 4,
    captain_assistant_id: null,
  });
});

it('sem assistentes (sem o Captain), nada de seletor', async () => {
  const wrapper = mountPage({
    stages: [{ id: 3, name: 'Documentos', is_won: true }],
  });
  await flushPromises();
  expect(wrapper.find('[data-testid="stage-assistente"]').exists()).toBe(false);
});
