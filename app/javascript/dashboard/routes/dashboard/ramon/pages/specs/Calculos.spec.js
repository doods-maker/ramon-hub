import { mount, flushPromises } from '@vue/test-utils';
import { reactive } from 'vue';
import Calculos from '../Calculos.vue';
import ContactAPI from 'dashboard/api/contacts';
import LeadsAPI from 'dashboard/api/leads';
import RamonCalculosAPI from 'dashboard/api/ramonCalculos';
import CalculosAPI from 'dashboard/api/calculos';

// Rota simulada: reativa pra que router.push (mockado) dispare o watch do
// componente, do mesmo jeito que a navegação real faria.
const routeParams = reactive({});
const push = vi.fn(({ params }) => {
  Object.keys(routeParams).forEach(key => delete routeParams[key]);
  Object.assign(routeParams, params);
});

vi.mock('vue-router', () => ({
  useRoute: () => ({ params: routeParams }),
  useRouter: () => ({ push }),
}));
vi.mock('dashboard/api/contacts', () => ({
  default: { search: vi.fn() },
}));
vi.mock('dashboard/api/leads', () => ({
  default: { get: vi.fn(), show: vi.fn() },
}));
vi.mock('dashboard/api/ramonCalculos', () => ({
  default: { advboxCustomers: vi.fn(), criarCaso: vi.fn(), rascunho: vi.fn() },
}));
vi.mock('dashboard/api/calculos', () => ({
  default: { historico: vi.fn(), reabrir: vi.fn(), delete: vi.fn() },
}));
// LeadSimulador tem specs próprios — aqui só confirmamos que recebeu o lead certo.
vi.mock('../../components/conversation/LeadSimulador.vue', () => ({
  default: {
    name: 'LeadSimulador',
    props: ['lead', 'inicial'],
    template: '<div data-testid="stub-simulador">{{ lead.id }}</div>',
  },
}));

const mountOptions = {
  global: {
    mocks: {
      $t: (key, params) => (params ? `${key} ${JSON.stringify(params)}` : key),
    },
  },
};

// A tela abre na calculadora (cálculo rápido); a busca de pessoa é o outro modo.
const mountBusca = async () => {
  const wrapper = mount(Calculos, mountOptions);
  await flushPromises();
  await wrapper.find('[data-testid="calculos-modo-busca"]').trigger('click');
  return wrapper;
};

const search = async (wrapper, term) => {
  await wrapper.find('[data-testid="pessoa-search"]').setValue(term);
  await new Promise(resolve => {
    setTimeout(resolve, 320); // debounce de 300ms
  });
  await flushPromises();
};

beforeEach(() => {
  Object.keys(routeParams).forEach(key => delete routeParams[key]);
  push.mockClear();
  ContactAPI.search.mockReset();
  LeadsAPI.get.mockReset();
  LeadsAPI.show.mockReset();
  RamonCalculosAPI.advboxCustomers.mockReset();
  RamonCalculosAPI.criarCaso.mockReset();
  RamonCalculosAPI.rascunho.mockReset();
  RamonCalculosAPI.rascunho.mockResolvedValue({
    data: { id: 77, name: 'Cálculo rápido' },
  });
  CalculosAPI.historico.mockReset();
  CalculosAPI.reabrir.mockReset();
  CalculosAPI.delete.mockReset();
  CalculosAPI.historico.mockResolvedValue({ data: { payload: [] } });
});

describe('Calculos.vue', () => {
  it('abre na calculadora, sem pedir nome', async () => {
    const wrapper = mount(Calculos, mountOptions);
    await flushPromises();

    expect(RamonCalculosAPI.rascunho).toHaveBeenCalledTimes(1);
    expect(wrapper.find('[data-testid="pessoa-search"]').exists()).toBe(false);
    const stub = wrapper.findComponent({ name: 'LeadSimulador' });
    expect(stub.props('lead').id).toBe(77);
  });

  it('histórico lista cálculo com data/hora e filtra por cliente', async () => {
    CalculosAPI.historico.mockResolvedValue({
      data: {
        payload: [
          {
            id: 5,
            tipo: 'painel',
            lead_id: 77,
            segurado_nome: 'Maria das Dores',
            der: '2026-03-10',
            created_at: '2026-07-27T14:32:00.000Z',
          },
        ],
      },
    });
    const wrapper = mount(Calculos, mountOptions);
    await flushPromises();

    await wrapper
      .find('[data-testid="calculos-historico-toggle"]')
      .trigger('click');
    await flushPromises();

    expect(CalculosAPI.historico).toHaveBeenCalledWith('');
    const item = wrapper.find('[data-testid="calculos-historico-item"]');
    expect(item.text()).toContain('Maria das Dores');
    expect(item.text()).toContain('HIST_LINHA_DER');

    await wrapper
      .find('[data-testid="calculos-historico-busca"]')
      .setValue('Maria');
    await new Promise(resolve => {
      setTimeout(resolve, 320); // debounce de 300ms
    });
    await flushPromises();
    expect(CalculosAPI.historico).toHaveBeenLastCalledWith('Maria');
  });

  it('reabrir cálculo do rascunho remonta o simulador com o estado salvo', async () => {
    CalculosAPI.historico.mockResolvedValue({
      data: {
        payload: [
          {
            id: 5,
            tipo: 'pensao',
            lead_id: 77,
            segurado_nome: 'Maria das Dores',
            created_at: '2026-07-27T14:32:00.000Z',
          },
        ],
      },
    });
    CalculosAPI.reabrir.mockResolvedValue({
      data: {
        lead_id: 77,
        tipo: 'pensao',
        params: { der: '2026-03-10' },
        cnis: { filename: 'cnis.pdf' },
      },
    });
    const wrapper = mount(Calculos, mountOptions);
    await flushPromises();
    await wrapper
      .find('[data-testid="calculos-historico-toggle"]')
      .trigger('click');
    await flushPromises();

    await wrapper
      .find('[data-testid="calculos-historico-item"]')
      .trigger('click');
    await flushPromises();

    expect(CalculosAPI.reabrir).toHaveBeenCalledWith(5);
    // mesmo lead do rascunho: fica na tela, sem navegar
    expect(push).not.toHaveBeenCalled();
    const stub = wrapper.findComponent({ name: 'LeadSimulador' });
    expect(stub.props('inicial').tipo).toBe('pensao');
    expect(stub.props('inicial').cnis.filename).toBe('cnis.pdf');
  });

  it('erro ao abrir a calculadora permite tentar de novo', async () => {
    RamonCalculosAPI.rascunho.mockRejectedValueOnce(new Error('down'));
    const wrapper = mount(Calculos, mountOptions);
    await flushPromises();

    expect(
      wrapper.find('[data-testid="calculos-rascunho-error"]').exists()
    ).toBe(true);
    await wrapper
      .find('[data-testid="calculos-rascunho-retry"]')
      .trigger('click');
    await flushPromises();

    expect(
      wrapper.findComponent({ name: 'LeadSimulador' }).props('lead').id
    ).toBe(77);
  });

  it('busca pessoa e, com 1 lead só, navega e renderiza o Simulador direto', async () => {
    ContactAPI.search.mockResolvedValue({
      data: {
        payload: [
          { id: 1, name: 'Maria das Dores', phone_number: '+5548999990000' },
        ],
      },
    });
    LeadsAPI.get.mockResolvedValue({
      data: { payload: [{ id: 9, name: 'Lead único' }] },
    });
    LeadsAPI.show.mockResolvedValue({
      data: {
        id: 9,
        name: 'Lead único',
        contact_name: 'Maria das Dores',
        thesis_name: 'Auxílio-acidente',
      },
    });

    const wrapper = await mountBusca();
    await search(wrapper, 'Maria');

    expect(wrapper.find('[data-testid="pessoa-result"]').text()).toContain(
      'Maria das Dores'
    );

    await wrapper.find('[data-testid="pessoa-result"]').trigger('click');
    await flushPromises();

    expect(LeadsAPI.get).toHaveBeenCalledWith({ contact_id: 1 });
    expect(push).toHaveBeenCalledWith({
      name: 'ramon_calculos_lead',
      params: { leadId: 9 },
    });

    await flushPromises();
    expect(LeadsAPI.show).toHaveBeenCalledWith(9);
    const stub = wrapper.findComponent({ name: 'LeadSimulador' });
    expect(stub.exists()).toBe(true);
    expect(stub.props('lead').id).toBe(9);
  });

  it('com mais de um lead, lista tese/data pra escolher antes de simular', async () => {
    ContactAPI.search.mockResolvedValue({
      data: { payload: [{ id: 2, name: 'João Pedro' }] },
    });
    LeadsAPI.get.mockResolvedValue({
      data: {
        payload: [
          {
            id: 10,
            thesis_name: 'Auxílio-doença',
            stage_entered_at: '2026-01-05',
          },
          {
            id: 11,
            thesis_name: 'Aposentadoria',
            stage_entered_at: '2026-03-10',
          },
        ],
      },
    });
    LeadsAPI.show.mockResolvedValue({
      data: { id: 11, name: 'Lead 11', contact_name: 'João Pedro' },
    });

    const wrapper = await mountBusca();
    await search(wrapper, 'João');
    await wrapper.find('[data-testid="pessoa-result"]').trigger('click');
    await flushPromises();

    expect(push).not.toHaveBeenCalled();
    const items = wrapper.findAll('[data-testid="calculos-lead-item"]');
    expect(items).toHaveLength(2);
    expect(items[1].text()).toContain('Aposentadoria');

    await items[1].trigger('click');
    expect(push).toHaveBeenCalledWith({
      name: 'ramon_calculos_lead',
      params: { leadId: 11 },
    });

    await flushPromises();
    const stub = wrapper.findComponent({ name: 'LeadSimulador' });
    expect(stub.props('lead').id).toBe(11);
  });

  it('sem lead pro contato, mostra estado vazio com orientação', async () => {
    ContactAPI.search.mockResolvedValue({
      data: { payload: [{ id: 3, name: 'Ana Beatriz' }] },
    });
    LeadsAPI.get.mockResolvedValue({ data: { payload: [] } });

    const wrapper = await mountBusca();
    await search(wrapper, 'Ana');
    await wrapper.find('[data-testid="pessoa-result"]').trigger('click');
    await flushPromises();

    expect(push).not.toHaveBeenCalled();
    const empty = wrapper.find('[data-testid="calculos-empty"]');
    expect(empty.exists()).toBe(true);
    expect(empty.text()).toContain('RAMON.CALCULOS.EMPTY_NO_LEAD');
    expect(empty.text()).toContain('Ana Beatriz');
  });

  it('busca no AdvBox só sob demanda e lista cadastros', async () => {
    ContactAPI.search.mockResolvedValue({ data: { payload: [] } });
    RamonCalculosAPI.advboxCustomers.mockResolvedValue({
      data: {
        payload: [
          { id: 7, name: 'José do AdvBox', identification: '52998224725' },
        ],
      },
    });

    const wrapper = await mountBusca();
    await search(wrapper, 'José');

    // Digitar não chama o AdvBox — só o clique no botão.
    expect(RamonCalculosAPI.advboxCustomers).not.toHaveBeenCalled();

    await wrapper.find('[data-testid="advbox-search"]').trigger('click');
    await flushPromises();

    expect(RamonCalculosAPI.advboxCustomers).toHaveBeenCalledTimes(1);
    expect(RamonCalculosAPI.advboxCustomers).toHaveBeenCalledWith('José');
    const result = wrapper.find('[data-testid="advbox-result"]');
    expect(result.text()).toContain('José do AdvBox');
    expect(result.text()).toContain('52998224725');
  });

  it('escolher cadastro do AdvBox cria caso e navega pro lead', async () => {
    ContactAPI.search.mockResolvedValue({ data: { payload: [] } });
    RamonCalculosAPI.advboxCustomers.mockResolvedValue({
      data: {
        payload: [
          {
            id: 7,
            name: 'José do AdvBox',
            identification: '52998224725',
            cellphone: '48999887766',
            birthdate: '1980-05-10',
            email: null,
          },
        ],
      },
    });
    RamonCalculosAPI.criarCaso.mockResolvedValue({
      data: { contact: { id: 4, name: 'José do AdvBox' }, leads: [{ id: 33 }] },
    });
    LeadsAPI.show.mockResolvedValue({
      data: { id: 33, name: 'José do AdvBox', contact_name: 'José do AdvBox' },
    });

    const wrapper = await mountBusca();
    await search(wrapper, 'José');
    await wrapper.find('[data-testid="advbox-search"]').trigger('click');
    await flushPromises();
    await wrapper.find('[data-testid="advbox-result"]').trigger('click');
    await flushPromises();

    expect(RamonCalculosAPI.criarCaso).toHaveBeenCalledWith({
      nome: 'José do AdvBox',
      cpf: '52998224725',
      telefone: '48999887766',
      nascimento: '1980-05-10',
      email: null,
    });
    expect(push).toHaveBeenCalledWith({
      name: 'ramon_calculos_lead',
      params: { leadId: 33 },
    });
  });

  it('contato do hub sem lead ganha botão de criar caso de cálculo', async () => {
    ContactAPI.search.mockResolvedValue({
      data: { payload: [{ id: 3, name: 'Ana Beatriz' }] },
    });
    LeadsAPI.get.mockResolvedValue({ data: { payload: [] } });
    RamonCalculosAPI.criarCaso.mockResolvedValue({
      data: { contact: { id: 3, name: 'Ana Beatriz' }, leads: [{ id: 44 }] },
    });
    LeadsAPI.show.mockResolvedValue({
      data: { id: 44, name: 'Ana Beatriz', contact_name: 'Ana Beatriz' },
    });

    const wrapper = await mountBusca();
    await search(wrapper, 'Ana');
    await wrapper.find('[data-testid="pessoa-result"]').trigger('click');
    await flushPromises();

    await wrapper.find('[data-testid="create-case"]').trigger('click');
    await flushPromises();

    expect(RamonCalculosAPI.criarCaso).toHaveBeenCalledWith({ contact_id: 3 });
    expect(push).toHaveBeenCalledWith({
      name: 'ramon_calculos_lead',
      params: { leadId: 44 },
    });
  });

  it('erro do AdvBox mostra mensagem e permite tentar de novo', async () => {
    ContactAPI.search.mockResolvedValue({ data: { payload: [] } });
    RamonCalculosAPI.advboxCustomers.mockRejectedValueOnce(new Error('down'));

    const wrapper = await mountBusca();
    await search(wrapper, 'José');
    await wrapper.find('[data-testid="advbox-search"]').trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-testid="advbox-error"]').exists()).toBe(true);

    RamonCalculosAPI.advboxCustomers.mockResolvedValueOnce({
      data: { payload: [] },
    });
    await wrapper.find('[data-testid="advbox-search"]').trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-testid="advbox-error"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="advbox-empty"]').exists()).toBe(true);
  });
});
