import { shallowMount, flushPromises } from '@vue/test-utils';
import LeadsAPI from 'dashboard/api/leads';
import LeadSimulador from '../LeadSimulador.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));
vi.mock('dashboard/api/leads', () => ({
  default: { simulate: vi.fn() },
}));

const resultado = {
  mensal: '1700.00',
  perda_mensal: '1700.00',
  atrasados: '17000.00',
  atrasados_estimativa: { estimado: true, meses: 10 },
  honorario: {
    valor: '10200.00',
    percentual: 30,
    n_mensalidades: 3,
    tese: 'Auxílio-acidente (B36)',
  },
  avisos: ['qualidade de segurado não é aferida pelo motor'],
};

const lead = {
  id: 7,
  thesis_name: 'Auxílio-acidente (B36)',
  contact_data_nascimento: '1980-05-10',
  contact_sexo: 'F',
};

const mountSim = (props = {}) =>
  shallowMount(LeadSimulador, {
    props: { lead, ...props },
    global: { mocks: { $t: k => k } },
  });

const fillForm = async wrapper => {
  await wrapper.find('[data-testid="sim-der"]').setValue('2025-09-01');
  await wrapper.find('[data-testid="sim-salario"]').setValue('3000');
};

describe('LeadSimulador.vue', () => {
  beforeEach(() => {
    LeadsAPI.simulate.mockReset();
  });

  it('pré-preenche nascimento/sexo do contato e benefício pela tese', () => {
    const wrapper = mountSim();
    expect(wrapper.find('[data-testid="sim-nascimento"]').element.value).toBe(
      '1980-05-10'
    );
    expect(wrapper.find('[data-testid="sim-sexo"]').element.value).toBe('F');
    expect(wrapper.find('[data-testid="sim-beneficio"]').element.value).toBe(
      'acidente'
    );
  });

  it('mostra o disclaimer sempre, mesmo sem resultado', () => {
    const wrapper = mountSim();
    expect(wrapper.find('[data-testid="sim-disclaimer"]').exists()).toBe(true);
  });

  it('simula e renderiza atrasados, perda mensal e honorário', async () => {
    LeadsAPI.simulate.mockResolvedValue({ data: resultado });
    const wrapper = mountSim();
    await fillForm(wrapper);
    await wrapper.find('[data-testid="sim-run"]').trigger('click');
    await flushPromises();
    expect(LeadsAPI.simulate).toHaveBeenCalledWith(
      7,
      expect.objectContaining({ beneficio: 'acidente', salario: 3000 })
    );
    expect(wrapper.find('[data-testid="sim-atrasados"]').text()).toContain(
      '17.000,00'
    );
    expect(wrapper.find('[data-testid="sim-honorario"]').text()).toContain(
      '10.200,00'
    );
    expect(wrapper.find('[data-testid="sim-avisos"]').text()).toContain(
      'qualidade de segurado'
    );
  });

  it('mostra estado explicativo quando o motor está fora do ar (503)', async () => {
    LeadsAPI.simulate.mockRejectedValue({
      response: { status: 503, data: { error: 'motor indisponível' } },
    });
    const wrapper = mountSim();
    await fillForm(wrapper);
    await wrapper.find('[data-testid="sim-run"]').trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-testid="sim-motor-down"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="sim-resultado"]').exists()).toBe(false);
  });

  it('mostra o erro do motor em entrada inválida (422)', async () => {
    LeadsAPI.simulate.mockRejectedValue({
      response: { status: 422, data: { error: 'benefício inválido' } },
    });
    const wrapper = mountSim();
    await fillForm(wrapper);
    await wrapper.find('[data-testid="sim-run"]').trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-testid="sim-error"]').text()).toContain(
      'benefício inválido'
    );
  });
});
