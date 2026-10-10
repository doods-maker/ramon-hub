import { mount, flushPromises } from '@vue/test-utils';
import ConferenciaFases from '../ConferenciaFases.vue';
import RamonConferenciaFasesAPI from 'dashboard/api/ramonConferenciaFases';

const t = (key, params) =>
  params ? `${key} ${Object.values(params).join(' ')}` : key;
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t }) }));

const alertSpy = vi.fn();
vi.mock('dashboard/composables', () => ({ useAlert: msg => alertSpy(msg) }));
vi.mock('dashboard/api/ramonConferenciaFases', () => ({
  default: { get: vi.fn(), update: vi.fn(), aplicar: vi.fn() },
}));

const LINHA = {
  id: 7,
  lawsuit_id: 900,
  numero: '5001234-56.2025.4.04.7207',
  cliente: 'Maria Souza',
  responsavel: 'Ana Gestora',
  etapa_advbox: 'Aguardando perícia',
  fase_advbox: 'justica',
  painel_titulo: 'Recurso em andamento',
  fase_painel: 'recurso',
  grupo: 'atrasada',
  tribunal: { etapa: 'recurso', data: '2026-09-30', titulo: 'Apelação' },
  agenda: [],
  ultimo_andamento: '2026-10-02',
  sugestao: { etapa: 'Recurso', etapa_id: 12 },
  painel_marca: null,
  atualizar: false,
  obs: null,
  marcado_em: null,
  marcado_por: null,
  aplicado_em: null,
  aplicado_por: null,
  erro_aplicacao: null,
};

const mountPage = async ({ aplicar = false, ...data } = {}) => {
  RamonConferenciaFasesAPI.get.mockResolvedValue({
    data: {
      payload: [LINHA],
      total: 1,
      pagina: 1,
      por_pagina: 50,
      resumo: {
        grupos: { atrasada: 1 },
        conferidos: 0,
        errados: 0,
        para_aplicar: 3,
        responsaveis: ['Ana Gestora'],
      },
      atualizado_em: '2026-10-09T05:10:00Z',
      permissoes: { aplicar },
      ...data,
    },
  });
  const wrapper = mount(ConferenciaFases, { global: { mocks: { $t: t } } });
  await flushPromises();
  return wrapper;
};

describe('ConferenciaFases.vue', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.useFakeTimers();
  });
  afterEach(() => vi.useRealTimers());

  it('pede o grupo "atrasada" e lista ADVBOX ao lado do painel', async () => {
    const wrapper = await mountPage();
    expect(RamonConferenciaFasesAPI.get).toHaveBeenCalledWith({
      grupo: 'atrasada',
      page: 1,
    });
    const linha = wrapper.find('[data-testid="conferencia-linha"]');
    expect(linha.text()).toContain('Maria Souza');
    expect(linha.text()).toContain('Aguardando perícia');
    expect(linha.text()).toContain('Recurso em andamento');
    expect(linha.find('[data-testid="conferencia-decidiu"]').text()).toContain(
      'Apelação 30/09/2026'
    );
  });

  it('Certo grava painel_marca e troca a linha pela resposta', async () => {
    const wrapper = await mountPage();
    RamonConferenciaFasesAPI.update.mockResolvedValue({
      data: {
        ...LINHA,
        painel_marca: 'certo',
        marcado_em: '2026-10-09T13:00:00Z',
        marcado_por: 'Ana Gestora',
      },
    });
    await wrapper
      .find('[data-testid="conferencia-marca-certo"]')
      .trigger('click');
    await flushPromises();

    expect(RamonConferenciaFasesAPI.update).toHaveBeenCalledWith(7, {
      painel_marca: 'certo',
    });
    expect(wrapper.text()).toContain(
      'RAMON.CONFERENCIA.CONFERIDO_POR Ana Gestora'
    );
  });

  it('agente não vê o botão de aplicar', async () => {
    const wrapper = await mountPage();
    expect(wrapper.find('[data-testid="conferencia-aplicar"]').exists()).toBe(
      false
    );
  });

  it('admin aplica depois de confirmar na própria página', async () => {
    const wrapper = await mountPage({ aplicar: true });
    RamonConferenciaFasesAPI.aplicar.mockResolvedValue({
      data: { enfileirados: 3 },
    });
    await wrapper.find('[data-testid="conferencia-aplicar"]').trigger('click');
    expect(RamonConferenciaFasesAPI.aplicar).not.toHaveBeenCalled();
    await wrapper
      .find('[data-testid="confirm-modal-confirm"]')
      .trigger('click');
    await flushPromises();

    expect(RamonConferenciaFasesAPI.aplicar).toHaveBeenCalled();
    expect(wrapper.find('[data-testid="conferencia-enviados"]').text()).toBe(
      'RAMON.CONFERENCIA.ENVIADOS 3'
    );
  });

  it('busca volta pra página 1 com o filtro', async () => {
    const wrapper = await mountPage();
    await wrapper
      .find('[data-testid="conferencia-grupo-todos"]')
      .trigger('click');
    await wrapper.find('[data-testid="conferencia-busca"]').setValue('maria');
    vi.advanceTimersByTime(300);
    await flushPromises();

    expect(RamonConferenciaFasesAPI.get).toHaveBeenLastCalledWith({
      q: 'maria',
      page: 1,
    });
  });

  it('sem nenhuma carga mostra que a conferência não foi montada', async () => {
    const wrapper = await mountPage({
      payload: [],
      total: 0,
      resumo: { grupos: {}, responsaveis: [], para_aplicar: 0 },
    });
    expect(wrapper.find('[data-testid="conferencia-vazio"]').text()).toBe(
      'RAMON.CONFERENCIA.NAO_MONTADA'
    );
  });
});
