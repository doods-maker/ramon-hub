import { mount, flushPromises } from '@vue/test-utils';
import ValidacaoApto from '../ValidacaoApto.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: (k, p) => (p ? `${k} ${JSON.stringify(p)}` : k) }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const aptos = vi.hoisted(() => ({
  get: vi.fn(),
  validarLote: vi.fn(() =>
    Promise.resolve({ data: { validados: [1], recusados: [] } })
  ),
}));
vi.mock('dashboard/api/leadAptos', () => ({ default: aptos }));
const leads = vi.hoisted(() => ({ apto: vi.fn(() => Promise.resolve({})) }));
vi.mock('dashboard/api/leads', () => ({ default: leads }));

const fila = [
  {
    id: 1,
    name: 'Maria',
    tese: 'Auxílio-acidente (B36)',
    closer: 'Caio',
    apto_situacao: 'aguardando',
    apto_prazo: '2026-11-23T23:59:59-03:00',
  },
  {
    id: 2,
    name: 'João',
    tese: 'BPC/LOAS',
    closer: 'Caio',
    apto_situacao: 'devolvido',
    devolvido_motivo: 'Falta o laudo',
  },
];

const montar = () =>
  mount(ValidacaoApto, {
    global: {
      mocks: { $t: k => k },
      stubs: {
        RamonPageHeader: true,
        RouterLink: { template: '<a><slot /></a>' },
      },
    },
  });

describe('ValidacaoApto.vue', () => {
  beforeEach(() => {
    aptos.get.mockResolvedValue({ data: fila });
    aptos.validarLote.mockClear();
    leads.apto.mockClear();
  });

  it('lista os casos com tese, prazo e o motivo do devolvido', async () => {
    const wrapper = montar();
    await flushPromises();

    const linhas = wrapper.findAll('[data-testid="validacao-linha"]');
    expect(linhas).toHaveLength(2);
    expect(linhas[0].text()).toContain('Auxílio-acidente (B36)');
    expect(linhas[1].text()).toContain('Falta o laudo');
    // devolvido não entra na seleção do lote
    expect(linhas[1].find('[data-testid="validacao-marcar"]').exists()).toBe(
      false
    );
  });

  it('valida em lote os marcados e recarrega', async () => {
    const wrapper = montar();
    await flushPromises();

    await wrapper.find('[data-testid="validacao-marcar"]').setValue(true);
    await wrapper.find('[data-testid="validacao-lote"]').trigger('click');
    await flushPromises();

    expect(aptos.validarLote).toHaveBeenCalledWith([1]);
    expect(aptos.get).toHaveBeenCalledTimes(2);
  });

  it('devolve um caso com motivo obrigatório', async () => {
    const wrapper = montar();
    await flushPromises();
    const linha = wrapper.findAll('[data-testid="validacao-linha"]')[0];

    await linha.find('[data-testid="validacao-devolver"]').trigger('click');
    expect(
      linha.find('[data-testid="validacao-devolver-confirmar"]').attributes()
    ).toHaveProperty('disabled');
    await linha.find('[data-testid="validacao-motivo"]').setValue('Sem CAT');
    await linha
      .find('[data-testid="validacao-devolver-confirmar"]')
      .trigger('click');
    await flushPromises();

    expect(leads.apto).toHaveBeenCalledWith(1, {
      acao: 'devolver',
      motivo: 'Sem CAT',
    });
  });

  it('fila vazia mostra o aviso', async () => {
    aptos.get.mockResolvedValue({ data: [] });
    const wrapper = montar();
    await flushPromises();

    expect(wrapper.find('[data-testid="validacao-vazia"]').exists()).toBe(true);
  });
});
