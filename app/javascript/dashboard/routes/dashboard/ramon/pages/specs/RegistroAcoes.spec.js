import { mount, flushPromises } from '@vue/test-utils';
import RegistroAcoes from '../RegistroAcoes.vue';
import RamonRegistroAcoesAPI from 'dashboard/api/ramonRegistroAcoes';

const t = (key, params) =>
  params ? `${key} ${Object.values(params).join(' ')}` : key;
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t }) }));

const alertSpy = vi.fn();
vi.mock('dashboard/composables', () => ({ useAlert: msg => alertSpy(msg) }));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    accountScopedRoute: (name, params) => ({ name, params }),
  }),
}));
vi.mock('dashboard/api/ramonRegistroAcoes', () => ({
  default: { listar: vi.fn() },
}));

const REGISTROS = [
  {
    id: 2,
    quando: '2026-10-06T17:32:00Z',
    tipo: 'lead',
    modelo: 'Lead',
    acao: 'update',
    comentario: null,
    quem: { id: 1, nome: 'Ana Gestora' },
    alvo: { lead_id: 7, contato_id: 3, nome: 'Maria Souza' },
    mudancas: { lead_stage_id: ['Qualificação', 'Negociação'] },
  },
  {
    id: 1,
    quando: '2026-10-06T12:00:00Z',
    tipo: 'contato',
    modelo: 'Contact',
    acao: 'update',
    comentario: 'anonimizado',
    quem: null,
    alvo: { contato_id: 3, nome: 'Titular anonimizado #3' },
    mudancas: { name: ['[anonimizado]', '[anonimizado]'] },
  },
];

const mountPage = async (data = {}) => {
  RamonRegistroAcoesAPI.listar.mockResolvedValue({
    data: {
      registros: REGISTROS,
      total: 2,
      pagina: 1,
      por_pagina: 50,
      pessoas: [{ id: 1, nome: 'Ana Gestora' }],
      ...data,
    },
  });
  const wrapper = mount(RegistroAcoes, {
    global: {
      mocks: { $t: t },
      stubs: { RouterLink: { props: ['to'], template: '<a><slot /></a>' } },
    },
  });
  await flushPromises();
  return wrapper;
};

describe('RegistroAcoes.vue', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.useFakeTimers();
  });
  afterEach(() => vi.useRealTimers());

  it('lista quando (SP), quem, a frase e o antes → depois', async () => {
    const wrapper = await mountPage();
    const linhas = wrapper.findAll('[data-testid="registro-linha"]');

    expect(linhas).toHaveLength(2);
    expect(linhas[0].text()).toContain('06/10/2026 14:32');
    expect(linhas[0].text()).toContain('Ana Gestora');
    expect(linhas[0].find('[data-testid="registro-frase"]').text()).toContain(
      'RAMON.REGISTRO.FRASE.LEAD_ETAPA Qualificação Negociação'
    );
    expect(linhas[0].find('[data-testid="registro-mudanca"]').text()).toContain(
      'Qualificação'
    );
    expect(linhas[1].text()).toContain('RAMON.REGISTRO.AUTOMACAO');
    expect(linhas[1].text()).toContain(
      'RAMON.REGISTRO.FRASE.CONTATO_ANONIMIZOU'
    );
  });

  it('filtro vai pro backend e volta pra página 1', async () => {
    const wrapper = await mountPage();
    await wrapper.find('[data-testid="registro-tipo"]').setValue('lead');
    await wrapper.find('[data-testid="registro-busca"]').setValue('maria');
    vi.advanceTimersByTime(300);
    await flushPromises();

    expect(RamonRegistroAcoesAPI.listar).toHaveBeenLastCalledWith({
      tipo: 'lead',
      q: 'maria',
      page: 1,
    });
  });

  it('pagina pra frente quando há mais que uma página', async () => {
    const wrapper = await mountPage({ total: 120 });
    expect(wrapper.find('[data-testid="registro-paginacao"]').text()).toContain(
      '1 2 120'
    );
    await wrapper.find('[data-testid="registro-proxima"]').trigger('click');
    await flushPromises();

    expect(RamonRegistroAcoesAPI.listar).toHaveBeenLastCalledWith({ page: 2 });
  });

  it('Exportar CSV pede o filtro inteiro (todos=1)', async () => {
    URL.createObjectURL = vi.fn(() => 'blob:x');
    URL.revokeObjectURL = vi.fn();
    const wrapper = await mountPage();
    await wrapper.find('[data-testid="registro-csv"]').trigger('click');
    await flushPromises();

    expect(RamonRegistroAcoesAPI.listar).toHaveBeenLastCalledWith({ todos: 1 });
    expect(URL.createObjectURL).toHaveBeenCalled();
  });

  it('sem resultado mostra o vazio', async () => {
    const wrapper = await mountPage({ registros: [], total: 0 });
    expect(wrapper.find('[data-testid="registro-vazio"]').exists()).toBe(true);
  });
});
