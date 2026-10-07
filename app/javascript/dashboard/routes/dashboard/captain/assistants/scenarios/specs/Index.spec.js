import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import Index from '../Index.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('vue-router', async importOriginal => ({
  ...(await importOriginal()),
  useRoute: () => ({ params: { assistantId: '1' } }),
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
    { id: 1, title: 'A', enabled: true, edited: false },
    { id: 2, title: 'B', enabled: false, edited: false },
  ];
  const store = createStore({
    modules: {
      captainScenarios: {
        namespaced: true,
        getters: { getRecords: () => scenarios, getUIFlags: () => ({}) },
        actions: { get: () => {}, update: () => {} },
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
