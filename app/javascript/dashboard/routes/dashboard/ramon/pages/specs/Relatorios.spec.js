import { mount, flushPromises } from '@vue/test-utils';
import Relatorios from '../Relatorios.vue';
import RamonRelatoriosAPI from 'dashboard/api/ramonRelatorios';

const t = key => key;
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t }) }));

vi.mock('vue-router', () => ({ useRouter: () => ({ push: vi.fn() }) }));

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: vi.fn() }),
}));

vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    accountScopedRoute: (name, params) => ({ name, params }),
  }),
}));

vi.mock('dashboard/api/ramonRelatorios', () => ({ default: { get: vi.fn() } }));

const mountPage = () =>
  mount(Relatorios, {
    global: { mocks: { $t: t } },
  });

describe('Relatorios', () => {
  it('mostra aviso quando nao configurado', async () => {
    RamonRelatoriosAPI.get.mockResolvedValue({ data: { configured: false } });
    const wrapper = mountPage();
    await flushPromises();
    expect(wrapper.text()).toContain('RAMON.RELATORIOS.NOT_CONFIGURED');
    expect(wrapper.find('iframe').exists()).toBe(false);
  });

  it('renderiza o iframe quando configurado', async () => {
    RamonRelatoriosAPI.get.mockResolvedValue({
      data: {
        configured: true,
        url: 'https://bi.test/embed/dashboard/tok#theme=night',
      },
    });
    const wrapper = mountPage();
    await flushPromises();
    expect(wrapper.find('iframe').attributes('src')).toBe(
      'https://bi.test/embed/dashboard/tok#theme=night'
    );
  });

  it('mostra erro com retry quando a API falha', async () => {
    RamonRelatoriosAPI.get.mockRejectedValue(new Error('boom'));
    const wrapper = mountPage();
    await flushPromises();
    expect(wrapper.text()).toContain('RAMON.RELATORIOS.LOAD_ERROR');
  });
});
