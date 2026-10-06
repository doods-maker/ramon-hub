import { mount, flushPromises } from '@vue/test-utils';
import RamonFluxosAPI from 'dashboard/api/ramonFluxos';
import Lista from '../Lista.vue';

const push = vi.fn();
vi.mock('vue-router', () => ({ useRouter: () => ({ push }) }));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    accountScopedRoute: (name, params) => ({ name, params }),
  }),
}));
vi.mock('dashboard/api/ramonFluxos', () => ({
  default: { get: vi.fn(), update: vi.fn(), create: vi.fn() },
}));

const FLUXO = {
  id: 1,
  nome: 'Pós-contrato',
  gatilho_tipo: 'lead_mudou_etapa',
  ativo: true,
  limite_dia: 20,
  origem: 'usuario',
  versao: 3,
  editado_em: '2026-10-04T12:00:00Z',
  hoje: 3,
  esperando: 8,
  falharam_24h: 0,
  ultima_em: null,
};

describe('Lista de automações', () => {
  beforeEach(() => {
    RamonFluxosAPI.get.mockResolvedValue({
      data: {
        payload: [
          FLUXO,
          {
            ...FLUXO,
            id: 2,
            nome: 'Rascunho',
            ativo: false,
            versao: null,
            gatilho_tipo: null,
            falharam_24h: 1,
          },
          { ...FLUXO, id: 3, origem: 'sistema' },
        ],
        resumo: {
          ligados: 1,
          total: 3,
          hoje: 3,
          esperando: 8,
          falharam_24h: 1,
        },
      },
    });
    RamonFluxosAPI.update.mockResolvedValue({ data: {} });
  });

  it('mostra os 4 números e só "Meus fluxos" (sem os do sistema)', async () => {
    const wrapper = mount(Lista);
    await flushPromises();
    expect(wrapper.findAll('[data-testid="fluxo-linha"]')).toHaveLength(2);
    expect(wrapper.find('[data-testid="fluxos-resumo"]').text()).toContain('1');
    expect(wrapper.text()).toContain('3 / 20');
    expect(wrapper.text()).toContain('1 failed');
  });

  it('clicar na linha abre o editor', async () => {
    const wrapper = mount(Lista);
    await flushPromises();
    await wrapper.find('[data-testid="fluxo-linha"]').trigger('click');
    expect(push).toHaveBeenCalledWith({
      name: 'captain_automacoes_editor',
      params: { fluxoId: 1 },
    });
  });

  it('a chave liga/desliga sem abrir o editor', async () => {
    const wrapper = mount(Lista);
    await flushPromises();
    await wrapper
      .find('[data-testid="fluxo-linha"] [role="switch"]')
      .trigger('click');
    expect(RamonFluxosAPI.update).toHaveBeenCalledWith(1, { ativo: false });
    expect(push).not.toHaveBeenCalled();
  });
});
