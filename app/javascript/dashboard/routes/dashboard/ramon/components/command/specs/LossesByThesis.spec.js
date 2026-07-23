import { mount } from '@vue/test-utils';
import LossesByThesis from '../LossesByThesis.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));

const losses = {
  window_days: 90,
  theses: [
    {
      thesis_id: 1,
      name: 'Restabelecimento B31',
      total: 8,
      prev_total: 5,
      reasons: [
        { reason: 'Sem carência', count: 4 },
        { reason: 'Fechou c/ outro', count: 2 },
        { reason: 'Sem interesse', count: 2 },
      ],
    },
    {
      thesis_id: 2,
      name: 'Auxílio-acidente (B94)',
      total: 4,
      prev_total: 6,
      reasons: [
        { reason: 'Fechou c/ outro', count: 3 },
        { reason: 'Sem interesse', count: 1 },
      ],
    },
    {
      thesis_id: null,
      name: 'Sem tese',
      total: 2,
      prev_total: 0,
      reasons: [{ reason: '—', count: 2 }],
    },
  ],
};

const mountLosses = () =>
  mount(LossesByThesis, {
    props: { losses },
    global: { mocks: { $t: k => k } },
  });

describe('LossesByThesis.vue', () => {
  it('renders every thesis with stacked reason segments by default', () => {
    const wrapper = mountLosses();
    expect(wrapper.findAll('[data-testid="losses-thesis"]')).toHaveLength(3);
    const first = wrapper.find('[data-testid="losses-thesis"]');
    expect(first.findAll('[data-testid="losses-segment"]')).toHaveLength(3);
    expect(first.text()).toContain('Sem carência · 4');
  });

  it('shows the right delta per thesis: up (ruby), down (teal), none', () => {
    const wrapper = mountLosses();
    const deltas = wrapper.findAll('[data-testid="losses-delta"]');
    expect(deltas[0].text()).toContain('RAMON.COMMAND.LOSSES.DELTA_UP');
    expect(deltas[0].classes()).toContain('text-n-ruby-11');
    expect(deltas[1].text()).toContain('RAMON.COMMAND.LOSSES.DELTA_DOWN');
    expect(deltas[1].classes()).toContain('text-n-teal-11');
    expect(deltas[2].text()).toContain('RAMON.COMMAND.LOSSES.DELTA_NONE');
  });

  it('shows the signal line only when a reason dominates (≥50%)', () => {
    const wrapper = mountLosses();
    const theses = wrapper.findAll('[data-testid="losses-thesis"]');
    // 4 de 8 = 50% → sinal; 3 de 4 = 75% → sinal; razão "—" domina mas conta
    expect(theses[0].find('[data-testid="losses-signal"]').exists()).toBe(true);
    expect(theses[1].find('[data-testid="losses-signal"]').exists()).toBe(true);
  });

  it('filters to a single thesis through the selector', async () => {
    const wrapper = mountLosses();
    await wrapper.find('[data-testid="losses-thesis-select"]').setValue('2');
    const visible = wrapper.findAll('[data-testid="losses-thesis"]');
    expect(visible).toHaveLength(1);
    expect(visible[0].text()).toContain('Auxílio-acidente');
  });
});
