import { shallowMount, flushPromises } from '@vue/test-utils';
import LeadsAPI from 'dashboard/api/leads';
import LeadMaternidade from '../LeadMaternidade.vue';

const tWithParams = (k, params) =>
  params ? `${k}:${Object.values(params).join(',')}` : k;
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: tWithParams }) }));
vi.mock('dashboard/api/leads', () => ({
  default: { maternidade: vi.fn() },
}));

const lead = { id: 11 };

const mountMaternidade = (props = {}) =>
  shallowMount(LeadMaternidade, {
    props: { lead, ...props },
    global: { mocks: { $t: tWithParams } },
  });

const resultado = {
  rmi: '1518.00',
  carencia: { exigida: 0, fundamento: 'segurada especial dispensa carência' },
  duracao_dias: 120,
  avisos: ['evento anterior a 04/2024 — regra de transição aplicada'],
};

describe('LeadMaternidade', () => {
  beforeEach(() => {
    LeadsAPI.maternidade.mockReset();
  });

  it('calcular renderiza RMI e carência 0 com fundamento', async () => {
    LeadsAPI.maternidade.mockResolvedValue({ data: resultado });
    const wrapper = mountMaternidade();
    await wrapper
      .find('[data-testid="maternidade-data-evento"]')
      .setValue('2026-03-01');
    await wrapper
      .find('[data-testid="maternidade-categoria"]')
      .setValue('especial');
    await wrapper.find('[data-testid="maternidade-calcular"]').trigger('click');
    await flushPromises();

    expect(LeadsAPI.maternidade).toHaveBeenCalledWith(11, {
      data_evento: '2026-03-01',
      categoria: 'especial',
    });
    expect(wrapper.find('[data-testid="maternidade-rmi"]').text()).toContain(
      'R$'
    );
    expect(
      wrapper.find('[data-testid="maternidade-carencia"]').text()
    ).toContain('segurada especial dispensa carência');
    expect(
      wrapper.find('[data-testid="maternidade-duracao"]').text()
    ).toContain('120');
    expect(wrapper.find('[data-testid="maternidade-avisos"]').text()).toContain(
      'regra de transição aplicada'
    );
  });

  it('erro de rede mostra erro+retry, não vazio; retry refaz a chamada', async () => {
    LeadsAPI.maternidade.mockRejectedValueOnce({
      response: { data: { error: 'categoria inválida' } },
    });
    const wrapper = mountMaternidade();
    await wrapper
      .find('[data-testid="maternidade-data-evento"]')
      .setValue('2026-03-01');
    await wrapper.find('[data-testid="maternidade-calcular"]').trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-testid="maternidade-error"]').text()).toContain(
      'categoria inválida'
    );
    expect(wrapper.find('[data-testid="maternidade-retry"]').exists()).toBe(
      true
    );
    expect(wrapper.find('[data-testid="maternidade-resultado"]').exists()).toBe(
      false
    );

    LeadsAPI.maternidade.mockResolvedValueOnce({ data: resultado });
    await wrapper.find('[data-testid="maternidade-retry"]').trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-testid="maternidade-error"]').exists()).toBe(
      false
    );
    expect(wrapper.find('[data-testid="maternidade-resultado"]').exists()).toBe(
      true
    );
  });
});
