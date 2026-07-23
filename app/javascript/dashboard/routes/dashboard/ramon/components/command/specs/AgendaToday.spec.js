import { mount } from '@vue/test-utils';
import AgendaToday from '../AgendaToday.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));

const items = [
  {
    id: 1,
    lead_id: 10,
    lead_name: 'Antônio Carlos',
    title: 'Reunião de fechamento',
    due_at: new Date(Date.now() - 60 * 60 * 1000).toISOString(),
    user_name: 'Camila',
    source: 'Cal.com',
  },
  {
    id: 2,
    lead_id: 11,
    lead_name: 'Zilda Pereira',
    title: 'Assinatura de contrato',
    due_at: new Date(Date.now() + 60 * 60 * 1000).toISOString(),
    user_name: 'Eduardo',
    source: null,
  },
];

const mountAgenda = (props = { items }) =>
  mount(AgendaToday, { props, global: { mocks: { $t: k => k } } });

describe('AgendaToday.vue', () => {
  it('renders one row per meeting with the meta line', () => {
    const wrapper = mountAgenda();
    const rows = wrapper.findAll('[data-testid="agenda-item"]');
    expect(rows).toHaveLength(2);
    expect(rows[0].text()).toContain('Antônio Carlos');
    expect(rows[0].text()).toContain(
      'Reunião de fechamento · Camila · Cal.com'
    );
    // source nulo não vira "· null" na linha de meta
    expect(rows[1].text()).toContain('Assinatura de contrato · Eduardo');
    expect(rows[1].text()).not.toContain('null');
  });

  it('highlights the time block of the next upcoming meeting only', () => {
    const wrapper = mountAgenda();
    const rows = wrapper.findAll('[data-testid="agenda-item"]');
    expect(rows[0].find('.bg-\\[\\#c9a97c\\]\\/\\[\\.12\\]').exists()).toBe(
      false
    );
    expect(rows[1].find('.bg-\\[\\#c9a97c\\]\\/\\[\\.12\\]').exists()).toBe(
      true
    );
  });

  it('emits select with the lead id and viewWeek from the footer', async () => {
    const wrapper = mountAgenda();
    await wrapper.find('[data-testid="agenda-item"]').trigger('click');
    expect(wrapper.emitted('select')[0]).toEqual([10]);
    await wrapper.find('[data-testid="agenda-view-week"]').trigger('click');
    expect(wrapper.emitted('viewWeek')).toHaveLength(1);
  });

  it('shows the empty state when there are no meetings', () => {
    const wrapper = mountAgenda({ items: [] });
    expect(wrapper.find('[data-testid="agenda-empty"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="agenda-view-week"]').exists()).toBe(
      false
    );
  });
});
