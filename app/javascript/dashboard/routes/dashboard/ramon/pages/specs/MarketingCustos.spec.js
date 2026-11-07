import { mount, flushPromises } from '@vue/test-utils';
import MarketingCustos from '../MarketingCustos.vue';
import RamonMarketingAPI from 'dashboard/api/ramonMarketing';

const t = (key, args) => (args ? `${key} ${JSON.stringify(args)}` : key);
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t }) }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/ramonMarketing', () => ({
  default: {
    get: vi.fn(),
    criarCusto: vi.fn(),
    removerCusto: vi.fn(),
    importarGasto: vi.fn(),
    importarMetas: vi.fn(),
  },
}));

const resposta = (extra = {}) => ({
  data: {
    status: {
      gasto: false,
      capi: false,
      insights_ig: false,
      conta_anuncios: false,
      painel_trafego: true,
      ultimo_gasto: { data: '2026-10-14', origem: 'csv' },
    },
    metas: { de: null, ate: null },
    custos: [
      {
        id: 1,
        data: '2026-11-01',
        valor: '1908.0',
        categoria: 'equipe',
        thesis_name: null,
        observacao: 'SDR',
      },
    ],
    categorias: ['impulsionamento', 'equipe'],
    teses: [{ id: 3, name: 'Auxílio-acidente' }],
    ...extra,
  },
});

const montar = async () => {
  const w = mount(MarketingCustos, { global: { mocks: { $t: t } } });
  await flushPromises();
  return w;
};

describe('MarketingCustos', () => {
  beforeEach(() => vi.clearAllMocks());

  it('mostra a Meta desligada, o último gasto pelo CSV e os custos lançados', async () => {
    RamonMarketingAPI.get.mockResolvedValue(resposta());
    const w = await montar();
    expect(w.text()).toContain('RAMON.MARKETING.STATUS.NAO_LIGADO');
    expect(w.text()).toContain('"origem":"CSV"');
    expect(w.text()).toContain('RAMON.MARKETING.CATEGORIAS.EQUIPE');
    expect(w.text()).toContain('RAMON.MARKETING.CUSTO.GERAL');
  });

  it('lança custo com valor em pt-BR e recarrega', async () => {
    RamonMarketingAPI.get.mockResolvedValue(resposta());
    RamonMarketingAPI.criarCusto.mockResolvedValue({ data: {} });
    const w = await montar();
    await w.find('input[inputmode="decimal"]').setValue('1.234,56');
    await w.findAll('select')[0].setValue('impulsionamento');
    await w.find('form').trigger('submit');
    await flushPromises();
    expect(RamonMarketingAPI.criarCusto).toHaveBeenCalledWith(
      expect.objectContaining({
        valor: 1234.56,
        categoria: 'impulsionamento',
        thesis_id: null,
      })
    );
    expect(RamonMarketingAPI.get).toHaveBeenCalledTimes(2);
  });

  it('sem valor não chama a API', async () => {
    RamonMarketingAPI.get.mockResolvedValue(resposta());
    const w = await montar();
    await w.find('form').trigger('submit');
    expect(RamonMarketingAPI.criarCusto).not.toHaveBeenCalled();
  });
});
