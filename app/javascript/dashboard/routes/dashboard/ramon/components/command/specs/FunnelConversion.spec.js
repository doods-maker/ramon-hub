import { mount } from '@vue/test-utils';
import FunnelConversion from '../FunnelConversion.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));

const stages = [
  {
    stage_id: 1,
    name: 'Novo',
    color: '#c9a97c',
    count: 18,
    total_value: 132000,
    weighted_value: 66000,
    is_won: false,
    is_lost: false,
  },
  {
    stage_id: 2,
    name: 'Qualificado',
    color: '#6b8f85',
    count: 0,
    total_value: 0,
    weighted_value: 0,
    is_won: false,
    is_lost: false,
  },
  {
    stage_id: 5,
    name: 'Ganhamos',
    color: '#12a594',
    count: 3,
    total_value: 95000,
    weighted_value: 95000,
    is_won: true,
    is_lost: false,
  },
  {
    stage_id: 6,
    name: 'Perdemos',
    color: '#e54666',
    count: 2,
    total_value: 0,
    weighted_value: 0,
    is_won: false,
    is_lost: true,
  },
];

const conversion = [
  { stage_id: 1, name: 'Novo', entered: 18, advanced: 11, rate: 61 },
  { stage_id: 2, name: 'Qualificado', entered: 0, advanced: 0, rate: 0 },
];

const mountFunnel = (props = { stages, conversion }) =>
  mount(FunnelConversion, { props, global: { mocks: { $t: k => k } } });

describe('FunnelConversion.vue', () => {
  it('renders open stages as rows, won as a separate row and no lost row', () => {
    const wrapper = mountFunnel();
    expect(wrapper.findAll('[data-testid="funnel-stage"]')).toHaveLength(2);
    expect(wrapper.find('[data-testid="funnel-won"]').text()).toContain(
      'Ganhamos'
    );
    expect(wrapper.text()).not.toContain('Perdemos');
  });

  it('only renders bar segments for open stages with leads', () => {
    const wrapper = mountFunnel();
    expect(wrapper.findAll('[data-testid="funnel-bar-segment"]')).toHaveLength(
      1
    );
  });

  it('shows the advance rate only for stages someone entered', () => {
    const wrapper = mountFunnel();
    const rates = wrapper.findAll('[data-testid="funnel-rate"]');
    expect(rates).toHaveLength(1);
    expect(rates[0].text()).toContain('RAMON.COMMAND.FUNNEL.ADVANCE');
  });

  it('emits stageSelect from both row and bar segment', async () => {
    const wrapper = mountFunnel();
    await wrapper.find('[data-testid="funnel-stage"]').trigger('click');
    await wrapper.find('[data-testid="funnel-bar-segment"]').trigger('click');
    expect(wrapper.emitted('stageSelect')).toEqual([[1], [1]]);
  });

  it('shows the empty message without stages', () => {
    const wrapper = mountFunnel({ stages: [], conversion: [] });
    expect(wrapper.text()).toContain('RAMON.COMMAND.FUNNEL.EMPTY');
  });
});
