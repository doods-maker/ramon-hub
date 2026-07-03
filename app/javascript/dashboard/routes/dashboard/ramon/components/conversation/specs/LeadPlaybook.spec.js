import { shallowMount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import LeadPlaybook from '../LeadPlaybook.vue';

const thesisWithItems = {
  id: 1,
  name: 'Auxílio-acidente',
  active: true,
  position: 0,
  items: [
    { id: 1, section: 'abertura', title: 'Abrir', content: 'Bom dia…' },
    {
      id: 2,
      section: 'qualificacao',
      title: 'Perguntar sobre o acidente',
      content: 'Me conta como aconteceu o acidente.',
    },
    {
      id: 3,
      section: 'objecao',
      title: null,
      content: 'Entendo a preocupação, mas…',
    },
    {
      id: 4,
      section: 'documento',
      title: 'CAT',
      content: 'Precisamos da CAT.',
    },
  ],
};

const thesisWithoutItems = {
  id: 2,
  name: 'BPC/LOAS',
  active: true,
  position: 1,
};

const build = (theses, showSpy = vi.fn()) =>
  createStore({
    modules: {
      theses: {
        namespaced: true,
        getters: { getTheses: () => theses },
        actions: { show: showSpy },
      },
    },
  });

const mountPlaybook = (lead, theses = [thesisWithItems], showSpy = vi.fn()) =>
  shallowMount(LeadPlaybook, {
    props: { lead },
    global: {
      plugins: [build(theses, showSpy)],
      mocks: { $t: k => k },
    },
  });

describe('LeadPlaybook.vue', () => {
  beforeEach(() => {
    Object.assign(navigator, {
      clipboard: { writeText: vi.fn().mockResolvedValue() },
    });
  });

  it('shows the empty state when the lead has no thesis', () => {
    const wrapper = mountPlaybook({ id: 1, thesis_id: null });
    expect(wrapper.find('[data-testid="playbook-empty"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="playbook-section"]').exists()).toBe(
      false
    );
  });

  it('renders only qualificacao/objecao/documento sections, grouped, when the thesis has items', () => {
    const wrapper = mountPlaybook({ id: 1, thesis_id: 1 });
    const sections = wrapper.findAll('[data-testid="playbook-section"]');
    expect(sections).toHaveLength(3);

    const items = wrapper.findAll('[data-testid="playbook-item"]');
    expect(items).toHaveLength(3);
    expect(wrapper.text()).not.toContain('Bom dia');
    expect(wrapper.text()).toContain('Perguntar sobre o acidente');
    expect(wrapper.text()).toContain('Precisamos da CAT.');
  });

  it('fetches the thesis items when the selected thesis has none loaded yet', async () => {
    const show = vi.fn().mockResolvedValue(thesisWithItems);
    mountPlaybook({ id: 1, thesis_id: 2 }, [thesisWithoutItems], show);
    await flushPromises();
    expect(show).toHaveBeenCalledWith(expect.anything(), 2);
  });

  it('copies an item content to the clipboard and shows feedback', async () => {
    const wrapper = mountPlaybook({ id: 1, thesis_id: 1 });
    const button = wrapper.findAll('[data-testid="playbook-copy"]')[0];
    await button.trigger('click');
    expect(navigator.clipboard.writeText).toHaveBeenCalledWith(
      'Me conta como aconteceu o acidente.'
    );
    await flushPromises();
    expect(button.text()).toBe('RAMON.PLAYBOOK.COPIED');
  });
});
