import { shallowMount, flushPromises } from '@vue/test-utils';
import LeadsAPI from 'dashboard/api/leads';
import LeadSimulador from '../LeadSimulador.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));
vi.mock('dashboard/api/leads', () => ({
  default: {
    simulate: vi.fn(),
    uploadCnis: vi.fn(),
    getCnis: vi.fn(),
    deleteCnis: vi.fn(),
    painel: vi.fn(),
  },
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

const cnisResumo = {
  filename: 'cnis.pdf',
  uploaded_at: '2026-07-10T10:00:00Z',
  nascimento: '1980-05-10',
  competencias: 110,
  vinculos: 9,
  avisos: ['03/2013: indicador pendente'],
};

describe('LeadSimulador.vue', () => {
  beforeEach(() => {
    LeadsAPI.simulate.mockReset();
    LeadsAPI.uploadCnis.mockReset();
    LeadsAPI.getCnis.mockReset();
    LeadsAPI.deleteCnis.mockReset();
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

  it('com CNIS no caso, esconde os campos manuais e simula com usar_cnis', async () => {
    LeadsAPI.simulate.mockResolvedValue({ data: resultado });
    const wrapper = mountSim({ lead: { ...lead, cnis_resumo: cnisResumo } });
    expect(wrapper.find('[data-testid="sim-cnis-chip"]').text()).toContain(
      'cnis.pdf'
    );
    expect(wrapper.find('[data-testid="sim-salario"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="sim-nascimento"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="sim-cnis-avisos"]').text()).toContain(
      'indicador pendente'
    );
    await wrapper.find('[data-testid="sim-der"]').setValue('2025-09-01');
    await wrapper.find('[data-testid="sim-run"]').trigger('click');
    await flushPromises();
    expect(LeadsAPI.simulate).toHaveBeenCalledWith(
      7,
      expect.objectContaining({ usar_cnis: true, der: '2025-09-01' })
    );
  });

  it('faz upload do CNIS e mostra o chip com o resumo', async () => {
    LeadsAPI.uploadCnis.mockResolvedValue({ data: cnisResumo });
    const wrapper = mountSim();
    const input = wrapper.find('[data-testid="sim-cnis-file"]');
    const file = new File(['%PDF'], 'cnis.pdf', { type: 'application/pdf' });
    Object.defineProperty(input.element, 'files', { value: [file] });
    await input.trigger('change');
    await flushPromises();
    expect(LeadsAPI.uploadCnis).toHaveBeenCalledWith(7, file, 'F', {});
    expect(wrapper.find('[data-testid="sim-cnis-chip"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="sim-salario"]').exists()).toBe(false);
  });

  it('abre os ajustes de vínculos, busca o detalhe e reaplica com o PDF em memória', async () => {
    LeadsAPI.uploadCnis.mockResolvedValue({
      data: {
        ...cnisResumo,
        vinculos_detalhe: [
          { seq: 1, tipo: 'EMPREGO', origem: 'ACME' },
          { seq: 2, tipo: 'BENEFICIO', origem: 'Benefício 31' },
        ],
        parametros: {},
      },
    });
    const wrapper = mountSim();
    const input = wrapper.find('[data-testid="sim-cnis-file"]');
    const file = new File(['%PDF'], 'cnis.pdf', { type: 'application/pdf' });
    Object.defineProperty(input.element, 'files', { value: [file] });
    await input.trigger('change');
    await flushPromises();

    await wrapper
      .find('[data-testid="sim-cnis-ajustes-toggle"]')
      .trigger('click');
    expect(LeadsAPI.getCnis).not.toHaveBeenCalled(); // detalhe veio no upload
    await wrapper.find('[data-testid="sim-vinculo-excluir-2"]').setValue(true);
    await wrapper
      .find('[data-testid="sim-vinculo-mensalidade-2"]')
      .setValue('1286.57');
    await wrapper.find('[data-testid="sim-cnis-reaplicar"]').trigger('click');
    await flushPromises();
    expect(LeadsAPI.uploadCnis).toHaveBeenLastCalledWith(7, file, 'F', {
      excluirSeqs: '2',
      mensalidades: '{"2":"1286.57"}',
    });
  });

  it('depois de F5 busca o detalhe via GET e desabilita reaplicar sem o PDF', async () => {
    LeadsAPI.getCnis.mockResolvedValue({
      data: {
        ...cnisResumo,
        vinculos_detalhe: [{ seq: 1, tipo: 'EMPREGO', origem: 'ACME' }],
        parametros: { excluir_seqs: '1' },
      },
    });
    const wrapper = mountSim({ lead: { ...lead, cnis_resumo: cnisResumo } });
    await wrapper
      .find('[data-testid="sim-cnis-ajustes-toggle"]')
      .trigger('click');
    await flushPromises();
    expect(LeadsAPI.getCnis).toHaveBeenCalledWith(7);
    expect(
      wrapper.find('[data-testid="sim-vinculo-excluir-1"]').element.checked
    ).toBe(true);
    expect(
      wrapper.find('[data-testid="sim-cnis-reaplicar"]').element.disabled
    ).toBe(true);
    expect(wrapper.find('[data-testid="sim-cnis-refile"]').exists()).toBe(true);
  });

  it('pede a memória de cálculo sob demanda e renderiza a tabela', async () => {
    const comMemoria = {
      ...resultado,
      motor: {
        rmi: '1600.00',
        rmi_com_descartes: '1800.00',
        memoria_calculo: {
          salarios: [
            {
              competencia: '01/2024',
              salario: '3000.00',
              indice: '1.088517',
              corrigido: '3265.55',
            },
          ],
          soma: '3265.55',
          divisor: 1,
          media: '3265.55',
        },
      },
    };
    LeadsAPI.simulate.mockResolvedValue({ data: comMemoria });
    const wrapper = mountSim();
    await fillForm(wrapper);
    await wrapper.find('[data-testid="sim-run"]').trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-testid="sim-duas-medias"]').text()).toContain(
      'DUAS_MEDIAS'
    );
    await wrapper.find('[data-testid="sim-memoria-toggle"]').trigger('click');
    await flushPromises();
    expect(LeadsAPI.simulate).toHaveBeenLastCalledWith(
      7,
      expect.objectContaining({ memoria_calculo: true })
    );
    expect(wrapper.find('[data-testid="sim-memoria"]').text()).toContain(
      '01/2024'
    );
    expect(wrapper.find('[data-testid="sim-memoria-resumo"]').exists()).toBe(
      true
    );
  });

  it('remove o CNIS e volta pros campos manuais', async () => {
    LeadsAPI.deleteCnis.mockResolvedValue({});
    const wrapper = mountSim({ lead: { ...lead, cnis_resumo: cnisResumo } });
    await wrapper.find('[data-testid="sim-cnis-remove"]').trigger('click');
    await flushPromises();
    expect(LeadsAPI.deleteCnis).toHaveBeenCalledWith(7);
    expect(wrapper.find('[data-testid="sim-cnis-chip"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="sim-salario"]').exists()).toBe(true);
  });

  it('calcula o painel com vínculo manual e renderiza os cartões', async () => {
    LeadsAPI.painel.mockResolvedValue({
      data: {
        resumo: {
          idade: '57a, 10m e 23d',
          tempo_contribuicao: '34a, 11m e 3d',
          tempo_na_reforma: '28a, 7m e 15d',
          carencia: 425,
          media: '3651.92',
        },
        cartoes: [
          {
            id: 'idade_pre',
            titulo: 'Aposentadoria por idade',
            subtitulo: 'Pré-reforma. Aposentadoria. Idade.',
            elegivel: false,
            rmi: '3396.58',
            requisitos: [
              {
                nome: 'idade',
                atual: '51a, 3m e 5d',
                exigido: '65a',
                faltou: '13a, 8m e 25d',
              },
            ],
            previsao: '2033-08-08',
          },
          {
            id: 'invalidez_pre',
            titulo: 'Aposentadoria por invalidez',
            subtitulo: 'Pré-reforma.',
            elegivel: null,
            depende_de: 'incapacidade laborativa permanente',
            rmi: '4207.99',
            rmi_com_descartes: '4300.00',
            requisitos: [],
          },
        ],
        avisos: [],
      },
    });
    const wrapper = mountSim();
    await wrapper.find('[data-testid="sim-der"]').setValue('2026-06-30');
    await wrapper
      .find('[data-testid="sim-vinculo-extra-add"]')
      .trigger('click');
    const extra = wrapper.find('[data-testid="sim-vinculo-extra-0"]');
    await extra.find('input[type="date"]').setValue('1980-08-07');
    await extra.findAll('input[type="date"]')[1].setValue('1988-04-30');
    await wrapper.find('[data-testid="sim-painel-run"]').trigger('click');
    await flushPromises();
    expect(LeadsAPI.painel).toHaveBeenCalledWith(
      7,
      expect.objectContaining({
        der: '2026-06-30',
        vinculos_extras: [
          expect.objectContaining({ inicio: '1980-08-07', fim: '1988-04-30' }),
        ],
      })
    );
    expect(wrapper.find('[data-testid="sim-painel-resumo"]').exists()).toBe(
      true
    );
    const cartao = wrapper.find('[data-testid="sim-cartao-idade_pre"]');
    expect(cartao.text()).toContain('3.396,58');
    // $t mockado devolve a chave — presença = requisito faltante e previsão renderizados
    expect(cartao.text()).toContain('RAMON.SIMULADOR.PAINEL_FALTOU');
    expect(cartao.text()).toContain('RAMON.SIMULADOR.PAINEL_PREVISAO');
    expect(
      wrapper.find('[data-testid="sim-cartao-invalidez_pre"]').text()
    ).toContain('4.207,99');
  });

  it('com CNIS no caso, o painel calcula só com a DER', async () => {
    LeadsAPI.painel.mockResolvedValue({
      data: { resumo: { media: '1.00' }, cartoes: [], avisos: [] },
    });
    const wrapper = mountSim({ lead: { ...lead, cnis_resumo: cnisResumo } });
    expect(
      wrapper.find('[data-testid="sim-painel-run"]').element.disabled
    ).toBe(true);
    await wrapper.find('[data-testid="sim-der"]').setValue('2026-06-30');
    expect(
      wrapper.find('[data-testid="sim-painel-run"]').element.disabled
    ).toBe(false);
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
