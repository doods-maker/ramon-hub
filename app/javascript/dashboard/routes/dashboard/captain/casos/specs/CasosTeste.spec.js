import { mount, flushPromises } from '@vue/test-utils';
import IaCasosAPI from 'dashboard/api/captain/iaCasos';
import CaptainFerramentasAPI from 'dashboard/api/captain/ferramentas';
import CasosTeste from '../CasosTeste.vue';

vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: '1', assistantId: '1' } }),
}));
vi.mock('dashboard/components-next/captain/PageLayout.vue', () => ({
  default: {
    template:
      '<div><slot name="search" /><slot name="subHeader" /><slot name="body" /></div>',
  },
}));
vi.mock('../AbasTestar.vue', () => ({ default: { template: '<nav />' } }));
vi.mock('dashboard/api/captain/ferramentas', () => ({
  default: { get: vi.fn() },
}));
vi.mock('dashboard/api/captain/iaCasos', () => ({
  default: {
    casos: vi.fn(),
    rodadas: vi.fn(),
    rodada: vi.fn(),
    rodar: vi.fn(),
    criar: vi.fn(),
    atualizar: vi.fn(),
    remover: vi.fn(),
    noturno: vi.fn().mockResolvedValue({ data: { noturno: true } }),
  },
}));

const caso = (id, titulo, extra = {}) => ({
  id,
  titulo,
  grupo: 'auxilio-acidente',
  ativo: true,
  mensagens: [{ role: 'user', content: `fala ${titulo}` }],
  criterios: {},
  ...extra,
});
const CASOS = [
  caso(1, 'A3 · ainda trabalho'),
  caso(2, 'A5 · quanto cobram'),
  caso(3, 'A11 · quero o Dr. Ramon'),
  caso(4, 'B14 · aposentado', { ativo: false, grupo: 'acrescimo-25' }),
];
const RODADA = {
  id: 9,
  status: 'concluida',
  total: 3,
  passou: 2,
  falhou: 1,
  duracao_ms: 61000,
  created_at: '2026-10-06T15:00:00Z',
  resultados: [
    {
      caso_id: 1,
      passou: true,
      motivos: [],
      resposta: 'Pode continuar trabalhando.',
      ferramentas: [{ nome: 'faq_lookup', resultado: 'achei' }],
      handoff: false,
      duracao_ms: 9000,
    },
    {
      caso_id: 2,
      passou: false,
      motivos: ['Disse o proibido: desconto'],
      resposta: 'Te dou um desconto!',
      ferramentas: [
        {
          nome: 'mover_etapa',
          resultado: '[TESTE] faria mover_etapa(etapa: Ganho)',
        },
      ],
      handoff: false,
      duracao_ms: 8000,
    },
    { caso_id: 3, passou: true, motivos: [], resposta: 'ok', ferramentas: [] },
  ],
  comparacao: {
    rodada_id: 8,
    passou: 2,
    total: 3,
    pioraram: [2],
    melhoraram: [3],
  },
};

const montar = async () => {
  const wrapper = mount(CasosTeste);
  await flushPromises();
  return wrapper;
};

describe('Casos de teste da IA', () => {
  beforeEach(() => {
    vi.useRealTimers();
    CaptainFerramentasAPI.get.mockResolvedValue({
      data: { payload: [{ id: 'faq_lookup', title: 'Buscar nas FAQs' }] },
    });
    IaCasosAPI.casos.mockResolvedValue({
      data: {
        payload: CASOS,
        estimativa: { casos: 3, custo_usd: 0.15, segundos: 60 },
      },
    });
    IaCasosAPI.rodadas.mockResolvedValue({
      data: { payload: [{ ...RODADA, resultados: undefined }], noturno: false },
    });
    IaCasosAPI.rodada.mockResolvedValue({ data: RODADA });
  });

  it('mostra o placar, a comparação e o caso que piorou primeiro', async () => {
    const wrapper = await montar();

    expect(wrapper.find('[data-testid="casos-placar"]').text()).toBe('2/3');
    expect(wrapper.find('[data-testid="casos-pioraram"]').text()).toBe(
      '1 got worse'
    );
    expect(wrapper.find('[data-testid="casos-melhoraram"]').exists()).toBe(
      true
    );
    const linhas = wrapper.findAll('[data-testid="caso-linha"]');
    expect(linhas).toHaveLength(4);
    expect(linhas[0].text()).toContain('A5');
    expect(linhas[0].find('[data-testid="caso-chip"]').text()).toBe(
      'Got worse'
    );
    expect(wrapper.find('[data-testid="casos-historico"]').text()).toContain(
      '2/3'
    );
  });

  it('liga a rodada da madrugada (I-X6)', async () => {
    const wrapper = await montar();
    wrapper
      .findComponent('[data-testid="casos-noturno-chave"]')
      .vm.$emit('update:modelValue', true);
    await flushPromises();
    expect(IaCasosAPI.noturno).toHaveBeenCalledWith(1, true);
  });

  it('busca e filtro de ativos', async () => {
    const wrapper = await montar();

    await wrapper.find('[data-testid="casos-busca"]').setValue('ramon');
    expect(wrapper.findAll('[data-testid="caso-linha"]')).toHaveLength(1);

    await wrapper.find('[data-testid="casos-busca"]').setValue('');
    await wrapper
      .find('[data-testid="casos-filtro-ativo"]')
      .setValue('inativos');
    const linhas = wrapper.findAll('[data-testid="caso-linha"]');
    expect(linhas).toHaveLength(1);
    expect(linhas[0].text()).toContain('B14');
  });

  it('abre o detalhe com resposta, ferramentas pedidas e motivo', async () => {
    const wrapper = await montar();

    await wrapper
      .findAll('[data-testid="caso-linha"] button')[0]
      .trigger('click');

    const detalhe = wrapper.find('[data-testid="caso-detalhe"]');
    expect(detalhe.text()).toContain('Disse o proibido: desconto');
    expect(detalhe.text()).toContain('Te dou um desconto!');
    expect(detalhe.text()).toContain('[TESTE] faria mover_etapa');
  });

  it('rodar todos mostra o custo, confirma e acompanha o progresso', async () => {
    vi.useFakeTimers();
    const rodando = {
      ...RODADA,
      id: 10,
      status: 'rodando',
      resultados: RODADA.resultados.slice(0, 1),
      comparacao: null,
    };
    IaCasosAPI.rodar.mockResolvedValue({
      data: { ...rodando, resultados: undefined },
    });
    const wrapper = await montar();
    IaCasosAPI.rodada.mockResolvedValue({ data: rodando });

    await wrapper.find('[data-testid="casos-rodar"]').trigger('click');
    const confirmar = wrapper.find('[data-testid="casos-confirmar"]');
    expect(confirmar.text()).toContain('US$ 0,15');
    expect(confirmar.text()).toContain('3');

    await wrapper
      .find('[data-testid="casos-confirmar-rodar"]')
      .trigger('click');
    await flushPromises();
    expect(IaCasosAPI.rodar).toHaveBeenCalledWith(1);
    expect(wrapper.find('[data-testid="casos-progresso"]').text()).toContain(
      '1 of 3'
    );

    IaCasosAPI.rodada.mockClear();
    vi.advanceTimersByTime(3000);
    await flushPromises();
    expect(IaCasosAPI.rodada).toHaveBeenCalledWith(1, 10);
    wrapper.unmount();
  });

  it('segunda rodada do mesmo assistente: avisa e não quebra', async () => {
    IaCasosAPI.rodar.mockRejectedValue({
      response: { data: { error: 'Já tem uma rodada em andamento.' } },
    });
    const wrapper = await montar();

    await wrapper.find('[data-testid="casos-rodar"]').trigger('click');
    await wrapper
      .find('[data-testid="casos-confirmar-rodar"]')
      .trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-testid="casos-aviso"]').text()).toBe(
      'Já tem uma rodada em andamento.'
    );
  });

  it('sem rodada ainda: convida a rodar', async () => {
    IaCasosAPI.rodadas.mockResolvedValue({ data: { payload: [] } });
    const wrapper = await montar();

    expect(wrapper.find('[data-testid="casos-sem-rodada"]').exists()).toBe(
      true
    );
    expect(IaCasosAPI.rodada).not.toHaveBeenCalled();
  });
});
