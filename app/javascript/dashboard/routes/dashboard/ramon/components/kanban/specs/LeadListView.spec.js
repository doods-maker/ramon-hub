import { mount } from '@vue/test-utils';
import LeadListView from '../LeadListView.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

const stages = [
  { id: 1, name: 'Novo', color: '#a00' },
  { id: 2, name: 'Triagem', color: '#0a0' },
];

const leads = [
  {
    id: 10,
    name: 'Bia',
    lead_stage_id: 1,
    value: 100,
    sdr_name: 'Edu',
    thesis_name: 'B31',
    contact_phone: '+554899',
  },
  {
    id: 11,
    name: 'Ana',
    lead_stage_id: 2,
    value: 300,
    sdr_name: null,
    thesis_name: null,
    contact_phone: null,
  },
];

const mountList = (props = {}) =>
  mount(LeadListView, {
    props: { leads, stages, selectedLeadIds: [11], ...props },
    global: { mocks: { $t: k => k } },
  });

describe('LeadListView', () => {
  it('renderiza uma linha por lead, ordenada por nome', () => {
    const wrapper = mountList();
    const rows = wrapper.findAll('[data-testid="list-row"]');
    expect(rows).toHaveLength(2);
    expect(rows[0].text()).toContain('Ana');
    expect(rows[1].text()).toContain('Bia');
  });

  it('ordena por valor ao clicar no header (asc, depois desc)', async () => {
    const wrapper = mountList();
    await wrapper.find('[data-testid="list-sort-value"]').trigger('click');
    let rows = wrapper.findAll('[data-testid="list-row"]');
    expect(rows[0].text()).toContain('Bia');

    await wrapper.find('[data-testid="list-sort-value"]').trigger('click');
    rows = wrapper.findAll('[data-testid="list-row"]');
    expect(rows[0].text()).toContain('Ana');
  });

  it('clicar na linha emite openLead', async () => {
    const wrapper = mountList();
    await wrapper.find('[data-testid="list-row"]').trigger('click');
    expect(wrapper.emitted().openLead[0][0].name).toBe('Ana');
  });

  it('checkbox emite toggleSelect sem abrir a gaveta', async () => {
    const wrapper = mountList();
    await wrapper.find('[data-testid="list-select-toggle"]').trigger('click');
    expect(wrapper.emitted().toggleSelect).toBeTruthy();
    expect(wrapper.emitted().openLead).toBeFalsy();
  });

  it('marca o checkbox das linhas selecionadas', () => {
    const wrapper = mountList();
    const checks = wrapper.findAll('[data-testid="list-select-toggle"]');
    // primeira linha = Ana (id 11), selecionada
    expect(checks[0].classes()).toContain('bg-n-iris-9');
    expect(checks[1].classes()).not.toContain('bg-n-iris-9');
  });

  it('mostra o vazio quando não há leads', () => {
    const wrapper = mountList({ leads: [] });
    expect(wrapper.find('[data-testid="list-empty"]').exists()).toBe(true);
  });
});
