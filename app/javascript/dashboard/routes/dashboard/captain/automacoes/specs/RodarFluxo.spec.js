import { mount, flushPromises, RouterLinkStub } from '@vue/test-utils';
import RamonFluxosAPI from 'dashboard/api/ramonFluxos';
import { useAlert } from 'dashboard/composables';
import RodarFluxo from '../RodarFluxo.vue';
import en from 'dashboard/i18n/locale/en/ramon.json';

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    accountScopedRoute: (name, params) => ({ name, params }),
  }),
}));
vi.mock('dashboard/api/ramonFluxos', () => ({
  default: { get: vi.fn(), rodar: vi.fn() },
}));

const MANUAL = {
  id: 7,
  nome: 'Pedir documentos',
  gatilho_tipo: 'manual',
  ativo: true,
  versao: 2,
  origem: 'usuario',
};
const montar = (alvo = { lead_id: 31 }) =>
  mount(RodarFluxo, {
    props: { alvo },
    global: { stubs: { teleport: true, RouterLink: RouterLinkStub } },
  });

describe('Rodar fluxo…', () => {
  beforeEach(() => {
    RamonFluxosAPI.get.mockResolvedValue({
      data: {
        payload: [
          MANUAL,
          { ...MANUAL, id: 8, nome: 'Desligado', ativo: false },
          { ...MANUAL, id: 9, nome: 'Nunca publicado', versao: null },
          {
            ...MANUAL,
            id: 10,
            nome: 'Outro gatilho',
            gatilho_tipo: 'lead_ganho',
          },
          { ...MANUAL, id: 11, nome: 'Do sistema', origem: 'sistema' },
        ],
      },
    });
  });

  it('lista só os manuais publicados e ligados; rodar avisa com link para a execução', async () => {
    RamonFluxosAPI.rodar.mockResolvedValue({ data: { id: 412 } });
    const wrapper = montar({ conversation_id: 1802 });
    await flushPromises();
    const itens = wrapper.findAll('[data-testid="rodar-fluxo-item"]');
    expect(itens.map(i => i.text())).toEqual(['Pedir documentos']);
    await itens[0].trigger('click');
    await flushPromises();
    expect(RamonFluxosAPI.rodar).toHaveBeenCalledWith(7, {
      conversation_id: 1802,
    });
    expect(useAlert).toHaveBeenCalledWith(expect.any(String), {
      type: 'link',
      to: {
        name: 'captain_automacoes_execucao',
        params: { fluxoId: 7, execId: 412 },
      },
      message: expect.any(String),
    });
    expect(wrapper.emitted('fechar')).toHaveLength(1);
  });

  it('sem fluxo manual: estado vazio com link para Automações', async () => {
    RamonFluxosAPI.get.mockResolvedValue({ data: { payload: [] } });
    const wrapper = montar();
    await flushPromises();
    expect(wrapper.find('[data-testid="rodar-vazio"]').exists()).toBe(true);
    expect(wrapper.findComponent(RouterLinkStub).props('to')).toEqual({
      name: 'captain_automacoes_index',
      params: undefined,
    });
  });

  it('fluxo que não rodou (limite, já rodando…) explica e não fecha', async () => {
    RamonFluxosAPI.rodar.mockRejectedValue({
      response: { data: { erro: 'FLUXO_NAO_RODOU' } },
    });
    const wrapper = montar();
    await flushPromises();
    await wrapper.find('[data-testid="rodar-fluxo-item"]').trigger('click');
    await flushPromises();
    expect(wrapper.get('[data-testid="rodar-erro"]').text()).toBe(
      en.CAPTAIN_RAMON.FLUXOS.RODAR.NAO_RODOU
    );
    expect(wrapper.emitted('fechar')).toBeUndefined();
    expect(useAlert).not.toHaveBeenCalled();
  });

  it('erro genérico (403) mostra ERRO e não fecha', async () => {
    RamonFluxosAPI.rodar.mockRejectedValue({
      response: { status: 403, data: {} },
    });
    const wrapper = montar();
    await flushPromises();
    await wrapper.find('[data-testid="rodar-fluxo-item"]').trigger('click');
    await flushPromises();
    expect(wrapper.get('[data-testid="rodar-erro"]').text()).toBe(
      en.CAPTAIN_RAMON.FLUXOS.RODAR.ERRO
    );
    expect(wrapper.emitted('fechar')).toBeUndefined();
  });

  it('falha ao carregar a lista mostra ERRO_LISTA e o estado vazio', async () => {
    RamonFluxosAPI.get.mockRejectedValue(new Error('rede'));
    const wrapper = montar();
    await flushPromises();
    expect(wrapper.get('[data-testid="rodar-erro"]').text()).toBe(
      en.CAPTAIN_RAMON.FLUXOS.RODAR.ERRO_LISTA
    );
    expect(wrapper.find('[data-testid="rodar-vazio"]').exists()).toBe(true);
  });

  it('enquanto roda, Fechar e fundo são ignorados', async () => {
    RamonFluxosAPI.rodar.mockReturnValue(new Promise(() => {}));
    const wrapper = montar();
    await flushPromises();
    await wrapper.find('[data-testid="rodar-fluxo-item"]').trigger('click');
    await wrapper.find('button:not([data-testid])').trigger('click');
    expect(wrapper.emitted('fechar')).toBeUndefined();
  });
});
