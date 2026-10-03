import { mount, flushPromises } from '@vue/test-utils';
import PortalClientesAPI from 'dashboard/api/portalClientes';
import PortalClientes from '../PortalClientes.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));
const mockRoute = { query: {} };
vi.mock('vue-router', () => ({ useRoute: () => mockRoute }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/portalClientes', () => ({
  default: { get: vi.fn(), show: vi.fn() },
}));
vi.mock('dashboard/api/ramonCalculos', () => ({ default: {} }));
vi.mock('dashboard/api/leads', () => ({
  default: { zapsignTemplates: vi.fn().mockResolvedValue({ data: [] }) },
}));

const clientes = [
  { id: 1, nome: 'João Paulo Ramos', processos: [] },
  { id: 2, nome: 'Maria de Lourdes', processos: [] },
];

const montar = async () => {
  const wrapper = mount(PortalClientes, {
    global: { mocks: { $t: k => k }, stubs: { RamonPageHeader: true } },
  });
  await flushPromises();
  return wrapper;
};

describe('PortalClientes — ?q= da paleta Ctrl K', () => {
  beforeEach(() => {
    PortalClientesAPI.get.mockResolvedValue({
      data: { payload: clientes, metricas: null },
    });
    PortalClientesAPI.show.mockResolvedValue({
      data: { id: 1, recados: {}, processos: [], assinaturas: [], envios: [] },
    });
    PortalClientesAPI.show.mockClear();
  });

  it('sem q lista todos', async () => {
    mockRoute.query = {};
    const wrapper = await montar();
    expect(wrapper.text()).toContain('Maria de Lourdes');
    expect(PortalClientesAPI.show).not.toHaveBeenCalled();
  });

  it('com q filtra pelo nome sem acento e abre o único resultado', async () => {
    mockRoute.query = { q: 'joao paulo' };
    const wrapper = await montar();
    expect(wrapper.text()).toContain('João Paulo Ramos');
    expect(wrapper.text()).not.toContain('Maria de Lourdes');
    expect(PortalClientesAPI.show).toHaveBeenCalledWith(1);
    await wrapper.find('[data-testid="portal-filtro-limpar"]').trigger('click');
    expect(wrapper.text()).toContain('Maria de Lourdes');
  });
});
