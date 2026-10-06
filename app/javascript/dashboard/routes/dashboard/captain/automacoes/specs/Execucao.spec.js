import { mount, flushPromises } from '@vue/test-utils';
import RamonFluxosAPI from 'dashboard/api/ramonFluxos';
import Execucao from '../Execucao.vue';

const push = vi.fn();
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { fluxoId: '1', execId: '412' } }),
  useRouter: () => ({ push }),
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    accountScopedRoute: (name, params) => ({ name, params }),
  }),
}));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: vi.fn() }),
}));
vi.mock('dashboard/api/ramonFluxos', () => ({
  default: { show: vi.fn(), execucao: vi.fn() },
}));

const GRAFO = {
  nos: [
    {
      id: 'n1',
      tipo: 'gatilho',
      config: { tipo: 'manual' },
      posicao: { x: 0, y: 0 },
    },
    {
      id: 'n2',
      tipo: 'nota_privada',
      config: { texto: 'oi', rotulo: 'Aviso' },
      posicao: { x: 0, y: 140 },
    },
  ],
  setas: [{ de: 'n1', saida: 's', para: 'n2' }],
};

describe('Execução de fluxo', () => {
  beforeEach(() => {
    RamonFluxosAPI.show.mockResolvedValue({
      data: { id: 1, nome: 'Pós-contrato' },
    });
    RamonFluxosAPI.execucao.mockResolvedValue({
      data: {
        id: 412,
        versao: 3,
        status: 'concluida',
        ensaio: true,
        alvo_type: 'Lead',
        alvo_id: 231,
        alvo_nome: 'Maria da Silva',
        lead_id: 231,
        conversation_display_id: 1802,
        created_at: '2026-10-02T17:31:00Z',
        updated_at: '2026-10-04T17:32:00Z',
        trilha: [
          {
            no: 'n1',
            tipo: 'gatilho',
            em: '2026-10-02T17:31:00Z',
            saida: 's',
            resumo: 'manual',
            erro: false,
          },
          {
            no: 'n2',
            tipo: 'nota_privada',
            em: '2026-10-02T17:31:02Z',
            saida: 's',
            resumo: 'faria: nota "oi"',
            erro: false,
          },
        ],
        grafo: GRAFO,
      },
    });
  });

  it('mostra alvo, a trilha com o nome do passo e o resumo', async () => {
    const wrapper = mount(Execucao, { global: { stubs: { Quadro: true } } });
    await flushPromises();
    expect(wrapper.text()).toContain('Maria da Silva');
    expect(wrapper.findAll('[data-testid="trilha-item"]')).toHaveLength(2);
    expect(wrapper.text()).toContain('Aviso');
    expect(wrapper.text()).toContain('faria: nota "oi"');
    expect(wrapper.text()).toContain('dry run');
  });

  it('"Voltar a editar" abre o editor do fluxo', async () => {
    const wrapper = mount(Execucao, { global: { stubs: { Quadro: true } } });
    await flushPromises();
    await wrapper.find('[data-testid="voltar-editar"]').trigger('click');
    expect(push).toHaveBeenCalledWith({
      name: 'captain_automacoes_editor',
      params: { fluxoId: 1 },
    });
  });

  it('esperando mostra "Esperando até" e falhou mostra o erro', async () => {
    const base = (await RamonFluxosAPI.execucao()).data;
    RamonFluxosAPI.execucao.mockResolvedValue({
      data: {
        ...base,
        status: 'esperando',
        no_atual: 'n2',
        retomar_em: '2026-10-06T12:00:00Z',
      },
    });
    let wrapper = mount(Execucao, { global: { stubs: { Quadro: true } } });
    await flushPromises();
    expect(wrapper.text()).toContain('Waiting until');
    RamonFluxosAPI.execucao.mockResolvedValue({
      data: { ...base, status: 'falhou', erro: 'boom' },
    });
    wrapper = mount(Execucao, { global: { stubs: { Quadro: true } } });
    await flushPromises();
    expect(wrapper.text()).toContain('Error: boom');
  });
});
