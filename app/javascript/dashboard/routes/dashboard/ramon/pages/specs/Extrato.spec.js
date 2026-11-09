import { mount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import Extrato from '../Extrato.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: (k, p) => (p ? `${k} ${JSON.stringify(p)}` : k) }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const api = vi.hoisted(() => ({
  get: vi.fn(),
  salvarMeta: vi.fn(() => Promise.resolve({})),
  programas: vi.fn(() => Promise.resolve({ data: [] })),
  salvarPrograma: vi.fn(() => Promise.resolve({ data: {} })),
}));
vi.mock('dashboard/api/ramonExtrato', () => ({ default: api }));

const sdr = {
  user: { id: 1, name: 'Sara' },
  papel: 'sdr',
  meta: 50,
  fator: 0.8,
  contagem: 2,
  variavel: 12.8,
  dsr: 3.9,
  bonus: [],
  total: 16.7,
  unidades: [
    {
      data: '2026-11-10T15:00:00Z',
      lead_id: 9,
      lead_nome: 'Maria',
      evento: 'reuniao_qualificada',
      valor: 8,
    },
  ],
};
const hibrido = {
  user: { id: 2, name: 'Caio' },
  papel: 'hibrido',
  meta: null,
  fator: 1,
  contagem: 41,
  variavel: 1025,
  dsr: 197.12,
  bonus: [
    { tipo: 'faixa', valor: 450 },
    { tipo: 'gas', valor: 25 },
  ],
  sem_valor: 1,
  total: 1697.12,
  unidades: [],
};

const montar = (role = 'administrator') =>
  mount(Extrato, {
    global: {
      plugins: [createStore({ getters: { getCurrentRole: () => role } })],
      mocks: { $t: k => k },
      stubs: { RamonPageHeader: true },
    },
  });

describe('Extrato.vue (duas grades)', () => {
  beforeEach(() => {
    api.get.mockResolvedValue({ data: { pessoas: [sdr, hibrido] } });
    api.salvarMeta.mockClear();
    api.salvarPrograma.mockClear();
  });

  it('mostra DSR, bônus do Programa e a marca de tese sem comissão', async () => {
    const wrapper = montar();
    await flushPromises();

    const cartoes = wrapper.findAll('[data-testid="extrato-pessoa"]');
    expect(cartoes[0].find('[data-testid="extrato-dsr"]').text()).toContain(
      '3,90'
    );
    expect(
      cartoes[1].findAll('[data-testid="extrato-bonus"]').map(b => b.text())
    ).toEqual([
      expect.stringContaining('RAMON.EXTRATO.BONUS_TIPO.faixa'),
      expect.stringContaining('RAMON.EXTRATO.BONUS_TIPO.gas'),
    ]);
    expect(cartoes[1].find('[data-testid="extrato-sem-valor"]').exists()).toBe(
      true
    );
  });

  it('gestor salva papel, meta e fator (sem rampa)', async () => {
    const wrapper = montar();
    await flushPromises();
    const cartao = wrapper.findAll('[data-testid="extrato-pessoa"]')[0];

    await cartao.find('[data-testid="extrato-papel"]').setValue('closer');
    await cartao.find('[data-testid="extrato-fator"]').setValue('1.1');
    await cartao.find('[data-testid="extrato-salvar-meta"]').trigger('click');

    expect(api.salvarMeta).toHaveBeenCalledWith(
      expect.objectContaining({
        user_id: 1,
        papel: 'closer',
        meta: 50,
        fator: 1.1,
      })
    );
    expect(api.salvarMeta.mock.calls[0][0]).not.toHaveProperty('rampa');
  });

  it('gestor lança o Programa de Metas do trimestre', async () => {
    const wrapper = montar();
    await flushPromises();

    const form = wrapper.find('[data-testid="extrato-programa"]');
    await form.find('[data-testid="programa-inicio"]').setValue('2026-12-01');
    await form.find('[data-testid="programa-fim"]').setValue('2027-02-28');
    await form.find('[data-testid="programa-faixa1-min"]').setValue('25');
    await form.find('[data-testid="programa-faixa1-valor"]').setValue('300');
    await form.find('[data-testid="programa-salvar"]').trigger('click');

    expect(api.salvarPrograma).toHaveBeenCalledWith(
      expect.objectContaining({
        inicio: '2026-12-01',
        fim: '2027-02-28',
        regras: expect.objectContaining({
          faixas: [{ min: 25, valor: 300 }],
        }),
      })
    );
  });

  it('agente não vê o Programa nem os campos de meta', async () => {
    api.get.mockResolvedValue({ data: { pessoas: [sdr] } });
    const wrapper = montar('agent');
    await flushPromises();

    expect(wrapper.find('[data-testid="extrato-programa"]').exists()).toBe(
      false
    );
    expect(wrapper.find('[data-testid="extrato-papel"]').exists()).toBe(false);
  });
});
