import { shallowMount, flushPromises } from '@vue/test-utils';
import LeadsAPI from 'dashboard/api/leads';
import LeadTriage from '../LeadTriage.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));

const alertSpy = vi.fn();
vi.mock('dashboard/composables', () => ({
  useAlert: (...a) => alertSpy(...a),
}));
vi.mock('shared/helpers/clipboard', () => ({
  copyTextToClipboard: vi.fn(),
}));
vi.mock('dashboard/api/leads', () => ({
  default: {
    getTriages: vi.fn(),
    createTriage: vi.fn(),
  },
}));

const mountTriage = lead =>
  shallowMount(LeadTriage, {
    props: { lead },
    global: { mocks: { $t: k => k } },
  });

describe('LeadTriage.vue', () => {
  beforeEach(() => {
    alertSpy.mockClear();
    LeadsAPI.getTriages.mockReset();
    LeadsAPI.createTriage.mockReset();
  });

  it('shows the empty state when there are no triages', async () => {
    LeadsAPI.getTriages.mockResolvedValue({ data: [] });
    const wrapper = mountTriage({ id: 3, latest_triage: null });
    await flushPromises();
    expect(wrapper.find('[data-testid="triage-empty"]').exists()).toBe(true);
  });

  it('renders the viability badge for the latest done triage', async () => {
    LeadsAPI.getTriages.mockResolvedValue({
      data: [
        {
          id: 1,
          status: 'done',
          viability: 'alta',
          result: 'Caso viável.',
          created_at: '2026-07-01',
        },
      ],
    });
    const wrapper = mountTriage({
      id: 3,
      latest_triage: { id: 1, status: 'done', viability: 'alta' },
    });
    await flushPromises();
    const badge = wrapper.find('[data-testid="triage-viability-badge"]');
    expect(badge.exists()).toBe(true);
    expect(badge.text()).toContain('RAMON.TRIAGE.VIABILITY.ALTA');
  });

  it('renders the triage result as markdown', async () => {
    LeadsAPI.getTriages.mockResolvedValue({
      data: [
        {
          id: 1,
          status: 'done',
          viability: 'alta',
          result: '**Viável** pela Súmula 47.',
          created_at: '2026-07-01',
        },
      ],
    });
    const wrapper = mountTriage({
      id: 3,
      latest_triage: { id: 1, status: 'done', viability: 'alta' },
    });
    await flushPromises();
    const result = wrapper.find('[data-testid="triage-result"]');
    expect(result.html()).toContain('<strong>Viável</strong>');
    expect(result.text()).not.toContain('**');
  });

  it('disables the run button while the latest triage is running', async () => {
    LeadsAPI.getTriages.mockResolvedValue({
      data: [{ id: 2, status: 'running', viability: null }],
    });
    const wrapper = mountTriage({
      id: 3,
      latest_triage: { id: 2, status: 'running' },
    });
    await flushPromises();
    expect(
      wrapper.find('[data-testid="triage-run"]').attributes('disabled')
    ).toBeDefined();
  });

  it('calls createTriage and reloads the list when clicking run', async () => {
    LeadsAPI.getTriages.mockResolvedValue({ data: [] });
    LeadsAPI.createTriage.mockResolvedValue({ data: {} });
    const wrapper = mountTriage({ id: 3, latest_triage: null });
    await flushPromises();
    await wrapper.find('[data-testid="triage-run"]').trigger('click');
    await flushPromises();
    expect(LeadsAPI.createTriage).toHaveBeenCalledWith(3);
    expect(alertSpy).toHaveBeenCalledWith('RAMON.TRIAGE.STARTED');
    expect(LeadsAPI.getTriages).toHaveBeenCalledTimes(2);
  });

  it('clears the previous lead triages and reloads when switching to a lead without a latest_triage', async () => {
    LeadsAPI.getTriages.mockResolvedValue({
      data: [
        {
          id: 1,
          status: 'done',
          viability: 'alta',
          result: 'Caso viável.',
          created_at: '2026-07-01',
        },
      ],
    });
    const wrapper = mountTriage({
      id: 3,
      latest_triage: { id: 1, status: 'done', viability: 'alta' },
    });
    await flushPromises();
    expect(wrapper.find('[data-testid="triage-latest"]').exists()).toBe(true);

    LeadsAPI.getTriages.mockResolvedValue({ data: [] });
    await wrapper.setProps({ lead: { id: 4, latest_triage: null } });
    await flushPromises();

    expect(LeadsAPI.getTriages).toHaveBeenCalledWith(4);
    expect(wrapper.find('[data-testid="triage-latest"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="triage-empty"]').exists()).toBe(true);
  });
});
