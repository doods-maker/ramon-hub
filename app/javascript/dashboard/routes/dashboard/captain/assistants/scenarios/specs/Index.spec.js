import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import Index from '../Index.vue';

const { push } = vi.hoisted(() => ({ push: vi.fn() }));

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('vue-router', async importOriginal => ({
  ...(await importOriginal()),
  useRoute: () => ({ params: { assistantId: '1' } }),
  useRouter: () => ({ push }),
}));
vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({
    uiSettings: { value: { show_scenarios_suggestions: false } },
    updateUISettings: vi.fn(),
  }),
}));
vi.mock('dashboard/composables/useAdmin', () => ({
  useAdmin: () => ({ isAdmin: true }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const montar = () => {
  const scenarios = [
    { id: 1, title: 'A', enabled: true, edited: false, exemplo: 'Fala A' },
    { id: 2, title: 'B', enabled: false, edited: false },
  ];
  const store = createStore({
    modules: {
      captainScenarios: {
        namespaced: true,
        getters: { getRecords: () => scenarios, getUIFlags: () => ({}) },
        actions: { get: () => {}, update: () => {} },
      },
      teams: {
        namespaced: true,
        getters: { getTeams: () => [] },
        actions: { get: () => {} },
      },
      captainTools: {
        namespaced: true,
        getters: { getRecords: () => [] },
        actions: { getTools: () => {} },
      },
    },
  });
  return mount(Index, {
    global: {
      plugins: [store],
      mocks: { $t: key => key },
      stubs: {
        PageLayout: { template: '<div><slot name="body" /></div>' },
        SettingsHeader: true,
        ScenariosCard: true,
        AddNewScenariosDialog: true,
        Input: true,
        Button: true,
        BulkSelectBar: {
          props: ['modelValue'],
          template: '<i data-testid="bulk" :data-n="modelValue.size" />',
        },
      },
    },
  });
};

describe('Skills — abas e seleção em lote', () => {
  it('trocar de aba limpa a seleção', async () => {
    const wrapper = montar();
    wrapper.findComponent({ name: 'BulkSelectBar' });
    const bulk = () => wrapper.find('[data-testid="bulk"]');
    wrapper.vm.$.setupState.bulkSelectedIds = new Set([1]);
    await wrapper.vm.$nextTick();
    expect(bulk().attributes('data-n')).toBe('1');
    await wrapper
      .findAll('[data-testid="skills-abas"] button')[1]
      .trigger('click');
    expect(bulk().attributes('data-n')).toBe('0');
  });
});

describe('Skills — Testar esta skill', () => {
  it('abre o Testar do mesmo assistente com a fala de exemplo', async () => {
    const wrapper = montar();
    wrapper.findAllComponents({ name: 'ScenariosCard' })[0].vm.$emit('testar');
    expect(push).toHaveBeenCalledWith(
      expect.objectContaining({
        name: 'captain_assistants_playground_index',
        query: { fala: 'Fala A' },
      })
    );
  });
});
