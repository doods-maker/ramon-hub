import { shallowMount, flushPromises } from '@vue/test-utils';
import LeadsAPI from 'dashboard/api/leads';
import LeadPlanejamento from '../LeadPlanejamento.vue';

const tWithParams = (k, params) =>
  params ? `${k}:${Object.values(params).join(',')}` : k;
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: tWithParams }) }));
vi.mock('dashboard/api/leads', () => ({
  default: { planejamento: vi.fn(), planejamentoPdf: vi.fn() },
}));

global.URL.createObjectURL = vi.fn(() => 'blob:mock');
global.URL.revokeObjectURL = vi.fn();

const lead = { id: 13 };

const mountPlanejamento = (props = {}) =>
  shallowMount(LeadPlanejamento, {
    props: { lead, ...props },
    global: { mocks: { $t: tWithParams } },
  });

const resultado = {
  data_calculo: '2026-07-24',
  cenarios: [
    {
      nome: 'conservador',
      salario: '3000.00',
      aliquota: 20,
      observacao: 'contribuição mínima recomendada',
      resultados: [
        {
          regra: 'idade',
          titulo: 'Aposentadoria por idade',
          fecha_em: '2032-01-10',
          rmi_projetada: '2200.00',
          meses_contribuindo: 66,
          desembolso_total: '39600.00',
          payback_meses: 18,
        },
      ],
      regras_excluidas: [
        { regra: 'pontos', motivo: 'não atinge a pontuação mínima' },
      ],
      avisos: ['aviso do cenário conservador'],
    },
  ],
  decisoes_pendentes: [
    { tipo: 'cenario_manter', pergunta: 'Manter contribuição mínima até lá?' },
  ],
  avisos: ['aviso geral do planejamento'],
};

describe('LeadPlanejamento', () => {
  beforeEach(() => {
    LeadsAPI.planejamento.mockReset();
    LeadsAPI.planejamentoPdf.mockReset();
  });

  it('planejar renderiza cenários, resultados e regras excluídas', async () => {
    LeadsAPI.planejamento.mockResolvedValue({ data: resultado });
    const wrapper = mountPlanejamento();
    await wrapper
      .find('[data-testid="planejamento-planejar"]')
      .trigger('click');
    await flushPromises();

    expect(LeadsAPI.planejamento).toHaveBeenCalledWith(13, {});
    expect(
      wrapper.find('[data-testid="planejamento-cenario-0"]').text()
    ).toContain('Conservador');
    expect(
      wrapper.find('[data-testid="planejamento-cenario-0-resultado-0"]').text()
    ).toContain('Aposentadoria por idade');
    expect(
      wrapper.find('[data-testid="planejamento-cenario-0-excluidas"]').text()
    ).toContain('não atinge a pontuação mínima');
    expect(
      wrapper.find('[data-testid="planejamento-pendencias"]').text()
    ).toContain('Manter contribuição mínima até lá?');
    expect(
      wrapper.find('[data-testid="planejamento-avisos"]').text()
    ).toContain('aviso geral do planejamento');
  });

  it('baixa o PDF com responseType blob (mockado) e nome de arquivo do lead', async () => {
    LeadsAPI.planejamento.mockResolvedValue({ data: resultado });
    const pdfBlob = new Blob(['%PDF'], { type: 'application/pdf' });
    LeadsAPI.planejamentoPdf.mockResolvedValue({ data: pdfBlob });
    const wrapper = mountPlanejamento();
    await wrapper
      .find('[data-testid="planejamento-planejar"]')
      .trigger('click');
    await flushPromises();

    await wrapper.find('[data-testid="planejamento-pdf-run"]').trigger('click');
    await flushPromises();

    expect(LeadsAPI.planejamentoPdf).toHaveBeenCalledWith(13, {});
    expect(global.URL.createObjectURL).toHaveBeenCalledWith(pdfBlob);
  });

  it('erro do PDF vindo como blob mostra mensagem (não vazio); retry refaz a mesma ação', async () => {
    LeadsAPI.planejamento.mockResolvedValue({ data: resultado });
    LeadsAPI.planejamentoPdf.mockRejectedValueOnce({
      response: {
        status: 422,
        data: new Blob([JSON.stringify({ error: 'CNIS incompleto' })], {
          type: 'application/json',
        }),
      },
    });
    const wrapper = mountPlanejamento();
    await wrapper
      .find('[data-testid="planejamento-planejar"]')
      .trigger('click');
    await flushPromises();

    await wrapper.find('[data-testid="planejamento-pdf-run"]').trigger('click');
    await flushPromises();
    await new Promise(resolve => {
      setTimeout(resolve, 0);
    });
    await flushPromises();

    expect(wrapper.find('[data-testid="planejamento-error"]').text()).toContain(
      'CNIS incompleto'
    );
    expect(wrapper.find('[data-testid="planejamento-retry"]').exists()).toBe(
      true
    );

    const pdfBlob = new Blob(['%PDF'], { type: 'application/pdf' });
    LeadsAPI.planejamentoPdf.mockResolvedValueOnce({ data: pdfBlob });
    await wrapper.find('[data-testid="planejamento-retry"]').trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-testid="planejamento-error"]').exists()).toBe(
      false
    );
    expect(LeadsAPI.planejamentoPdf).toHaveBeenCalledTimes(2);
  });

  it('erro de rede ao planejar mostra erro+retry, não vazio', async () => {
    LeadsAPI.planejamento.mockRejectedValueOnce({
      response: { data: { error: 'motor indisponível' } },
    });
    const wrapper = mountPlanejamento();
    await wrapper
      .find('[data-testid="planejamento-planejar"]')
      .trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-testid="planejamento-error"]').text()).toContain(
      'motor indisponível'
    );
    expect(
      wrapper.find('[data-testid="planejamento-cenario-0"]').exists()
    ).toBe(false);

    LeadsAPI.planejamento.mockResolvedValueOnce({ data: resultado });
    await wrapper.find('[data-testid="planejamento-retry"]').trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-testid="planejamento-error"]').exists()).toBe(
      false
    );
    expect(
      wrapper.find('[data-testid="planejamento-cenario-0"]').exists()
    ).toBe(true);
  });
});
