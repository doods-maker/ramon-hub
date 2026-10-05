import { mount, flushPromises } from '@vue/test-utils';
import { ref } from 'vue';
import RamonEsteiraAPI from 'dashboard/api/ramonEsteira';
import RamonCopilotAPI from 'dashboard/api/ramonCopilot';
import { EMPTY_FILTERS } from 'dashboard/store/modules/leads';
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

vi.mock('dashboard/api/ramonEsteira', () => ({
  default: { get: vi.fn(), done: vi.fn() },
}));

vi.mock('dashboard/api/ramonCopilot', () => ({
  default: { generate: vi.fn() },
}));

// A fila do Centro é a fila da Esteira: mesma ordem, mesmos itens.
const esteira = () => ({
  items: [
    {
      lead_id: 1,
      name: 'Maria de Lourdes',
      stage_name: 'Novo',
      value: 16900,
      conversation_id: null,
      task_id: 7,
      reasons: [
        { key: 'PRESCRIPTION_BLEEDING', params: { monthly: 1412 } },
        { key: 'TASK_OVERDUE', params: { title: 'Ligar após perícia' } },
      ],
    },
    {
      lead_id: 2,
      name: 'Sebastião Ramos',
      stage_name: 'Qualificado',
      value: null,
      conversation_id: 9,
      task_id: null,
      reasons: [{ key: 'STALLED', params: { days: 14 } }],
    },
  ],
  board: { total: 2, value_sum: 16900, done_today: 5 },
});

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
  week: { won: 5, won_since: '2026-07-20', nps: { media: 9.4, respostas: 3 } },
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

// NightCopilot tem store/specs próprios — aqui entra como stub.
const mountPage = async (data = payload(), queue = esteira()) => {
  dataRef.value = data;
  RamonEsteiraAPI.get.mockResolvedValue({ data: queue });
  const wrapper = mount(CommandCenter, {
    global: { mocks: { $t: k => k }, stubs: { NightCopilot: true } },
  });
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

  it('shows the Esteira queue: hero = 1st item, list = the next ones', async () => {
    const wrapper = await mountPage();
    expect(RamonEsteiraAPI.get).toHaveBeenCalled();
    const hero = wrapper.find('[data-testid="queue-hero"]');
    expect(hero.text()).toContain('Maria de Lourdes');
    expect(hero.find('[data-testid="queue-hero-chips"]').text()).toContain(
      'RAMON.ESTEIRA.REASON.PRESCRIPTION_BLEEDING'
    );
    expect(hero.find('[data-testid="queue-hero-value"]').text()).toContain(
      '16.900'
    );
    const next = wrapper.findAll('[data-testid="queue-next-item"]');
    expect(next).toHaveLength(1);
    expect(next[0].text()).toContain('RAMON.ESTEIRA.REASON.STALLED');
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

  it('marks done with F through the Esteira and refetches the goal', async () => {
    RamonEsteiraAPI.done.mockResolvedValue({});
    const wrapper = await mountPage();
    keyHandlers.KeyF.action();
    await flushPromises();
    expect(RamonEsteiraAPI.done).toHaveBeenCalledWith(1);
    expect(dispatchSpy).not.toHaveBeenCalledWith(
      'leadTasks/complete',
      expect.anything()
    );
    expect(dispatchSpy).toHaveBeenCalledWith('ramonDashboard/fetch');
    expect(wrapper.find('[data-testid="queue-hero"]').text()).toContain(
      'Sebastião Ramos'
    );
  });

  it('keeps the item and warns when Done fails', async () => {
    RamonEsteiraAPI.done.mockRejectedValue(new Error('boom'));
    const wrapper = await mountPage();
    await wrapper.find('[data-testid="queue-done"]').trigger('click');
    await flushPromises();
    expect(alertSpy).toHaveBeenCalledWith('RAMON.ESTEIRA.ACTION_ERROR');
    expect(wrapper.find('[data-testid="queue-hero"]').text()).toContain(
      'Maria de Lourdes'
    );
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

  it('opens the lead panel when the item has no conversation', async () => {
    const wrapper = await mountPage();
    await wrapper
      .find('[data-testid="queue-open-conversation"]')
      .trigger('click');
    expect(dispatchSpy).toHaveBeenCalledWith('leads/select', 1);
  });

  it('hides the AI draft when the item has no conversation', async () => {
    const wrapper = await mountPage();
    expect(wrapper.find('[data-testid="queue-ai-draft"]').exists()).toBe(false);
  });

  it('AI draft fills the reply draft BEFORE opening the dock', async () => {
    RamonCopilotAPI.generate.mockResolvedValue({
      data: { content: 'Oi, Sebastião!' },
    });
    const wrapper = await mountPage();
    keyHandlers.Space.action({ preventDefault: vi.fn() });
    await flushPromises();
    await wrapper.find('[data-testid="queue-ai-draft"]').trigger('click');
    await flushPromises();
    expect(RamonCopilotAPI.generate).toHaveBeenCalledWith(9, 'draft');
    const calls = dispatchSpy.mock.calls.map(([action]) => action);
    expect(dispatchSpy).toHaveBeenCalledWith('draftMessages/set', {
      key: 'draft-9-REPLY',
      message: 'Oi, Sebastião!',
    });
    expect(calls.indexOf('draftMessages/set')).toBeLessThan(
      calls.indexOf('leads/toggleDock')
    );
    expect(dispatchSpy).toHaveBeenCalledWith('leads/toggleDock', 9);
  });

  it('AI draft failure warns and does not open the conversation', async () => {
    RamonCopilotAPI.generate.mockRejectedValue(new Error('sem chave'));
    const wrapper = await mountPage();
    keyHandlers.Space.action({ preventDefault: vi.fn() });
    await flushPromises();
    await wrapper.find('[data-testid="queue-ai-draft"]').trigger('click');
    await flushPromises();
    expect(alertSpy).toHaveBeenCalledWith('RAMON.COMMAND.QUEUE.AI_DRAFT_ERROR');
    expect(dispatchSpy).not.toHaveBeenCalledWith(
      'draftMessages/set',
      expect.anything()
    );
    expect(dispatchSpy).not.toHaveBeenCalledWith('leads/toggleDock', 9);
  });

  it('KPI click opens the Funil with ONLY that filter on', async () => {
    const wrapper = await mountPage();
    const cases = [
      ['overdue', { overdueTask: true }],
      ['today', { taskDueToday: true }],
      ['stalled', { stalled: true }],
      ['new_from_lp', { newFromLp: true }],
      ['won_week', { wonSince: '2026-07-20' }],
    ];
    await Promise.all(
      cases.map(([key]) =>
        wrapper.find(`[data-testid="kpi-${key}"]`).trigger('click')
      )
    );
    cases.forEach(([, filter]) => {
      expect(dispatchSpy).toHaveBeenCalledWith('leads/setFilters', {
        ...EMPTY_FILTERS,
        ...filter,
      });
    });
    expect(routerPush).toHaveBeenCalledWith({
      name: 'ramon_funil',
      params: undefined,
    });
    // os demais filtros persistidos vão zerados, não herdados
    const [, sent] = dispatchSpy.mock.calls.find(
      ([action]) => action === 'leads/setFilters'
    );
    expect(sent).toMatchObject({ agentId: null, q: '', leadStageId: null });
  });

  it('forecast KPI is not clickable', async () => {
    const wrapper = await mountPage();
    const forecast = wrapper.find('[data-testid="kpi-forecast"]');
    expect(forecast.element.tagName).toBe('DIV');
    await forecast.trigger('click');
    expect(dispatchSpy).not.toHaveBeenCalledWith(
      'leads/setFilters',
      expect.anything()
    );
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

  it('shows the empty queue state when the Esteira is empty', async () => {
    const wrapper = await mountPage(payload(), { items: [], board: {} });
    expect(wrapper.find('[data-testid="queue-empty"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="queue-hero"]').exists()).toBe(false);
  });

  it('shows a queue error (not an empty queue) when the Esteira fails', async () => {
    dataRef.value = payload();
    RamonEsteiraAPI.get.mockRejectedValue(new Error('boom'));
    const wrapper = mount(CommandCenter, {
      global: { mocks: { $t: k => k }, stubs: { NightCopilot: true } },
    });
    await flushPromises();
    expect(wrapper.find('[data-testid="queue-error"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="queue-empty"]').exists()).toBe(false);
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
