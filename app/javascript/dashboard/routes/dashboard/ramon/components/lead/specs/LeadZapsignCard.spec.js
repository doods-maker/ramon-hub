import { mount, flushPromises } from '@vue/test-utils';
import LeadZapsignCard from '../LeadZapsignCard.vue';
import LeadsAPI from 'dashboard/api/leads';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/leads', () => ({
  default: {
    createZapsign: vi.fn(),
    zapsignTemplates: vi.fn(),
    zapsignPreview: vi.fn(),
    saveZapsignDados: vi.fn(),
    zapsignCep: vi.fn(),
  },
}));

const TEMPLATES = [
  { token: 't1', name: 'Aux. Acidente' },
  { token: 't2', name: 'Aposentadoria' },
];

const eligibleLead = {
  id: 9,
  thesis_name: 'Auxílio-acidente',
  contact_cpf: '05231877490',
};

const mountCard = async lead => {
  const wrapper = mount(LeadZapsignCard, {
    props: { lead },
    global: { mocks: { $t: k => k } },
  });
  await flushPromises();
  return wrapper;
};

describe('LeadZapsignCard', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    LeadsAPI.zapsignTemplates.mockResolvedValue({ data: TEMPLATES });
    LeadsAPI.zapsignPreview.mockResolvedValue({
      data: { faltando: [], dados: {} },
    });
  });

  it('aparece mesmo sem tese de acidente', async () => {
    const wrapper = await mountCard({ id: 9, thesis_name: 'Aposentadoria' });
    expect(wrapper.find('[data-testid="zapsign-card"]').exists()).toBe(true);
  });

  it('lista os modelos e pré-seleciona o que casa com a tese', async () => {
    const wrapper = await mountCard(eligibleLead);
    const select = wrapper.find('[data-testid="zapsign-template"]');
    expect(select.findAll('option')).toHaveLength(2);
    expect(select.element.value).toBe('t1');
  });

  // ordem invertida de propósito: se a pré-seleção caísse no fallback list[0],
  // viria 't2' — só casa 't1' quem compara "acidente" com "Aux. Acidente"
  it('casa a tese pelo acento/palavra certa, não pela ordem da lista', async () => {
    LeadsAPI.zapsignTemplates.mockResolvedValue({
      data: [...TEMPLATES].reverse(),
    });
    const wrapper = await mountCard(eligibleLead);
    expect(wrapper.find('[data-testid="zapsign-template"]').element.value).toBe(
      't1'
    );
  });

  it('recalcula o modelo ao trocar de lead', async () => {
    const wrapper = await mountCard(eligibleLead);
    const sel = () => wrapper.find('[data-testid="zapsign-template"]').element;
    expect(sel().value).toBe('t1');
    await wrapper.setProps({
      lead: { ...eligibleLead, id: 10, thesis_name: 'Aposentadoria por idade' },
    });
    await flushPromises();
    expect(sel().value).toBe('t2');
  });

  it('gera com o modelo escolhido', async () => {
    LeadsAPI.createZapsign.mockResolvedValue({
      data: { sign_url: 'https://zapsign/abc', faltando: [] },
    });
    const wrapper = await mountCard(eligibleLead);
    await wrapper.find('[data-testid="zapsign-template"]').setValue('t2');
    await wrapper.find('[data-testid="zapsign-generate"]').trigger('click');
    await flushPromises();
    expect(LeadsAPI.createZapsign).toHaveBeenCalledWith(9, 't2', false);
  });

  it('avisa quando não consegue carregar os modelos', async () => {
    LeadsAPI.zapsignTemplates.mockRejectedValue(new Error('boom'));
    const wrapper = await mountCard(eligibleLead);
    expect(
      wrapper.find('[data-testid="zapsign-template"]').attributes('disabled')
    ).toBeDefined();
    expect(
      wrapper.find('[data-testid="zapsign-generate"]').attributes('disabled')
    ).toBeDefined();
  });

  it('lista o que vai em branco pela prévia do backend e deixa gerar mesmo assim', async () => {
    LeadsAPI.zapsignPreview.mockResolvedValue({
      data: { faltando: ['{{CPF}}', '{{número}}'], dados: {} },
    });
    const wrapper = await mountCard(eligibleLead);
    expect(LeadsAPI.zapsignPreview).toHaveBeenCalledWith(9);
    expect(wrapper.find('[data-testid="zapsign-blanks"]').text()).toContain(
      'CPF, número'
    );
    expect(
      wrapper.find('[data-testid="zapsign-generate"]').attributes('disabled')
    ).toBeUndefined();
    // CPF não está no formulário do cartão: leva pros dados do contato
    await wrapper
      .find('[data-testid="zapsign-complete-data"]')
      .trigger('click');
    expect(wrapper.emitted('completeData')).toBeTruthy();
  });

  it('CEP com 8 dígitos preenche o endereço e salvar grava no contato', async () => {
    LeadsAPI.zapsignCep.mockResolvedValue({
      data: {
        cep: '88701000',
        rua: 'Rua A',
        bairro: 'Centro',
        cidade: 'Tubarão',
        uf: 'SC',
      },
    });
    LeadsAPI.saveZapsignDados.mockResolvedValue({
      data: { faltando: [], dados: {} },
    });
    const wrapper = await mountCard(eligibleLead);
    await wrapper.find('[data-testid="zapsign-cep"]').setValue('88701-000');
    await flushPromises();
    expect(LeadsAPI.zapsignCep).toHaveBeenCalledWith('88701000');
    await wrapper.find('[data-testid="zapsign-form"]').trigger('submit');
    await flushPromises();
    expect(LeadsAPI.saveZapsignDados).toHaveBeenCalledWith(
      9,
      expect.objectContaining({
        endereco: expect.objectContaining({
          cep: '88701000',
          rua: 'Rua A',
          cidade: 'Tubarão',
        }),
      })
    );
  });

  it('gerar com edição não salva grava os dados antes', async () => {
    LeadsAPI.saveZapsignDados.mockResolvedValue({
      data: { faltando: [], dados: { profissao: 'soldador' } },
    });
    LeadsAPI.createZapsign.mockResolvedValue({
      data: { sign_url: 'https://zapsign/abc', faltando: [] },
    });
    const wrapper = await mountCard(eligibleLead);
    const inputs = wrapper.findAll('[data-testid="zapsign-form"] input');
    await inputs[inputs.length - 2].setValue('soldador');
    await wrapper.find('[data-testid="zapsign-generate"]').trigger('click');
    await flushPromises();
    expect(LeadsAPI.saveZapsignDados).toHaveBeenCalled();
    expect(LeadsAPI.createZapsign).toHaveBeenCalled();
  });

  it('gera o contrato e mostra o link no mesmo cartão', async () => {
    LeadsAPI.createZapsign.mockResolvedValue({
      data: { sign_url: 'https://zapsign/abc', faltando: [] },
    });
    const wrapper = await mountCard(eligibleLead);
    await wrapper.find('[data-testid="zapsign-generate"]').trigger('click');
    await flushPromises();
    expect(LeadsAPI.createZapsign).toHaveBeenCalledWith(9, 't1', false);
    const link = wrapper.find('[data-testid="zapsign-link"]');
    expect(link.exists()).toBe(true);
    expect(link.attributes('href')).toBe('https://zapsign/abc');
    expect(wrapper.find('[data-testid="zapsign-copy"]').exists()).toBe(true);
    // não há mais botão de gerar — só o "Gerar de novo", com confirmação
    expect(wrapper.find('[data-testid="zapsign-generate"]').exists()).toBe(
      false
    );
    expect(wrapper.find('[data-testid="zapsign-regenerate"]').exists()).toBe(
      true
    );
  });

  it('lista o que faltou (sem chaves do template) após gerar com lacunas', async () => {
    const wrapper = await mountCard({
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

  it('usa o zapsign persistido no lead quando já existe', async () => {
    const wrapper = await mountCard({
      ...eligibleLead,
      custom_attributes: {
        zapsign: { sign_url: 'https://zapsign/persistido', faltando: [] },
      },
    });
    expect(
      wrapper.find('[data-testid="zapsign-link"]').attributes('href')
    ).toBe('https://zapsign/persistido');
  });

  it('Gerar de novo confirma e manda regenerar (o backend cancela o anterior)', async () => {
    LeadsAPI.createZapsign.mockResolvedValue({
      data: {
        doc_token: 'novo',
        sign_url: 'https://zapsign/novo',
        faltando: [],
      },
    });
    const wrapper = await mountCard({
      ...eligibleLead,
      custom_attributes: {
        zapsign: { doc_token: 'velho', sign_url: 'https://zapsign/velho' },
      },
    });
    await wrapper.find('[data-testid="zapsign-regenerate"]').trigger('click');
    expect(wrapper.find('[data-testid="zapsign-form"]').exists()).toBe(true);
    await wrapper.find('[data-testid="zapsign-generate"]').trigger('click');
    // nada sai sem confirmar na janela
    expect(LeadsAPI.createZapsign).not.toHaveBeenCalled();
    await wrapper
      .find('[data-testid="confirm-modal-confirm"]')
      .trigger('click');
    await flushPromises();
    expect(LeadsAPI.createZapsign).toHaveBeenCalledWith(9, 't1', true);
    expect(
      wrapper.find('[data-testid="zapsign-link"]').attributes('href')
    ).toBe('https://zapsign/novo');
  });

  it('doc cancelado: mostra o aviso e gera de novo sem janela', async () => {
    LeadsAPI.createZapsign.mockResolvedValue({
      data: { doc_token: 'novo', sign_url: 'https://zapsign/novo' },
    });
    const wrapper = await mountCard({
      ...eligibleLead,
      custom_attributes: {
        zapsign: {
          doc_token: 'velho',
          sign_url: 'https://zapsign/velho',
          status: 'cancelado',
        },
      },
    });
    expect(wrapper.find('[data-testid="zapsign-cancelled"]').exists()).toBe(
      true
    );
    await wrapper.find('[data-testid="zapsign-generate"]').trigger('click');
    await flushPromises();
    expect(LeadsAPI.createZapsign).toHaveBeenCalledWith(9, 't1', true);
  });

  it('assinado: selo com a data e sem "Gerar de novo"', async () => {
    const wrapper = await mountCard({
      ...eligibleLead,
      custom_attributes: {
        zapsign: {
          doc_token: 'd',
          sign_url: 'https://zapsign/d',
          status: 'signed',
          assinado_em: '2026-10-03T14:00:00Z',
        },
      },
    });
    expect(wrapper.find('[data-testid="zapsign-seal"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="zapsign-regenerate"]').exists()).toBe(
      false
    );
    expect(wrapper.find('[data-testid="zapsign-link"]').exists()).toBe(true);
  });

  it('recusado pelo cliente: selo ruby e volta o formulário pra gerar de novo', async () => {
    const wrapper = await mountCard({
      ...eligibleLead,
      custom_attributes: {
        zapsign: { doc_token: 'd', sign_url: 'https://x', status: 'refused' },
      },
    });
    expect(wrapper.find('[data-testid="zapsign-seal"]').classes()).toContain(
      'text-n-ruby-11'
    );
    expect(wrapper.find('[data-testid="zapsign-form"]').exists()).toBe(true);
  });
});
