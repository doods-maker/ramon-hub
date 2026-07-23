import { mount, flushPromises } from '@vue/test-utils';
import RadarPrescricao from '../RadarPrescricao.vue';
import RamonPrescriptionRadarAPI from 'dashboard/api/ramonPrescriptionRadar';

// t com params visíveis no texto pra testar contagens interpoladas.
const t = (key, params) =>
  params ? `${key} ${Object.values(params).join(' ')}` : key;
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t }) }));

const routerPush = vi.fn();
vi.mock('vue-router', () => ({ useRouter: () => ({ push: routerPush }) }));

const dispatchSpy = vi.fn();
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: dispatchSpy }),
}));

vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    accountScopedRoute: (name, params) => ({ name, params }),
  }),
}));

vi.mock('dashboard/api/ramonPrescriptionRadar', () => ({
  default: { get: vi.fn() },
}));

const payload = () => ({
  summary: {
    bleeding_monthly: 11240,
    bleeding_count: 8,
    at_risk_90d_monthly: 23700,
    at_risk_90d_count: 5,
  },
  items: [
    {
      lead_id: 1,
      name: 'Maria de Lourdes Souza',
      benefit_type_name: 'B31',
      dcb_em: '2021-03-03',
      stage_name: 'Qualificado',
      is_lost: false,
      monthly_value: 1412,
      lost_installments: 4,
      months_to_cliff: 0,
      pct_consumed: 1,
      consent_marketing: true,
    },
    {
      lead_id: 2,
      name: 'Osmar Vieira da Cunha',
      benefit_type_name: 'B32',
      dcb_em: '2020-11-10',
      stage_name: 'Perdido',
      is_lost: true,
      monthly_value: 2106,
      lost_installments: 9,
      months_to_cliff: 0,
      pct_consumed: 1,
      consent_marketing: true,
    },
    {
      lead_id: 3,
      name: 'João Batista Ferreira',
      benefit_type_name: 'B94',
      dcb_em: '2021-09-15',
      stage_name: 'Novo',
      is_lost: false,
      monthly_value: 1830,
      lost_installments: 0,
      months_to_cliff: 2,
      pct_consumed: 0.966,
      consent_marketing: false,
    },
  ],
});

const mountPage = async (response = { data: payload() }) => {
  RamonPrescriptionRadarAPI.get.mockResolvedValue(response);
  const wrapper = mount(RadarPrescricao, {
    global: { mocks: { $t: t } },
  });
  await flushPromises();
  return wrapper;
};

describe('RadarPrescricao.vue', () => {
  beforeEach(() => {
    routerPush.mockClear();
    dispatchSpy.mockClear();
  });

  it('renders the summary line with bleeding and at-risk numbers', async () => {
    const wrapper = await mountPage();
    const summaryText = wrapper.find('[data-testid="radar-summary"]').text();
    expect(summaryText).toContain('RAMON.RADAR.SUMMARY_BLEEDING 8');
    expect(summaryText).toContain('RAMON.RADAR.SUMMARY_RISK');
  });

  it('renders rows in the order the backend sent (bleeding first)', async () => {
    const wrapper = await mountPage();
    const names = wrapper
      .findAll('[data-testid="radar-row"]')
      .map(row => row.find('p').text());
    expect(names).toEqual([
      'Maria de Lourdes Souza',
      'Osmar Vieira da Cunha',
      'João Batista Ferreira',
    ]);
  });

  it('shows the amber lost chip only on lost leads', async () => {
    const wrapper = await mountPage();
    const rows = wrapper.findAll('[data-testid="radar-row"]');
    expect(rows[1].find('[data-testid="radar-lost-chip"]').exists()).toBe(true);
    expect(rows[0].find('[data-testid="radar-lost-chip"]').exists()).toBe(
      false
    );
  });

  it('counts only consented contacts in the campaign CTA', async () => {
    const wrapper = await mountPage();
    const cta = wrapper.find('[data-testid="radar-campaign-cta"]');
    expect(cta.text()).toBe('RAMON.RADAR.CAMPAIGN_CTA 2');
  });

  it('opens the lead in the funil on row click', async () => {
    const wrapper = await mountPage();
    await wrapper.findAll('[data-testid="radar-row"]')[1].trigger('click');
    expect(routerPush).toHaveBeenCalledWith({
      name: 'ramon_funil',
      params: undefined,
    });
    expect(dispatchSpy).toHaveBeenCalledWith('leads/select', 2);
  });

  it('confirming the campaign modal navigates to WhatsApp campaigns', async () => {
    const wrapper = await mountPage();
    await wrapper.find('[data-testid="radar-campaign-cta"]').trigger('click');
    await wrapper
      .find('[data-testid="confirm-modal-confirm"]')
      .trigger('click');
    expect(routerPush).toHaveBeenCalledWith({
      name: 'campaigns_whatsapp_index',
      params: undefined,
    });
  });

  it('shows error state with retry when the request fails', async () => {
    RamonPrescriptionRadarAPI.get.mockRejectedValue(new Error('boom'));
    const wrapper = mount(RadarPrescricao, {
      global: { mocks: { $t: t } },
    });
    await flushPromises();
    expect(wrapper.find('[data-testid="radar-error"]').exists()).toBe(true);
    RamonPrescriptionRadarAPI.get.mockResolvedValue({ data: payload() });
    await wrapper.find('[data-testid="radar-retry"]').trigger('click');
    await flushPromises();
    expect(wrapper.findAll('[data-testid="radar-row"]')).toHaveLength(3);
  });

  it('shows the empty state when there is nothing at risk', async () => {
    const wrapper = await mountPage({
      data: {
        summary: {
          bleeding_monthly: 0,
          bleeding_count: 0,
          at_risk_90d_monthly: 0,
          at_risk_90d_count: 0,
        },
        items: [],
      },
    });
    expect(wrapper.find('[data-testid="radar-empty"]').exists()).toBe(true);
  });
});
