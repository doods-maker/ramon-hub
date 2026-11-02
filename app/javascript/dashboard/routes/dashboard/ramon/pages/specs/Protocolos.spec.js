import { mount, flushPromises } from '@vue/test-utils';
import { ref } from 'vue';
import RamonPeticoesAPI from 'dashboard/api/ramonPeticoes';
import Protocolos from '../Protocolos.vue';

const rota = { params: {}, query: {} };
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));
vi.mock('vue-router', () => ({
  useRoute: () => rota,
  useRouter: () => ({ push: vi.fn() }),
}));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ref(1),
}));
vi.mock('dashboard/composables/useAdmin', () => ({
  useAdmin: () => ({ isAdmin: ref(true) }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/components-next/button/ConfirmButton.vue', () => ({
  default: { render: () => null },
}));
vi.mock('dashboard/api/ramonPeticoes', () => ({
  default: {
    get: vi.fn(),
    show: vi.fn(),
    relerPasta: vi.fn(),
    pastasProntas: vi.fn(),
  },
}));

const base = {
  id: 7,
  status: 'rascunho',
  pela_pasta: true,
  inicial: false,
  numero_processo: '5001234',
  contato: null,
  responsavel: { id: 1, name: 'Ana' },
  arquivos: [],
  problemas: [],
};

const montar = async () => {
  const w = mount(Protocolos, {
    global: {
      stubs: {
        RamonPageHeader: true,
        PeticaoForm: true,
        PacoteEditor: true,
        ConferenciaPasta: { template: '<div data-testid="conferencia" />' },
        SeletorDrive: true,
        RegistrarProtocolo: true,
      },
    },
  });
  await flushPromises();
  return w;
};

const lista = payload =>
  RamonPeticoesAPI.get.mockResolvedValue({
    data: { payload, tribunais: [], tipos: [] },
  });

describe('Protocolos.vue', () => {
  beforeEach(() => {
    rota.params = { peticaoId: 7 };
    lista([]);
  });

  it('rascunho da pasta: Reler chama a API e a petição volta à conferência', async () => {
    RamonPeticoesAPI.show.mockResolvedValue({ data: base });
    RamonPeticoesAPI.relerPasta.mockResolvedValue({
      data: { ...base, status: 'conferencia', leitura: { estado: 'lendo' } },
    });
    const w = await montar();
    await w.find('[data-testid="protocolo-reler"]').trigger('click');
    await flushPromises();
    expect(RamonPeticoesAPI.relerPasta).toHaveBeenCalledWith(7);
    expect(w.find('[data-testid="conferencia"]').exists()).toBe(true);
    expect(w.find('[data-testid="protocolo-reler"]').exists()).toBe(false);
  });

  it('rascunho manual não oferece Reler', async () => {
    RamonPeticoesAPI.show.mockResolvedValue({
      data: { ...base, pela_pasta: false },
    });
    const w = await montar();
    expect(w.find('[data-testid="protocolo-reler"]').exists()).toBe(false);
  });

  it('sem número: INICIAL só se for inicial; senão, traço', async () => {
    rota.params = {};
    lista([
      { ...base, id: 1, numero_processo: null, inicial: true },
      { ...base, id: 2, numero_processo: null },
    ]);
    const w = await montar();
    const linhas = w.findAll('[data-testid="protocolos-linha"]');
    expect(linhas[0].find('td').text()).toBe('RAMON.PETICOES.INICIAL');
    expect(linhas[1].find('td').text()).toBe('—');
  });
});
