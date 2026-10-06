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

const build = (theses, showSpy = vi.fn(), stages = []) =>
  createStore({
    modules: {
      theses: {
        namespaced: true,
        getters: { getTheses: () => theses },
        actions: { show: showSpy },
      },
      leadConfig: {
        namespaced: true,
        getters: { getStages: () => stages },
      },
    },
  });

const mountPlaybook = (
  lead,
  theses = [thesisWithItems],
  showSpy = vi.fn(),
  stages = []
) =>
  shallowMount(LeadPlaybook, {
    props: { lead },
    global: {
      plugins: [build(theses, showSpy, stages)],
      mocks: { $t: k => k },
      stubs: { Button: false },
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
  it('destaca a seção da etapa pelo label, mesmo com a etapa renomeada', () => {
    const wrapper = mountPlaybook(
      { id: 1, thesis_id: 1, lead_stage_id: 9 },
      [thesisWithItems],
      vi.fn(),
      [{ id: 9, name: 'Proposta na mesa', label: 'fase-negociacao' }]
    );
    const first = wrapper.findAll('[data-testid="playbook-section"]')[0];
    expect(first.text()).toContain('RAMON.PLAYBOOK.SECTIONS.OBJECAO');
    expect(first.find('[data-testid="playbook-stage-badge"]').exists()).toBe(
      true
    );
  });
  it('copia o roteiro com {{nome}} já trocado pelo primeiro nome do lead', async () => {
    const thesis = {
      ...thesisWithItems,
      items: [
        {
          id: 7,
          section: 'qualificacao',
          title: 'Abrir',
          content: 'Olá {{nome}}, tudo bem?',
        },
      ],
    };
    const wrapper = mountPlaybook(
      { id: 1, thesis_id: 1, contact_name: 'Maria Souza' },
      [thesis]
    );
    await wrapper.find('[data-testid="playbook-copy"]').trigger('click');
    expect(navigator.clipboard.writeText).toHaveBeenCalledWith(
      'Olá Maria, tudo bem?'
    );
  });
});
