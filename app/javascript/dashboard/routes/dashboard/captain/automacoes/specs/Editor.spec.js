import { mount, flushPromises } from '@vue/test-utils';
import RamonFluxosAPI from 'dashboard/api/ramonFluxos';
import Editor from '../Editor.vue';

vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { fluxoId: '5' } }),
  useRouter: () => ({ push: vi.fn() }),
  onBeforeRouteLeave: vi.fn(),
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    accountScopedRoute: (name, params, query) => ({ name, params, query }),
  }),
}));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: vi.fn() }),
  useMapGetter: () => ({ value: [{ id: 1 }] }),
}));
vi.mock('dashboard/api/ramonFluxos', () => ({
  default: { show: vi.fn(), execucoes: vi.fn(), update: vi.fn() },
}));

const SISTEMA = {
  id: 5,
  nome: 'Cadência de retomada',
  origem: 'sistema',
  sistema_chave: 'cadencia',
  descricao: 'No código: Ramon::DailyFollowUpJob (todo dia às 11:00)',
  alcance: 'fala_com_cliente',
  grupo: 'leads_conversas',
  ativo: false,
  versao: null,
  versoes: [],
  rascunho: {
    nos: [
      {
        id: 'n1',
        tipo: 'gatilho',
        config: { tipo: 'manual' },
        posicao: { x: 0, y: 0 },
      },
    ],
    setas: [],
  },
};

describe('Editor — desenho do sistema', () => {
  it('mostra Como roda hoje, o selo e volta para a aba do sistema', async () => {
    RamonFluxosAPI.show.mockResolvedValue({ data: SISTEMA });
    RamonFluxosAPI.execucoes.mockResolvedValue({ data: { payload: [] } });
    const wrapper = mount(Editor, {
      global: {
        stubs: {
          Quadro: true,
          RouterLink: {
            name: 'RouterLink',
            template: '<a><slot /></a>',
            props: ['to'],
          },
        },
      },
    });
    await flushPromises();

    const descricao = wrapper.get('[data-testid="sistema-descricao"]');
    expect(descricao.text()).toContain('How it runs today');
    expect(descricao.text()).toContain('Ramon::DailyFollowUpJob');
    expect(wrapper.get('[data-testid="sistema-alcance"]').text()).toContain(
      'talks to the client'
    );
    expect(wrapper.text()).not.toContain('Versions');
    expect(wrapper.text()).not.toContain('Test with a lead');
    expect(wrapper.findComponent({ name: 'RouterLink' }).props('to')).toEqual({
      name: 'captain_automacoes_index',
      params: {},
      query: { aba: 'sistema' },
    });
    expect(RamonFluxosAPI.update).not.toHaveBeenCalled();
  });
});
