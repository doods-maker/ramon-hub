import { mount, flushPromises } from '@vue/test-utils';
import RamonWatchdogAPI from 'dashboard/api/ramonWatchdog';
import VigiaBloco from '../VigiaBloco.vue';

vi.mock('dashboard/api/ramonWatchdog', () => ({ default: { get: vi.fn() } }));
const { push } = vi.hoisted(() => ({ push: vi.fn() }));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: vi.fn() }),
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ accountScopedRoute: n => n }),
}));
vi.mock('vue-router', () => ({ useRouter: () => ({ push }) }));

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

const montarCom = async items => {
  RamonWatchdogAPI.get.mockResolvedValue({
    data: { thresholds: { ...BASE, teto_diario: 15 }, counters: {}, items },
  });
  const wrapper = mount(VigiaBloco);
  await flushPromises();
  return wrapper;
};
const ITEM = {
  lead_id: 12,
  name: 'Maria',
  stage_name: 'Qualificação',
  dias_parado: 6,
  tentativas: 1,
  conversa_display_id: 482,
};

describe('Vigia: conversa e gravidade (I-WD3, I-WD4)', () => {
  it('abre a conversa pelo nº', async () => {
    const wrapper = await montarCom([ITEM]);
    await wrapper.find('[data-testid="watchdog-conversa"]').trigger('click');
    expect(push).toHaveBeenCalledWith('inbox_conversation');
  });

  it('âmbar até 2 retomadas; vermelho no limite da régua (3+)', async () => {
    const wrapper = await montarCom([
      ITEM,
      { ...ITEM, lead_id: 13, tentativas: 3 },
    ]);
    const chips = wrapper.findAll('[data-testid="watchdog-tentativas"]');
    expect(chips[0].classes()).toContain('text-n-amber-11');
    expect(chips[1].classes()).toContain('text-n-ruby-11');
  });

  it('sem conversa, sem botão', async () => {
    const wrapper = await montarCom([{ ...ITEM, conversa_display_id: null }]);
    expect(wrapper.find('[data-testid="watchdog-conversa"]').exists()).toBe(
      false
    );
  });
});
