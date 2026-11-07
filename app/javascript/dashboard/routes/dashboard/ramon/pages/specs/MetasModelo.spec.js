import { mount, flushPromises } from '@vue/test-utils';
import MetasModelo from '../../components/marketing/MetasModelo.vue';
import RamonMarketingAPI from 'dashboard/api/ramonMarketing';

const t = (key, args) => (args ? `${key} ${JSON.stringify(args)}` : key);
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t }) }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('@vueuse/core', () => ({ onKeyStroke: vi.fn() }));
vi.mock('dashboard/api/ramonMarketing', () => ({
  default: {
    metasAtivas: vi.fn(),
    editarMeta: vi.fn(),
    importarMetas: vi.fn(),
    apagarMetas: vi.fn(),
  },
}));

const metas = (extra = {}) => ({
  ativas: false,
  linhas: [
    {
      id: 1,
      mes: '2026-11-01',
      metrica: 'contratos',
      valor: '20.0',
      editada: false,
    },
    {
      id: 2,
      mes: '2026-11-01',
      metrica: 'cac',
      valor: '1215.0',
      editada: true,
    },
  ],
  ...extra,
});

const montar = (props = metas()) =>
  mount(MetasModelo, {
    props: { metas: props },
    global: { mocks: { $t: t } },
  });

describe('MetasModelo', () => {
  beforeEach(() => vi.clearAllMocks());

  it('desligadas: avisa que estão fora do Metabase e mostra a edição à mão', () => {
    const w = montar();
    expect(w.text()).toContain('RAMON.MARKETING.METAS.DESLIGADAS');
    expect(w.text()).toContain('RAMON.MARKETING.METAS.EDITADAS {"n":1}');
    const celulas = w.findAll('tbody input');
    expect(celulas.map(c => c.element.value)).toEqual(['20', '1.215']);
  });

  it('o interruptor liga as metas e pede para recarregar', async () => {
    RamonMarketingAPI.metasAtivas.mockResolvedValue({});
    const w = montar();
    await w.find('[role="switch"]').trigger('click');
    await flushPromises();
    expect(RamonMarketingAPI.metasAtivas).toHaveBeenCalledWith(true);
    expect(w.emitted('atualizar')).toHaveLength(1);
  });

  it('editar a célula salva o valor em pt-BR', async () => {
    RamonMarketingAPI.editarMeta.mockResolvedValue({ data: {} });
    const w = montar();
    const celula = w.findAll('tbody input')[0];
    await celula.setValue('22,5');
    await celula.trigger('change');
    await flushPromises();
    expect(RamonMarketingAPI.editarMeta).toHaveBeenCalledWith(1, 22.5);
  });

  it('"1.215" é milhar, e se a gravação falhar a célula volta ao valor salvo', async () => {
    RamonMarketingAPI.editarMeta.mockRejectedValue(new Error('rede'));
    const w = montar();
    const celula = w.findAll('tbody input')[1];
    await celula.setValue('1.300');
    await celula.trigger('change');
    await flushPromises();
    expect(RamonMarketingAPI.editarMeta).toHaveBeenCalledWith(2, 1300);
    expect(celula.element.value).toBe('1.215');
  });

  it('arquivo por cima de edição: 409 abre a confirmação e reenvia com confirmar', async () => {
    RamonMarketingAPI.importarMetas
      .mockRejectedValueOnce({
        response: { status: 409, data: { editadas: 1 } },
      })
      .mockResolvedValueOnce({ data: { meses: 15 } });
    const w = montar();
    const arquivo = { text: async () => '[]' }; // jsdom não tem File#text
    const input = w.find('input[type="file"]');
    Object.defineProperty(input.element, 'files', { value: [arquivo] });
    await input.trigger('change');
    await flushPromises();
    expect(w.text()).toContain(
      'RAMON.MARKETING.METAS.SOBRESCREVER_MSG {"n":1}'
    );

    const botoes = w.findAll('button');
    await botoes[botoes.length - 1].trigger('click');
    await flushPromises();
    expect(RamonMarketingAPI.importarMetas).toHaveBeenLastCalledWith(
      '[]',
      true
    );
  });
});
