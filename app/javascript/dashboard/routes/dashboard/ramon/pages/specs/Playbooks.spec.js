import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import Playbooks from '../Playbooks.vue';

const theses = [
  { id: 1, name: 'Auxílio-acidente', active: true, position: 0 },
  { id: 2, name: 'BPC/LOAS', active: false, position: 1 },
];

const buildStore = () =>
  createStore({
    modules: {
      theses: {
        namespaced: true,
        getters: {
          getTheses: () => theses,
          getThesis: () => id => theses.find(t => t.id === id),
          getUIFlags: () => ({ isFetching: false }),
        },
      },
    },
  });

const mountPlaybooks = () => {
  const store = buildStore();
  store.dispatch = vi.fn().mockResolvedValue({});
  const wrapper = mount(Playbooks, {
    global: { plugins: [store], mocks: { $t: k => k } },
  });
  return { wrapper, store };
};

describe('Playbooks.vue', () => {
  it('renders the thesis list from the store', () => {
    const { wrapper } = mountPlaybooks();
    const items = wrapper.findAll('[data-testid="playbooks-item"]');
    expect(items).toHaveLength(2);
    expect(wrapper.text()).toContain('Auxílio-acidente');
    expect(wrapper.text()).toContain('BPC/LOAS');
  });

  it('fetches theses on mount', () => {
    const { store } = mountPlaybooks();
    expect(store.dispatch).toHaveBeenCalledWith('theses/get');
  });

  it('dispatches theses/create when adding a new thesis', async () => {
    const { wrapper, store } = mountPlaybooks();
    await wrapper
      .find('[data-testid="playbooks-add-input"]')
      .setValue('Trabalhista');
    await wrapper.find('[data-testid="playbooks-add-button"]').trigger('click');
    expect(store.dispatch).toHaveBeenCalledWith('theses/create', {
      name: 'Trabalhista',
    });
  });

  it('shows the empty detail state when no thesis is selected', () => {
    const { wrapper } = mountPlaybooks();
    expect(
      wrapper.find('[data-testid="playbooks-empty-detail"]').exists()
    ).toBe(true);
  });
});
