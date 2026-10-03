import { mount, flushPromises } from '@vue/test-utils';
import RamonEsteiraAPI from 'dashboard/api/ramonEsteira';
import Esteira from '../Esteira.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));

const routerPush = vi.fn();
vi.mock('vue-router', () => ({ useRouter: () => ({ push: routerPush }) }));

const dispatchSpy = vi.fn();
const thesesRef = { value: [] };
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: dispatchSpy }),
  useMapGetter: () => thesesRef,
}));

// Captura o mapa de atalhos pra disparar as ações direto nos testes.
let keyHandlers = {};
vi.mock('dashboard/composables/useKeyboardEvents', () => ({
  useKeyboardEvents: events => {
    keyHandlers = events;
  },
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

vi.mock('dashboard/api/ramonEsteira', () => ({
  default: { get: vi.fn(), done: vi.fn(), snooze: vi.fn() },
}));

const payload = {
  items: [
    {
      lead_id: 1,
      name: 'Maria',
      stage_name: 'Novo',
      value: 5000,
      conversation_id: 9,
      contact_id: 4,
      task_id: null,
      score: 100,
      suggested_action: 'contact',
      reasons: [{ key: 'PRESCRIPTION_BLEEDING', params: { monthly: 1350 } }],
    },
    {
      lead_id: 2,
      name: 'João',
      stage_name: 'Contato',
      value: 1000,
      conversation_id: null,
      contact_id: null,
      task_id: 7,
      score: 80,
      suggested_action: 'task',
      reasons: [{ key: 'TASK_OVERDUE', params: { title: 'Ligar' } }],
    },
  ],
  board: { total: 2, value_sum: 6000, done_today: 3 },
};

const mountEsteira = async (data = payload) => {
  // O componente muta a fila (shift/push) — clona pra não vazar entre testes.
  RamonEsteiraAPI.get.mockResolvedValue({ data: structuredClone(data) });
  const wrapper = mount(Esteira, { global: { mocks: { $t: k => k } } });
  await flushPromises();
  return wrapper;
};

// Item enriquecido do Modo Foco: tese, última mensagem e última simulação.
const enrichedPayload = () => ({
  ...payload,
  items: [
    {
      ...payload.items[0],
      thesis_id: 5,
      last_message: {
        content: 'Doutor, remarcaram minha perícia de novo…',
        at: 1752900000,
        incoming: true,
      },
      ultima_simulacao: {
        mensal: '1412.00',
        atrasados: '46900.00',
        honorario_valor: '14070.00',
        tese: 'Restabelecimento B31',
        em: '2026-07-20T10:00:00Z',
        parametros: { der: '2023-03-01' },
      },
    },
    payload.items[1],
  ],
});

describe('Esteira.vue', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    thesesRef.value = [];
    keyHandlers = {};
  });

  it('renders the current item and the upcoming list', async () => {
    const wrapper = await mountEsteira();
    expect(wrapper.find('[data-testid="esteira-current"]').text()).toContain(
      'Maria'
    );
    expect(wrapper.findAll('[data-testid="esteira-next-item"]')).toHaveLength(
      1
    );
  });

  it('marks the current item as done and removes it from the queue', async () => {
    RamonEsteiraAPI.done.mockResolvedValue({});
    const wrapper = await mountEsteira();
    await wrapper.find('[data-testid="esteira-done"]').trigger('click');
    await flushPromises();
    expect(RamonEsteiraAPI.done).toHaveBeenCalledWith(1);
    expect(wrapper.find('[data-testid="esteira-current"]').text()).toContain(
      'João'
    );
  });

  it('snoozes the current item passing its task_id', async () => {
    RamonEsteiraAPI.snooze.mockResolvedValue({});
    const wrapper = await mountEsteira({
      ...payload,
      items: [payload.items[1]],
    });
    await wrapper.find('[data-testid="esteira-snooze"]').trigger('click');
    await flushPromises();
    expect(RamonEsteiraAPI.snooze).toHaveBeenCalledWith(2, 7);
    expect(wrapper.find('[data-testid="esteira-empty"]').exists()).toBe(true);
  });

  it('skip rotates the queue', async () => {
    const wrapper = await mountEsteira();
    await wrapper.find('[data-testid="esteira-skip"]').trigger('click');
    expect(wrapper.find('[data-testid="esteira-current"]').text()).toContain(
      'João'
    );
  });

  it('opens the conversation dock for the current item', async () => {
    const wrapper = await mountEsteira();
    await wrapper
      .find('[data-testid="esteira-open-conversation"]')
      .trigger('click');
    expect(routerPush).toHaveBeenCalledWith({
      name: 'ramon_funil',
      params: undefined,
    });
    expect(dispatchSpy).toHaveBeenCalledWith('leads/toggleDock', 9);
  });

  it('shows the empty state when the queue is clear', async () => {
    const wrapper = await mountEsteira({
      items: [],
      board: { total: 0, value_sum: 0, done_today: 0 },
    });
    expect(wrapper.find('[data-testid="esteira-empty"]').exists()).toBe(true);
  });

  it('renders progress, last message and last simulation of the current item', async () => {
    const wrapper = await mountEsteira(enrichedPayload());
    expect(wrapper.find('[data-testid="esteira-progress"]').text()).toContain(
      'RAMON.ESTEIRA.PROGRESS'
    );
    expect(
      wrapper.find('[data-testid="esteira-last-message"]').text()
    ).toContain('remarcaram minha perícia');
    expect(
      wrapper.find('[data-testid="esteira-last-simulation"]').text()
    ).toContain('46.900');
    expect(wrapper.find('[data-testid="esteira-sim-params"]').text()).toContain(
      'RAMON.ESTEIRA.LAST_SIMULATION_RMI'
    );
  });

  it('hides last message and shows the simulation hint when the lead has neither', async () => {
    const wrapper = await mountEsteira();
    expect(wrapper.find('[data-testid="esteira-last-message"]').exists()).toBe(
      false
    );
    expect(wrapper.find('[data-testid="esteira-sim-empty"]').exists()).toBe(
      true
    );
  });

  it('renders the playbook script from the cached thesis without refetching', async () => {
    thesesRef.value = [
      {
        id: 5,
        name: 'Restabelecimento B31',
        items: [{ id: 1, section: 'abertura', content: 'Dona Maria, vi que…' }],
      },
    ];
    const wrapper = await mountEsteira(enrichedPayload());
    expect(wrapper.find('[data-testid="esteira-script"]').text()).toContain(
      'Dona Maria, vi que…'
    );
    expect(dispatchSpy).not.toHaveBeenCalledWith('theses/show', 5);
  });

  it('fetches the thesis items when they are not cached yet', async () => {
    await mountEsteira(enrichedPayload());
    expect(dispatchSpy).toHaveBeenCalledWith('theses/show', 5);
  });

  it('hides the script block when the lead has no thesis', async () => {
    const wrapper = await mountEsteira();
    expect(wrapper.find('[data-testid="esteira-script"]').exists()).toBe(false);
  });

  it('marks done with the F shortcut', async () => {
    RamonEsteiraAPI.done.mockResolvedValue({});
    const wrapper = await mountEsteira();
    keyHandlers.KeyF.action();
    await flushPromises();
    expect(RamonEsteiraAPI.done).toHaveBeenCalledWith(1);
    expect(wrapper.find('[data-testid="esteira-current"]').text()).toContain(
      'João'
    );
  });

  it('skips with Space and opens the conversation with C', async () => {
    const wrapper = await mountEsteira();
    const preventDefault = vi.fn();
    keyHandlers.Space.action({ preventDefault });
    await flushPromises();
    expect(preventDefault).toHaveBeenCalled();
    expect(wrapper.find('[data-testid="esteira-current"]').text()).toContain(
      'João'
    );
    keyHandlers.KeyC.action();
    expect(routerPush).toHaveBeenCalledWith({
      name: 'ramon_funil',
      params: undefined,
    });
  });

  it('exits focus mode with Escape and with the exit button', async () => {
    const wrapper = await mountEsteira();
    keyHandlers.Escape.action();
    expect(routerPush).toHaveBeenCalledWith({
      name: 'ramon_index',
      params: undefined,
    });
    routerPush.mockClear();
    await wrapper.find('[data-testid="esteira-exit"]').trigger('click');
    expect(routerPush).toHaveBeenCalledWith({
      name: 'ramon_index',
      params: undefined,
    });
  });
});
