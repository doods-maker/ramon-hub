import { mount, flushPromises } from '@vue/test-utils';
import RamonEsteiraAPI from 'dashboard/api/ramonEsteira';
import Esteira from '../Esteira.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));

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
  RamonEsteiraAPI.get.mockResolvedValue({ data });
  const wrapper = mount(Esteira, { global: { mocks: { $t: k => k } } });
  await flushPromises();
  return wrapper;
};

describe('Esteira.vue', () => {
  beforeEach(() => {
    vi.clearAllMocks();
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
});
