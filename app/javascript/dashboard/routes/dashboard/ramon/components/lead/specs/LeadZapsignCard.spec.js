import { mount, flushPromises } from '@vue/test-utils';
import LeadZapsignCard from '../LeadZapsignCard.vue';
import LeadsAPI from 'dashboard/api/leads';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/leads', () => ({
  default: { createZapsign: vi.fn() },
}));

const eligibleLead = {
  id: 9,
  thesis_name: 'Auxílio-acidente',
  contact_cpf: '05231877490',
};

const mountCard = lead =>
  mount(LeadZapsignCard, {
    props: { lead },
    global: { mocks: { $t: k => k } },
  });

describe('LeadZapsignCard', () => {
  beforeEach(() => vi.clearAllMocks());

  it('não renderiza nada quando a tese não é elegível', () => {
    const wrapper = mountCard({ id: 9, thesis_name: 'Aposentadoria' });
    expect(wrapper.find('[data-testid="zapsign-card"]').exists()).toBe(false);
  });

  it('desabilita Gerar e oferece Completar dados quando falta CPF', async () => {
    const wrapper = mountCard({ ...eligibleLead, contact_cpf: null });
    expect(
      wrapper.find('[data-testid="zapsign-generate"]').attributes('disabled')
    ).toBeDefined();
    expect(wrapper.find('[data-testid="zapsign-missing"]').exists()).toBe(true);
    await wrapper
      .find('[data-testid="zapsign-complete-data"]')
      .trigger('click');
    expect(wrapper.emitted('completeData')).toBeTruthy();
  });

  it('gera o contrato e mostra o link no mesmo cartão', async () => {
    LeadsAPI.createZapsign.mockResolvedValue({
      data: { sign_url: 'https://zapsign/abc', faltando: [] },
    });
    const wrapper = mountCard(eligibleLead);
    await wrapper.find('[data-testid="zapsign-generate"]').trigger('click');
    await flushPromises();
    expect(LeadsAPI.createZapsign).toHaveBeenCalledWith(9);
    const link = wrapper.find('[data-testid="zapsign-link"]');
    expect(link.exists()).toBe(true);
    expect(link.attributes('href')).toBe('https://zapsign/abc');
    expect(wrapper.find('[data-testid="zapsign-copy"]').exists()).toBe(true);
    // não há mais botão de gerar — guard contra 2º contrato
    expect(wrapper.find('[data-testid="zapsign-generate"]').exists()).toBe(
      false
    );
  });

  it('lista o que faltou (sem chaves do template) após gerar com lacunas', () => {
    const wrapper = mountCard({
      ...eligibleLead,
      custom_attributes: {
        zapsign: {
          sign_url: 'https://zapsign/abc',
          faltando: ['{{CPF}}', '{{estado civil}}'],
        },
      },
    });
    // t mockado devolve a chave crua — o contador {count} fica fora do assert
    expect(wrapper.find('[data-testid="zapsign-missing"]').exists()).toBe(true);
    expect(wrapper.text()).toContain('CPF, estado civil');
    expect(wrapper.find('[data-testid="zapsign-complete-data"]').exists()).toBe(
      true
    );
  });

  it('usa o zapsign persistido no lead quando já existe', () => {
    const wrapper = mountCard({
      ...eligibleLead,
      custom_attributes: {
        zapsign: { sign_url: 'https://zapsign/persistido', faltando: [] },
      },
    });
    expect(
      wrapper.find('[data-testid="zapsign-link"]').attributes('href')
    ).toBe('https://zapsign/persistido');
  });
});
