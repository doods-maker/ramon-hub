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
    expect(rows[0].find('.text-n-blue-11').exists()).toBe(false);
    expect(rows[1].find('.text-n-blue-11').exists()).toBe(true);
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

  it('apaga a reunião feita (check) e marca a vencida', () => {
    const wrapper = mountAgenda({
      items: [
        { ...items[0], id: 7, vencida: true, due_at: '2026-10-02T12:00:00Z' },
        { ...items[1], id: 8, completed_at: new Date().toISOString() },
      ],
    });
    const rows = wrapper.findAll('[data-testid="agenda-item"]');
    expect(rows[0].find('[data-testid="agenda-item-overdue"]').exists()).toBe(
      true
    );
    expect(rows[1].classes()).toContain('opacity-60');
    expect(rows[1].find('[data-testid="agenda-item-done"]').exists()).toBe(
      true
    );
    // feita não é "a próxima": nenhum bloco azul
    expect(rows.some(row => row.find('.text-n-blue-11').exists())).toBe(false);
  });
});
