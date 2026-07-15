import { shallowMount } from '@vue/test-utils';
import { createStore } from 'vuex';
import ColheitaChecklist from '../ColheitaChecklist.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));

const thesis = {
  id: 1,
  name: 'Auxílio-acidente (B36)',
  items: [
    { id: 2, section: 'qualificacao', title: 'Q', content: 'q' },
    { id: 7, section: 'colheita', title: 'É aposentado?', content: 'why' },
    { id: 8, section: 'colheita', title: 'Data do acidente', content: 'why' },
  ],
};

const build = (updateSpy = vi.fn()) =>
  createStore({
    modules: {
      theses: {
        namespaced: true,
        getters: { getTheses: () => [thesis] },
        actions: { show: vi.fn() },
      },
      leads: { namespaced: true, actions: { update: updateSpy } },
    },
  });

const mountChecklist = (lead, updateSpy = vi.fn()) =>
  shallowMount(ColheitaChecklist, {
    props: { lead },
    global: { plugins: [build(updateSpy)], mocks: { $t: k => k } },
  });

const baseLead = {
  id: 3,
  name: 'Ana',
  thesis_id: 1,
  custom_attributes: { foo: 'bar', colheita_status: { 7: true } },
};

describe('ColheitaChecklist.vue', () => {
  it('does not render when the lead has no thesis', () => {
    const wrapper = mountChecklist({ id: 3, thesis_id: null });
    expect(wrapper.find('[data-testid="colheita-checklist"]').exists()).toBe(
      false
    );
  });

  it('renders one item per colheita item and a done count', () => {
    const wrapper = mountChecklist(baseLead);
    expect(wrapper.findAll('[data-testid="colheita-item"]')).toHaveLength(2);
    expect(wrapper.find('[data-testid="colheita-count"]').text()).toContain(
      'RAMON.COLHEITA.COUNT'
    );
  });

  it('toggles an item and dispatches update merging custom_attributes', async () => {
    const update = vi.fn();
    const wrapper = mountChecklist(baseLead, update);
    // segundo item = 8 (pendente) → colhido
    await wrapper.findAll('[data-testid="colheita-item"]')[1].trigger('click');
    expect(update).toHaveBeenCalledWith(expect.anything(), {
      id: 3,
      custom_attributes: {
        foo: 'bar',
        colheita_status: { 7: true, 8: true },
      },
    });
  });

  it('unchecks a checked item removing it from the map', async () => {
    const update = vi.fn();
    const wrapper = mountChecklist(baseLead, update);
    await wrapper.findAll('[data-testid="colheita-item"]')[0].trigger('click');
    expect(update).toHaveBeenCalledWith(expect.anything(), {
      id: 3,
      custom_attributes: { foo: 'bar', colheita_status: {} },
    });
  });

  it('shows the AI lacunas block when the extraction wrote them', () => {
    const lead = {
      ...baseLead,
      custom_attributes: {
        colheita: {
          lacunas: [{ campo: 'beneficios[0].dcb', como_obter: 'Meu INSS' }],
          extraida_em: '2026-07-15T10:00:00Z',
        },
      },
    };
    const wrapper = mountChecklist(lead);
    const block = wrapper.find('[data-testid="colheita-lacunas"]');
    expect(block.exists()).toBe(true);
    expect(block.text()).toContain('beneficios[0].dcb');
    expect(block.text()).toContain('Meu INSS');
  });

  it('hides the lacunas block without extraction data', () => {
    const wrapper = mountChecklist(baseLead);
    expect(wrapper.find('[data-testid="colheita-lacunas"]').exists()).toBe(
      false
    );
  });
});
