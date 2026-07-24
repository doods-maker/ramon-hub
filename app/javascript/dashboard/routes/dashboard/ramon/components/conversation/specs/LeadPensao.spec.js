import { shallowMount, flushPromises } from '@vue/test-utils';
import LeadsAPI from 'dashboard/api/leads';
import LeadPensao from '../LeadPensao.vue';

const tWithParams = (k, params) =>
  params ? `${k}:${Object.values(params).join(',')}` : k;
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: tWithParams }) }));
vi.mock('dashboard/api/leads', () => ({
  default: { pensao: vi.fn() },
}));

const lead = { id: 9 };

const mountPensao = (props = {}) =>
  shallowMount(LeadPensao, {
    props: { lead, ...props },
    global: { mocks: { $t: tWithParams } },
  });

const resultadoComQuotas = {
  qualidade_falecido: {
    cenarios: {
      unico: {
        mantida: true,
        ate: '2027-06-15',
        fundamento: 'em atividade no óbito',
      },
    },
  },
  direito_adquirido: false,
  base: { valor: '2000.00', origem: 'média dos 80% maiores salários' },
  percentual: 100,
  rmi: '2000.00',
  quotas: [
    {
      tipo: 'cônjuge',
      quota_pct: 50,
      cessa_em: {
        uniao_menor_2_anos: '2027-01-01',
        uniao_2_anos_ou_mais: null,
      },
      fundamento: 'Lei 13.135/2015',
      avisos: [],
    },
    {
      tipo: 'filho',
      quota_pct: 50,
      cessa_em: '2040-05-10',
      fundamento: 'até completar 21 anos',
      avisos: ['confirmar invalidez para prorrogação'],
    },
  ],
  decisoes_pendentes: [
    {
      tipo: 'uniao_2_anos',
      pergunta: 'A união estável durou 2 anos ou mais até o óbito?',
      efeito_por_resposta: { sim: 'quota vitalícia', nao: 'quota temporária' },
    },
  ],
  avisos: ['confirme os dependentes com o segurado'],
};

describe('LeadPensao', () => {
  beforeEach(() => {
    LeadsAPI.pensao.mockReset();
  });

  it('mostra o aviso de CNIS do falecido', () => {
    const wrapper = mountPensao();
    expect(
      wrapper.find('[data-testid="pensao-aviso-cnis-falecido"]').exists()
    ).toBe(true);
  });

  it('calcular renderiza quotas (incluindo cessa_em como dict)', async () => {
    LeadsAPI.pensao.mockResolvedValue({ data: resultadoComQuotas });
    const wrapper = mountPensao();
    await wrapper
      .find('[data-testid="pensao-data-obito"]')
      .setValue('2026-01-10');
    await wrapper.find('[data-testid="pensao-calcular"]').trigger('click');
    await flushPromises();

    expect(LeadsAPI.pensao).toHaveBeenCalledWith(9, {
      data_obito: '2026-01-10',
      dependentes: [{ tipo: 'conjuge', invalido: false }],
      decisoes: {},
    });
    expect(wrapper.find('[data-testid="pensao-quotas"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="pensao-quota-0"]').exists()).toBe(true);
    expect(
      wrapper.find('[data-testid="pensao-quota-cessa-dict-0"]').exists()
    ).toBe(true);
    expect(
      wrapper.find('[data-testid="pensao-quota-cessa-dict-0"]').text()
    ).toContain('RAMON.SIMULADOR.PENSAO_CESSA_VITALICIA');
    expect(wrapper.find('[data-testid="pensao-quota-1"]').text()).toContain(
      '2040-05-10'.split('-').reverse().join('/')
    );
    expect(
      wrapper.find('[data-testid="pensao-cenario-unico"]').text()
    ).toContain('2027-06-15'.split('-').reverse().join('/'));
    expect(wrapper.find('[data-testid="pensao-pendencia-0"]').text()).toContain(
      'quota vitalícia'
    );
    expect(wrapper.find('[data-testid="pensao-pendencia-0"]').text()).toContain(
      'quota temporária'
    );
  });

  it('clique em "Não" na pendência de união re-chama com decisoes.uniao_2_anos=false explícito', async () => {
    LeadsAPI.pensao.mockResolvedValueOnce({ data: resultadoComQuotas });
    const wrapper = mountPensao();
    await wrapper
      .find('[data-testid="pensao-data-obito"]')
      .setValue('2026-01-10');
    await wrapper.find('[data-testid="pensao-calcular"]').trigger('click');
    await flushPromises();

    LeadsAPI.pensao.mockResolvedValueOnce({
      data: { ...resultadoComQuotas, decisoes_pendentes: [] },
    });
    await wrapper.find('[data-testid="pensao-pendencia-nao"]').trigger('click');
    await flushPromises();

    expect(LeadsAPI.pensao).toHaveBeenLastCalledWith(9, {
      data_obito: '2026-01-10',
      dependentes: [{ tipo: 'conjuge', invalido: false }],
      decisoes: { uniao_2_anos: false },
    });
  });

  it('erro de rede mostra erro+retry, não vazio; retry refaz a chamada', async () => {
    LeadsAPI.pensao.mockRejectedValueOnce({
      response: {
        data: { error: 'dependentes obrigatório — informe ao menos 1' },
      },
    });
    const wrapper = mountPensao();
    await wrapper
      .find('[data-testid="pensao-data-obito"]')
      .setValue('2026-01-10');
    await wrapper.find('[data-testid="pensao-calcular"]').trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-testid="pensao-error"]').text()).toContain(
      'dependentes obrigatório — informe ao menos 1'
    );
    expect(wrapper.find('[data-testid="pensao-retry"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="pensao-quotas"]').exists()).toBe(false);

    LeadsAPI.pensao.mockResolvedValueOnce({ data: resultadoComQuotas });
    await wrapper.find('[data-testid="pensao-retry"]').trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-testid="pensao-error"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="pensao-quotas"]').exists()).toBe(true);
  });

  it('adiciona e remove dependentes dinamicamente', async () => {
    const wrapper = mountPensao();
    expect(wrapper.find('[data-testid="pensao-dependente-0"]').exists()).toBe(
      true
    );
    await wrapper
      .find('[data-testid="pensao-dependente-add"]')
      .trigger('click');
    expect(wrapper.find('[data-testid="pensao-dependente-1"]').exists()).toBe(
      true
    );
    await wrapper
      .find('[data-testid="pensao-dependente-remover-1"]')
      .trigger('click');
    expect(wrapper.find('[data-testid="pensao-dependente-1"]').exists()).toBe(
      false
    );
  });

  it('qualidade dispensada (string) renderiza sem cenários', async () => {
    LeadsAPI.pensao.mockResolvedValue({
      data: { ...resultadoComQuotas, qualidade_falecido: 'dispensada' },
    });
    const wrapper = mountPensao();
    await wrapper
      .find('[data-testid="pensao-data-obito"]')
      .setValue('2026-01-10');
    await wrapper.find('[data-testid="pensao-calcular"]').trigger('click');
    await flushPromises();

    expect(
      wrapper.find('[data-testid="pensao-qualidade-dispensada"]').exists()
    ).toBe(true);
    expect(wrapper.find('[data-testid="pensao-cenarios"]').exists()).toBe(
      false
    );
  });
});
