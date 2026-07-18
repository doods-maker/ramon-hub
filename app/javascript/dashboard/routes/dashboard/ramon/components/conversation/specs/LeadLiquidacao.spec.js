import { shallowMount, flushPromises } from '@vue/test-utils';
import LeadsAPI from 'dashboard/api/leads';
import LeadLiquidacao from '../LeadLiquidacao.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));
vi.mock('dashboard/api/leads', () => ({
  default: { liquidacao: vi.fn(), liquidacaoPdf: vi.fn() },
}));

const lead = { id: 7 };

const mountLiq = (props = {}) =>
  shallowMount(LeadLiquidacao, {
    props: { lead, ...props },
    global: { mocks: { $t: k => k } },
  });

describe('LeadLiquidacao', () => {
  beforeEach(() => {
    LeadsAPI.liquidacao.mockReset();
    LeadsAPI.liquidacaoPdf.mockReset();
  });

  it('desabilita calcular sem rmi e dib', () => {
    const wrapper = mountLiq();
    expect(
      wrapper.find('[data-testid="liq-run"]').attributes('disabled')
    ).toBeDefined();
  });

  it('calcula com rmi string e mostra os totais', async () => {
    LeadsAPI.liquidacao.mockResolvedValue({
      data: {
        total_principal_corrigido: '98000.00',
        total_juros: '7000.00',
        total_atualizacao_selic_ec136: '0.00',
        total_geral: '105000.00',
        honorarios: { sucumbenciais: null, contratuais: { valor: '31500.00' } },
        liquido_cliente: '73500.00',
        avisos: ['aviso do motor'],
      },
    });
    const wrapper = mountLiq();
    await wrapper.find('[data-testid="liq-rmi"]').setValue('1518.00');
    await wrapper.find('[data-testid="liq-dib"]').setValue('2022-03-10');
    await wrapper.find('[data-testid="liq-run"]').trigger('click');
    await flushPromises();
    expect(LeadsAPI.liquidacao).toHaveBeenCalledWith(
      7,
      expect.objectContaining({ rmi: '1518.00', dib: '2022-03-10' })
    );
    expect(wrapper.find('[data-testid="liq-resultado"]').text()).toContain(
      '105.000,00'
    );
  });

  it('mostra o 422 do motor no lugar de erro', async () => {
    LeadsAPI.liquidacao.mockRejectedValue({
      response: { status: 422, data: { error: 'data_citacao anterior a dib' } },
    });
    const wrapper = mountLiq();
    await wrapper.find('[data-testid="liq-rmi"]').setValue('1518.00');
    await wrapper.find('[data-testid="liq-dib"]').setValue('2022-03-10');
    await wrapper.find('[data-testid="liq-run"]').trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-testid="liq-error"]').text()).toContain(
      'data_citacao anterior a dib'
    );
  });

  it('preencher() seta a RMI vinda do cartao', async () => {
    const wrapper = mountLiq();
    wrapper.vm.preencher('3396.58');
    await wrapper.vm.$nextTick();
    expect(wrapper.find('[data-testid="liq-rmi"]').element.value).toBe(
      '3396.58'
    );
  });

  it('abatimentos entram como numeros/strings no payload', async () => {
    LeadsAPI.liquidacao.mockResolvedValue({
      data: { total_geral: '1.00', honorarios: {}, avisos: [] },
    });
    const wrapper = mountLiq();
    await wrapper.find('[data-testid="liq-rmi"]').setValue('1518.00');
    await wrapper.find('[data-testid="liq-dib"]').setValue('2022-03-10');
    await wrapper.find('[data-testid="liq-abatimento-add"]').trigger('click');
    await wrapper.find('[data-testid="liq-abatimento-ano-0"]').setValue('2023');
    await wrapper.find('[data-testid="liq-abatimento-mes-0"]').setValue('2');
    await wrapper
      .find('[data-testid="liq-abatimento-valor-0"]')
      .setValue('1300.50');
    await wrapper.find('[data-testid="liq-run"]').trigger('click');
    await flushPromises();
    expect(LeadsAPI.liquidacao).toHaveBeenCalledWith(
      7,
      expect.objectContaining({
        abatimentos: [{ ano: 2023, mes: 2, valor: '1300.50' }],
      })
    );
  });
});
