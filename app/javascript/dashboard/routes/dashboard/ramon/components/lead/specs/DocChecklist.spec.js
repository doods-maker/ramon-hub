import { shallowMount } from '@vue/test-utils';
import { createStore } from 'vuex';
import DocChecklist from '../DocChecklist.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));

const alertSpy = vi.fn();
const clipboardSpy = vi.fn();
vi.mock('dashboard/composables', () => ({
  useAlert: (...a) => alertSpy(...a),
}));
vi.mock('shared/helpers/clipboard', () => ({
  copyTextToClipboard: (...a) => clipboardSpy(...a),
}));

const thesis = {
  id: 1,
  name: 'Auxílio-acidente',
  items: [
    { id: 2, section: 'qualificacao', title: 'Q', content: 'q' },
    { id: 4, section: 'documento', title: 'CAT', content: 'A CAT.' },
    { id: 5, section: 'documento', title: 'Laudo', content: 'O laudo.' },
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
  shallowMount(DocChecklist, {
    props: { lead },
    global: { plugins: [build(updateSpy)], mocks: { $t: k => k } },
  });

const baseLead = {
  id: 3,
  name: 'Ana',
  thesis_id: 1,
  custom_attributes: { foo: 'bar', doc_status: { 5: 'recebido' } },
};

describe('DocChecklist.vue', () => {
  beforeEach(() => {
    alertSpy.mockClear();
    clipboardSpy.mockClear();
  });

  it('does not render when the lead has no thesis', () => {
    const wrapper = mountChecklist({ id: 3, thesis_id: null });
    expect(wrapper.find('[data-testid="doc-checklist"]').exists()).toBe(false);
  });

  it('renders one chip per documento item and a received count', () => {
    const wrapper = mountChecklist(baseLead);
    expect(wrapper.findAll('[data-testid="doc-chip"]')).toHaveLength(2);
    // item 5 recebido, item 4 pendente → 1/2
    expect(wrapper.find('[data-testid="doc-count"]').text()).toContain(
      'RAMON.DOCS.COUNT'
    );
  });

  it('cycles a chip status and dispatches update merging custom_attributes', async () => {
    const update = vi.fn();
    const wrapper = mountChecklist(baseLead, update);
    // primeiro chip = item 4 (pendente) → solicitado
    await wrapper.findAll('[data-testid="doc-chip"]')[0].trigger('click');
    expect(update).toHaveBeenCalledWith(expect.anything(), {
      id: 3,
      custom_attributes: {
        foo: 'bar',
        doc_status: { 5: 'recebido', 4: 'solicitado' },
      },
    });
  });

  it('charges pending: copies a draft, alerts and marks pendentes as solicitado', async () => {
    const update = vi.fn();
    const wrapper = mountChecklist(baseLead, update);
    await wrapper.find('[data-testid="doc-charge"]').trigger('click');
    expect(clipboardSpy).toHaveBeenCalledTimes(1);
    expect(alertSpy).toHaveBeenCalledWith('RAMON.DOCS.COPIED');
    expect(update).toHaveBeenCalledWith(expect.anything(), {
      id: 3,
      custom_attributes: {
        foo: 'bar',
        doc_status: { 5: 'recebido', 4: 'solicitado' },
      },
    });
  });

  it('disables the charge button when every document is received', () => {
    const lead = {
      ...baseLead,
      custom_attributes: { doc_status: { 4: 'recebido', 5: 'recebido' } },
    };
    const wrapper = mountChecklist(lead);
    expect(
      wrapper.find('[data-testid="doc-charge"]').attributes('disabled')
    ).toBeDefined();
  });
});
