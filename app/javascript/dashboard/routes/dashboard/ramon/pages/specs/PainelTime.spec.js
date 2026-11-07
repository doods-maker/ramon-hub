import { mount, flushPromises } from '@vue/test-utils';
import PainelTime from '../PainelTime.vue';
import RamonPainelTimeAPI from 'dashboard/api/ramonPainelTime';

const t = (key, params) =>
  params ? `${key} ${Object.values(params).join(' ')}` : key;
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t }) }));

let role = 'administrator';
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ getters: { getCurrentRole: role } }),
}));
vi.mock('dashboard/api/ramonPainelTime', () => ({ default: { get: vi.fn() } }));

const METAS = {
  primeira_resposta: { alvo: 5, sentido: 'max', unidade: 'min' },
  sem_resposta: { alvo: 0, sentido: 'max', unidade: 'n' },
  registro_completo: { alvo: 100, sentido: 'min', unidade: '%' },
  qualificado_agendada: { alvo: 70, sentido: 'min', unidade: '%' },
  show: { alvo: 75, sentido: 'min', unidade: '%' },
  nao_qualificada: { alvo: 15, sentido: 'max', unidade: '%' },
};
const kpi = (valor, num, den) => ({ valor, num, den });
const linha = (id, name, show) => ({
  user: id ? { id, name } : null,
  meta_mes: { meta: 25, realizado: 18, dias_uteis_restantes: 6 },
  kpis: {
    primeira_resposta: kpi(3, 40, null),
    sem_resposta: kpi(2, 2, 5),
    registro_completo: kpi(null, 0, 0),
    qualificado_agendada: kpi(80, 16, 20),
    show: kpi(show, 22, 31),
    nao_qualificada: kpi(11, 2, 18),
  },
  volume: { total: 96, serie: [{ inicio: '2026-10-01', n: 4 }] },
});
const resposta = (extra = {}) => ({
  data: {
    papel: 'sdr',
    periodo: 'mes',
    metas: METAS,
    time: linha(null, null, 71),
    pessoas: [linha(11, 'Ana', 71), linha(12, 'Bia', 90)],
    ...extra,
  },
});

const montar = async (dados = resposta()) => {
  RamonPainelTimeAPI.get.mockResolvedValue(dados);
  const wrapper = mount(PainelTime);
  await flushPromises();
  return wrapper;
};
const status = (wrapper, chave) =>
  wrapper.find(`[data-testid="painel-kpi-${chave}"]`).attributes('data-status');

describe('PainelTime.vue', () => {
  beforeEach(() => {
    role = 'administrator';
    vi.clearAllMocks();
  });

  it('gestor: pede SDR do mês e pinta cada cartão pela meta', async () => {
    const wrapper = await montar();
    expect(RamonPainelTimeAPI.get).toHaveBeenCalledWith({
      papel: 'sdr',
      periodo: 'mes',
    });
    expect(status(wrapper, 'primeira_resposta')).toBe('ok');
    expect(status(wrapper, 'sem_resposta')).toBe('cobrar');
    expect(status(wrapper, 'show')).toBe('atencao');
    expect(status(wrapper, 'registro_completo')).toBe('sem_dado');
    expect(wrapper.find('[data-testid="painel-kpi-show"]').text()).toContain(
      'RAMON.PAINEL_TIME.DE 22 31'
    );
    expect(wrapper.find('[data-testid="painel-meta"]').text()).toContain('72%');
    expect(wrapper.findAll('[data-testid="painel-linha-pessoa"]')).toHaveLength(
      2
    );
  });

  it('cada cartão mostra a variação contra o período anterior', async () => {
    const time = linha(null, null, 71);
    time.anterior = {
      kpis: { primeira_resposta: kpi(4, 30, null), show: kpi(65, 20, 31) },
      volume_total: 80,
    };
    const wrapper = await montar(
      resposta({
        time,
        anterior: {
          inicio: '2026-10-01T00:00:00-03:00',
          fim: '2026-10-18T14:00:00-03:00',
        },
      })
    );
    const variacao = chave =>
      wrapper.find(
        `[data-testid="painel-kpi-${chave}"] [data-testid="variacao"]`
      );
    // 1ª resposta caiu de 4 para 3 min: melhor (sentido max)
    expect(variacao('primeira_resposta').attributes('data-seta')).toBe('desce');
    expect(variacao('primeira_resposta').text()).toContain('25');
    expect(variacao('show').text()).toContain('RAMON.VARIACAO.PONTOS 6');
    expect(variacao('show').text()).toContain(
      'RAMON.VARIACAO.VS_DIAS 01/10 18/10'
    );
    // sem anterior (contado agora / sem dado): sem variação
    expect(variacao('sem_resposta').exists()).toBe(false);
    expect(
      wrapper
        .find('[data-testid="painel-volume"] [data-testid="variacao"]')
        .text()
    ).toContain('RAMON.VARIACAO.PORCENTO 20');
  });

  it('gestor escolhe a pessoa: os cartões passam a ser dela', async () => {
    const wrapper = await montar();
    await wrapper
      .findAll('[data-testid="painel-alvo-pessoa"]')[1]
      .trigger('click');
    expect(status(wrapper, 'show')).toBe('ok');
  });

  it('trocar papel e período pede de novo', async () => {
    const wrapper = await montar();
    await wrapper.find('[data-testid="painel-papel-closer"]').trigger('click');
    await wrapper
      .find('[data-testid="painel-periodo-mes_passado"]')
      .trigger('click');
    await flushPromises();
    expect(RamonPainelTimeAPI.get).toHaveBeenLastCalledWith({
      papel: 'closer',
      periodo: 'mes_passado',
    });
  });

  it('agente: só os próprios números, sem tabela nem seletor de pessoa', async () => {
    role = 'agent';
    const wrapper = await montar(
      resposta({ time: null, pessoas: [linha(11, 'Ana', 71)] })
    );
    expect(status(wrapper, 'show')).toBe('atencao');
    expect(wrapper.find('[data-testid="painel-tabela"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="painel-alvo"]').exists()).toBe(false);
  });

  it('agente fora do time SDR vai uma vez pro Closer', async () => {
    role = 'agent';
    await montar(resposta({ time: null, pessoas: [] }));
    await flushPromises();
    expect(RamonPainelTimeAPI.get).toHaveBeenCalledTimes(2);
    expect(RamonPainelTimeAPI.get).toHaveBeenLastCalledWith({
      papel: 'closer',
      periodo: 'mes',
    });
  });

  it('time vazio mostra o aviso', async () => {
    const wrapper = await montar(resposta({ pessoas: [] }));
    expect(wrapper.find('[data-testid="painel-vazio"]').exists()).toBe(true);
  });
});
