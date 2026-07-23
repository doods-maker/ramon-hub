import { mount, flushPromises } from '@vue/test-utils';
import { ref } from 'vue';
import CommandCenter from '../CommandCenter.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));

const routerPush = vi.fn();
vi.mock('vue-router', () => ({ useRouter: () => ({ push: routerPush }) }));

const dispatchSpy = vi.fn();
const dataRef = ref(null);
const flagsRef = ref({ isFetching: false, hasError: false });
const userRef = ref({ name: 'Eduardo Schlata' });
const roleRef = ref('administrator');
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: dispatchSpy }),
  useStoreGetters: () => ({
    'ramonDashboard/getData': dataRef,
    'ramonDashboard/getUIFlags': flagsRef,
    getCurrentUser: userRef,
    getCurrentRole: roleRef,
  }),
}));

vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    accountScopedRoute: (name, params) => ({ name, params }),
  }),
}));

const alertSpy = vi.fn();
vi.mock('dashboard/composables', () => ({
  useAlert: (...a) => alertSpy(...a),
}));

// Captura o mapa de atalhos pra disparar as ações direto nos testes.
let keyHandlers = {};
vi.mock('dashboard/composables/useKeyboardEvents', () => ({
  useKeyboardEvents: events => {
    keyHandlers = events;
  },
}));

// Maria tem DCB antiga + valor mensal → sangra prescrição e lidera a fila.
const payload = () => ({
  today: {
    tasks_overdue: {
      count: 1,
      items: [
        {
          id: 7,
          lead_id: 1,
          lead_name: 'Maria de Lourdes',
          title: 'Ligar após perícia',
          due_at: '2026-07-20T12:00:00Z',
          dcb_em: '2019-01-10',
          benefit_monthly_value: '1412.0',
        },
      ],
    },
    tasks_today: { count: 5, items: [] },
    stalled: {
      count: 1,
      items: [
        {
          id: 2,
          name: 'Sebastião Ramos',
          stage_name: 'Qualificado',
          days_in_stage: 14,
          conversation_id: 9,
          contact_phone: '+554899999999',
          dcb_em: null,
          benefit_monthly_value: null,
        },
      ],
    },
    no_next_action: { count: 0, items: [] },
    new_from_lp: { count: 6, items: [] },
  },
  funnel: [
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
      stage_id: 5,
      name: 'Ganhamos',
      color: '#12a594',
      count: 3,
      total_value: 95000,
      weighted_value: 95000,
      is_won: true,
      is_lost: false,
    },
  ],
  week: { won: 5, nps: { media: 9.4, respostas: 3 } },
  history: [
    { date: '2026-07-22', leads_count: 30, value_sum: 590000 },
    { date: '2026-07-23', leads_count: 32, value_sum: 616000 },
  ],
  goal: { target: 12, done: 5 },
  forecast_total: 187000,
  conversion: [
    { stage_id: 1, name: 'Novo', entered: 18, advanced: 11, rate: 61 },
  ],
  team_week: [
    {
      user_id: 1,
      name: 'Eduardo',
      avatar_url: null,
      won_count: 3,
      won_value: 95000,
      activities_count: 28,
    },
  ],
  agenda_today: [
    {
      id: 11,
      lead_id: 4,
      lead_name: 'Antônio Carlos',
      title: 'Reunião de fechamento',
      due_at: '2026-07-23T18:00:00Z',
      user_name: 'Camila',
      source: 'Cal.com',
    },
  ],
  losses_by_thesis: {
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
    ],
  },
  sla_today: { breached: 2, avg_first_response_minutes: 12.5 },
});

const mountPage = async (data = payload()) => {
  dataRef.value = data;
  const wrapper = mount(CommandCenter, { global: { mocks: { $t: k => k } } });
  await flushPromises();
  return wrapper;
};

describe('CommandCenter.vue', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    dataRef.value = null;
    flagsRef.value = { isFetching: false, hasError: false };
    roleRef.value = 'administrator';
    keyHandlers = {};
  });

  it('renders the greeting, daily goal and start-day CTA', async () => {
    const wrapper = await mountPage();
    expect(wrapper.find('h1').text()).toContain('RAMON.COMMAND.GREETING');
    expect(wrapper.find('[data-testid="daily-goal"]').text()).toContain(
      'RAMON.COMMAND.GOAL_PROGRESS'
    );
    await wrapper.find('[data-testid="start-day"]').trigger('click');
    expect(routerPush).toHaveBeenCalledWith({
      name: 'ramon_esteira',
      params: undefined,
    });
  });

  it('renders the six KPIs and the SLA subline', async () => {
    const wrapper = await mountPage();
    expect(wrapper.find('[data-testid="kpi-overdue"]').text()).toContain('1');
    expect(wrapper.find('[data-testid="kpi-today"]').text()).toContain('5');
    expect(wrapper.find('[data-testid="kpi-new_from_lp"]').text()).toContain(
      '6'
    );
    expect(wrapper.find('[data-testid="kpi-won_week"]').text()).toContain('5');
    expect(wrapper.find('[data-testid="kpi-forecast"]').text()).toContain('R$');
    expect(wrapper.find('[data-testid="sla-line"]').text()).toContain(
      'RAMON.COMMAND.SLA.BREACHED'
    );
  });

  it('puts the bleeding lead on the hero card with its risk chips', async () => {
    const wrapper = await mountPage();
    const hero = wrapper.find('[data-testid="queue-hero"]');
    expect(hero.text()).toContain('Maria de Lourdes');
    expect(hero.find('[data-testid="queue-hero-chips"]').text()).toContain(
      'RAMON.COMMAND.QUEUE.CHIP_BLEEDING'
    );
    expect(wrapper.findAll('[data-testid="queue-next-item"]')).toHaveLength(1);
  });

  it('skips to the next item with Space', async () => {
    const wrapper = await mountPage();
    const preventDefault = vi.fn();
    keyHandlers.Space.action({ preventDefault });
    await flushPromises();
    expect(preventDefault).toHaveBeenCalled();
    expect(wrapper.find('[data-testid="queue-hero"]').text()).toContain(
      'Sebastião Ramos'
    );
  });

  it('completes the current task with F and refetches the dashboard', async () => {
    const wrapper = await mountPage();
    keyHandlers.KeyF.action();
    await flushPromises();
    expect(dispatchSpy).toHaveBeenCalledWith('leadTasks/complete', {
      leadId: 1,
      taskId: 7,
    });
    expect(dispatchSpy).toHaveBeenCalledWith('ramonDashboard/fetch');
    expect(wrapper.find('[data-testid="queue-hero"]').text()).toContain(
      'Sebastião Ramos'
    );
  });

  it('navigates to the lead on Done when the item has no task', async () => {
    const wrapper = await mountPage();
    keyHandlers.Space.action({ preventDefault: vi.fn() });
    await flushPromises();
    await wrapper.find('[data-testid="queue-done"]').trigger('click');
    expect(routerPush).toHaveBeenCalledWith({
      name: 'ramon_funil',
      params: undefined,
    });
    expect(dispatchSpy).toHaveBeenCalledWith('leads/select', 2);
  });

  it('opens the conversation dock from the hero when there is one', async () => {
    const wrapper = await mountPage();
    keyHandlers.Space.action({ preventDefault: vi.fn() });
    await flushPromises();
    await wrapper
      .find('[data-testid="queue-open-conversation"]')
      .trigger('click');
    expect(dispatchSpy).toHaveBeenCalledWith('leads/toggleDock', 9);
  });

  it('opens the lead from the agenda and the week view from its footer', async () => {
    const wrapper = await mountPage();
    await wrapper.find('[data-testid="agenda-item"]').trigger('click');
    expect(dispatchSpy).toHaveBeenCalledWith('leads/select', 4);
    await wrapper.find('[data-testid="agenda-view-week"]').trigger('click');
    expect(routerPush).toHaveBeenCalledWith({
      name: 'ramon_agenda',
      params: undefined,
    });
  });

  it('opens the funnel filtered by stage from the conversion block', async () => {
    const wrapper = await mountPage();
    await wrapper.find('[data-testid="funnel-stage"]').trigger('click');
    expect(routerPush).toHaveBeenCalledWith({
      name: 'ramon_funil',
      params: undefined,
    });
    expect(dispatchSpy).toHaveBeenCalledWith('leads/setFilters', {
      leadStageId: '1',
    });
    expect(dispatchSpy).toHaveBeenCalledWith('leads/get');
  });

  it('shows losses by thesis for admins only', async () => {
    const wrapper = await mountPage();
    expect(wrapper.find('[data-testid="losses-by-thesis"]').exists()).toBe(
      true
    );
    roleRef.value = 'agent';
    const agentWrapper = await mountPage();
    expect(agentWrapper.find('[data-testid="losses-by-thesis"]').exists()).toBe(
      false
    );
  });

  it('shows the empty queue state when nothing is overdue or stalled', async () => {
    const data = payload();
    data.today.tasks_overdue = { count: 0, items: [] };
    data.today.stalled = { count: 0, items: [] };
    const wrapper = await mountPage(data);
    expect(wrapper.find('[data-testid="queue-empty"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="queue-hero"]').exists()).toBe(false);
  });

  it('shows the error state with retry instead of pretending all is fine', async () => {
    flagsRef.value = { isFetching: false, hasError: true };
    const wrapper = await mountPage(null);
    expect(wrapper.find('[data-testid="command-error"]').exists()).toBe(true);
    dispatchSpy.mockClear();
    await wrapper.find('[data-testid="command-retry"]').trigger('click');
    expect(dispatchSpy).toHaveBeenCalledWith('ramonDashboard/fetch');
  });
});
