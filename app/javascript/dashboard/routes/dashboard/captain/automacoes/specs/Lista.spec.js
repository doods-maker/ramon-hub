import { reactive, nextTick } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import RamonFluxosAPI from 'dashboard/api/ramonFluxos';
import Lista from '../Lista.vue';

const push = vi.fn();
const replace = vi.fn();
const rota = reactive({ query: {} });
vi.mock('vue-router', () => ({
  useRouter: () => ({ push, replace }),
  useRoute: () => rota,
}));
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
// do sistema (B3): desligado, sem versão, em grupo; "Hoje" vem do código (null = sem contador)
const SISTEMA = {
  ...FLUXO,
  id: 3,
  nome: 'Cadência de retomada',
  descricao:
    'No código: Ramon::DailyFollowUpJob (todo dia às 11:00)\n\nO desenho não consegue mostrar: o teto de 15 por dia',
  resumo: 'Todo dia às 11h, prepara rascunhos de retomada para leads parados.',
  gatilho_tipo: 'lead_parado',
  ativo: false,
  limite_dia: 15,
  origem: 'sistema',
  sistema_chave: 'cadencia',
  grupo: 'leads_conversas',
  versao: null,
  hoje: 2,
  esperando: 0,
};

describe('Lista de automações', () => {
  beforeEach(() => {
    rota.query = {};
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
          SISTEMA,
          {
            ...SISTEMA,
            id: 4,
            nome: 'Resumo do dia',
            sistema_chave: 'resumo_do_dia',
            descricao: 'No código: Ramon::DailyDigestJob',
            gatilho_tipo: 'relogio',
            gatilho_rotulo: 'Todo dia às 08:00 (1 vez por conta)',
            grupo: 'rotinas_relatorios',
            limite_dia: null,
            hoje: null,
          },
          {
            ...SISTEMA,
            id: 5,
            nome: 'Avisos do Painel do Cliente',
            sistema_chave: 'avisos_painel',
            descricao:
              'No código: Ramon::PortalAvisosJob — DESLIGADO até o Eduardo aprovar os textos',
            gatilho_tipo: 'relogio',
            grupo: 'painel_cliente',
            alcance: 'fala_com_cliente',
            limite_dia: null,
            hoje: null,
          },
        ],
        resumo: {
          ligados: 1,
          total: 2,
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
    expect(wrapper.find('[data-testid="sistema-linha"]').exists()).toBe(false);
  });

  it('Meus fluxos sem limite mostra "3 / —"', async () => {
    RamonFluxosAPI.get.mockResolvedValue({
      data: {
        payload: [{ ...FLUXO, limite_dia: null }],
        resumo: {},
      },
    });
    const wrapper = mount(Lista);
    await flushPromises();
    expect(wrapper.find('[data-testid="fluxo-linha"]').text()).toContain(
      '3 / —'
    );
  });

  it('trocar de aba escreve ?aba=sistema na URL e "Meus" a tira', async () => {
    rota.query = { x: '1' };
    const wrapper = mount(Lista);
    await flushPromises();
    await wrapper.find('[data-testid="aba-sistema"]').trigger('click');
    expect(replace).toHaveBeenLastCalledWith({
      query: { x: '1', aba: 'sistema' },
    });
    await wrapper.find('[data-testid="aba-meus"]').trigger('click');
    expect(replace).toHaveBeenLastCalledWith({ query: { x: '1' } });
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

  it('fluxo nunca publicado: chave desabilitada; erro ao ligar avisa e recarrega', async () => {
    const wrapper = mount(Lista);
    await flushPromises();
    const [publicado, rascunho] = wrapper.findAll(
      '[data-testid="fluxo-linha"] [role="switch"]'
    );
    expect(rascunho.attributes('disabled')).toBeDefined();
    RamonFluxosAPI.update.mockRejectedValueOnce(new Error('422'));
    RamonFluxosAPI.get.mockClear();
    await publicado.trigger('click');
    await flushPromises();
    expect(RamonFluxosAPI.get).toHaveBeenCalled();
  });

  it('aba Do sistema: explica, só os do sistema, sem chave nem números; "—" sem contador; clicar abre o desenho', async () => {
    const wrapper = mount(Lista);
    await flushPromises();
    await wrapper.find('[data-testid="aba-sistema"]').trigger('click');
    expect(wrapper.find('[data-testid="sistema-explica"]').exists()).toBe(true);
    const linhas = wrapper.findAll('[data-testid="sistema-linha"]');
    expect(linhas).toHaveLength(3);
    expect(linhas[0].text()).toContain(
      'Todo dia às 11h, prepara rascunhos de retomada para leads parados.'
    );
    expect(linhas[0].text()).not.toContain('No código');
    expect(linhas[0].text()).not.toContain('Ramon::');
    expect(linhas[0].text()).not.toContain('O desenho não consegue');
    expect(linhas[0].text()).toContain('2 / 15');
    expect(linhas[2].text()).toContain('—');
    expect(linhas[2].text()).toContain('Todo dia às 08:00 (1 vez por conta)');
    expect(wrapper.find('[role="switch"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="fluxos-resumo"]').exists()).toBe(false);
    await linhas[0].trigger('click');
    expect(push).toHaveBeenCalledWith({
      name: 'captain_automacoes_editor',
      params: { fluxoId: 3 },
    });
  });

  it('Do sistema em grupos, na ordem da tela; selo em quem fala com o cliente', async () => {
    rota.query = { aba: 'sistema' };
    const wrapper = mount(Lista);
    await flushPromises();
    const grupos = wrapper
      .findAll('[data-testid^="sistema-grupo-"]')
      .map(g => g.attributes('data-testid'));
    expect(grupos).toEqual([
      'sistema-grupo-leads_conversas',
      'sistema-grupo-painel_cliente',
      'sistema-grupo-rotinas_relatorios',
    ]);
    const selos = wrapper.findAll('[data-testid="sistema-alcance"]');
    expect(selos).toHaveLength(1);
    expect(selos[0].text()).toContain('talks to the client');
    expect(
      wrapper.find('[data-testid="sistema-grupo-painel_cliente"]').text()
    ).toContain('Avisos do Painel do Cliente');
  });

  it('?aba=sistema (volta do desenho do sistema) abre direto na aba Do sistema', async () => {
    rota.query = { aba: 'sistema' };
    const wrapper = mount(Lista);
    await flushPromises();
    expect(wrapper.findAll('[data-testid="sistema-linha"]')).toHaveLength(3);
    expect(wrapper.find('[data-testid="fluxo-linha"]').exists()).toBe(false);
  });

  it('a aba segue a URL quando ?aba muda sem remontar', async () => {
    rota.query = { aba: 'sistema' };
    const wrapper = mount(Lista);
    await flushPromises();
    expect(wrapper.findAll('[data-testid="sistema-linha"]')).toHaveLength(3);
    rota.query = {};
    await nextTick();
    expect(wrapper.find('[data-testid="sistema-linha"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="fluxo-linha"]').exists()).toBe(true);
  });
  it('fluxo em sombra tem selo próprio', async () => {
    RamonFluxosAPI.get.mockResolvedValue({
      data: { payload: [{ ...FLUXO, modo: 'sombra' }], resumo: {} },
    });
    const wrapper = mount(Lista);
    await flushPromises();
    expect(wrapper.find('[data-testid="fluxo-linha"]').text()).toContain(
      'shadow'
    );
  });
});
