import { shallowMount, flushPromises } from '@vue/test-utils';
import LeadsAPI from 'dashboard/api/leads';
import LeadElegibilidade from '../LeadElegibilidade.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));
vi.mock('dashboard/api/leads', () => ({
  default: { elegibilidade: vi.fn() },
}));

const lead = { id: 7 };
const der = '2026-06-30';

const mountEleg = (props = {}) =>
  shallowMount(LeadElegibilidade, {
    props: { lead, der, ...props },
    global: { mocks: { $t: k => k } },
  });

const doisCenarios = {
  qualidade: {
    cenarios: {
      sem_desemprego: { mantida: true, ate: null, fundamento: 'em atividade' },
      com_desemprego: {
        mantida: false,
        ate: '2026-08-15',
        fundamento: 'sem contribuição após o desligamento',
      },
    },
  },
  carencia: { total: 180, perda_qualidade_anterior: false, art_27a: null },
  lacunas: [],
  decisoes_pendentes: [
    {
      tipo: 'desemprego',
      inicio: '2026-01-01',
      fim: '2026-06-30',
      pergunta: 'O segurado recebeu seguro-desemprego nesse período?',
      efeito_por_resposta: {
        sim: 'período de graça amplia para 24 meses',
        nao: 'período de graça padrão de 12 meses',
      },
    },
  ],
  avisos: [],
};

const cenarioUnico = {
  qualidade: {
    cenarios: {
      unico: { mantida: true, ate: null, fundamento: 'em atividade' },
    },
  },
  carencia: { total: 180, art_27a: null },
  lacunas: [],
  decisoes_pendentes: [],
  avisos: [],
};

describe('LeadElegibilidade', () => {
  beforeEach(() => {
    LeadsAPI.elegibilidade.mockReset();
  });

  it('analisar renderiza 2 cenários + pendência', async () => {
    LeadsAPI.elegibilidade.mockResolvedValue({ data: doisCenarios });
    const wrapper = mountEleg();
    await wrapper.find('[data-testid="eleg-analisar"]').trigger('click');
    await flushPromises();

    expect(LeadsAPI.elegibilidade).toHaveBeenCalledWith(7, {
      der,
      decisoes: {},
    });
    expect(
      wrapper.find('[data-testid="eleg-cenario-sem-desemprego"]').exists()
    ).toBe(true);
    expect(
      wrapper.find('[data-testid="eleg-cenario-com-desemprego"]').exists()
    ).toBe(true);
    expect(wrapper.find('[data-testid="eleg-pendencia-0"]').text()).toContain(
      'O segurado recebeu seguro-desemprego nesse período?'
    );
  });

  it('clique em Sim re-chama com decisoes.desemprego=true e colapsa pra cenário único', async () => {
    LeadsAPI.elegibilidade.mockResolvedValueOnce({ data: doisCenarios });
    const wrapper = mountEleg();
    await wrapper.find('[data-testid="eleg-analisar"]').trigger('click');
    await flushPromises();

    LeadsAPI.elegibilidade.mockResolvedValueOnce({ data: cenarioUnico });
    await wrapper.find('[data-testid="eleg-pendencia-sim"]').trigger('click');
    await flushPromises();

    expect(LeadsAPI.elegibilidade).toHaveBeenLastCalledWith(7, {
      der,
      decisoes: { desemprego: true },
    });
    expect(wrapper.find('[data-testid="eleg-cenario-unico"]').exists()).toBe(
      true
    );
    expect(
      wrapper.find('[data-testid="eleg-cenario-sem-desemprego"]').exists()
    ).toBe(false);
  });

  it('erro de rede mostra erro+retry, não vazio', async () => {
    LeadsAPI.elegibilidade.mockRejectedValue(new Error('Network Error'));
    const wrapper = mountEleg();
    await wrapper.find('[data-testid="eleg-analisar"]').trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-testid="eleg-error"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="eleg-retry"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="eleg-cenarios"]').exists()).toBe(false);
  });

  it('simular chama com simular_lacunas e renderiza só cartões alterados', async () => {
    LeadsAPI.elegibilidade.mockResolvedValueOnce({
      data: {
        ...cenarioUnico,
        lacunas: [
          {
            inicio: '2020-01-01',
            fim: '2020-06-30',
            meses: 6,
            graca_cobriu: false,
            ganho_tempo_meses: 6,
            ganho_carencia: 6,
          },
        ],
      },
    });
    const wrapper = mountEleg();
    await wrapper.find('[data-testid="eleg-analisar"]').trigger('click');
    await flushPromises();

    LeadsAPI.elegibilidade.mockResolvedValueOnce({
      data: {
        ...cenarioUnico,
        simulacao: [
          {
            cenario: 'unico',
            cartoes: [
              {
                id: 'cartaoA',
                elegivel_antes: false,
                elegivel_depois: true,
                rmi_antes: '0',
                rmi_depois: '1500.00',
                previsao_antes: '2027-01-01',
                previsao_depois: '2026-07-01',
              },
              {
                id: 'cartaoB',
                elegivel_antes: true,
                elegivel_depois: true,
                rmi_antes: '2000.00',
                rmi_depois: '2000.00',
                previsao_antes: null,
                previsao_depois: null,
              },
            ],
            aviso: 'lacunas preenchidas mudam a RMI',
          },
        ],
      },
    });
    await wrapper.find('[data-testid="eleg-simular"]').trigger('click');
    await flushPromises();

    expect(LeadsAPI.elegibilidade).toHaveBeenLastCalledWith(7, {
      der,
      decisoes: {},
      simular_lacunas: true,
    });
    expect(
      wrapper.find('[data-testid="eleg-simulacao-cartao-cartaoA"]').exists()
    ).toBe(true);
    expect(
      wrapper.find('[data-testid="eleg-simulacao-cartao-cartaoB"]').exists()
    ).toBe(false);
  });
});
