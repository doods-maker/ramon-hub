import { mount, flushPromises } from '@vue/test-utils';
import RamonWatchdogAPI from 'dashboard/api/ramonWatchdog';
import VigiaBloco from '../VigiaBloco.vue';

vi.mock('dashboard/api/ramonWatchdog', () => ({ default: { get: vi.fn() } }));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: vi.fn() }),
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ accountScopedRoute: n => n }),
}));
vi.mock('vue-router', () => ({ useRouter: () => ({ push: vi.fn() }) }));

const montar = async thresholds => {
  RamonWatchdogAPI.get.mockResolvedValue({
    data: { thresholds, counters: {}, items: [] },
  });
  const wrapper = mount(VigiaBloco);
  await flushPromises();
  return wrapper;
};

const BASE = {
  intervalo_minimo_dias: 5,
  horario_retomada: '11:00',
  horario_copiloto: '05:00',
};

describe('Vigia: régua', () => {
  it('com teto, mostra o teto diário', async () => {
    const wrapper = await montar({ ...BASE, teto_diario: 15 });
    expect(wrapper.text()).toContain('up to 15 follow-ups a day');
  });

  it('sem teto (limite do dia apagado), frase própria e sem número vazio', async () => {
    const wrapper = await montar({ ...BASE, teto_diario: null });
    expect(wrapper.text()).toContain('no daily cap on follow-ups');
    expect(wrapper.text()).not.toContain('up to');
  });
});
