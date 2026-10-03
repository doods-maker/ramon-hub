import { mount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import LeadsAPI from 'dashboard/api/leads';
import Clientes from '../Clientes.vue';

vi.mock('dashboard/api/leads', () => ({ default: { get: vi.fn() } }));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (k, v) => (v ? `${k} ${JSON.stringify(v)}` : k),
  }),
}));

const routerPush = vi.fn();
vi.mock('vue-router', () => ({ useRouter: () => ({ push: routerPush }) }));

const dispatch = vi.fn();
const leads = [
  {
    id: 1,
    name: 'João Pedro Martins',
    lead_stage_id: 2,
    thesis_name: 'Auxílio-acidente',
    sdr_name: 'Sara',
    contact_phone: '+5547996342210',
    stage_entered_at: new Date(Date.now() - 3 * 86400000).toISOString(),
  },
  { id: 2, name: 'Ana Souza', lead_stage_id: 1, closer_name: 'Caio' },
];

const mountPage = () => {
  const store = createStore({
    modules: {
      leadConfig: {
        namespaced: true,
        getters: {
          getStages: () => [
            { id: 1, name: 'Novo', color: '#475569' },
            { id: 2, name: 'Em qualificação', color: '#0369A1' },
          ],
        },
      },
      theses: { namespaced: true, getters: { getTheses: () => [] } },
      agents: { namespaced: true, getters: { getAgents: () => [] } },
    },
  });
  store.dispatch = dispatch;
  return mount(Clientes, {
    global: {
      plugins: [store],
      mocks: { $t: k => k },
      stubs: { RouterLink: { template: '<a><slot /></a>' } },
    },
  });
};

describe('Clientes.vue', () => {
  beforeEach(() => {
    dispatch.mockClear();
    routerPush.mockClear();
    localStorage.clear();
    LeadsAPI.get.mockReset();
    LeadsAPI.get.mockResolvedValue({ data: { payload: leads } });
  });

  it('carrega leads (API própria), etapas, teses e agentes no mount', () => {
    mountPage();
    expect(LeadsAPI.get).toHaveBeenCalledWith({});
    expect(dispatch).toHaveBeenCalledWith('leadConfig/get');
    expect(dispatch).toHaveBeenCalledWith('theses/get');
    expect(dispatch).toHaveBeenCalledWith('agents/get');
  });

  it('lista em ordem alfabética com etapa, tese, responsável e telefone', async () => {
    const wrapper = mountPage();
    await flushPromises();
    const rows = wrapper.findAll('[data-testid="cliente-row"]');
    expect(rows).toHaveLength(2);
    expect(rows[0].text()).toContain('Ana Souza');
    expect(rows[0].text()).toContain('Caio');
    expect(rows[1].text()).toContain('Em qualificação');
    expect(rows[1].text()).toContain('Auxílio-acidente');
    expect(rows[1].text()).toContain('Sara');
    expect(rows[1].text()).toContain('+5547996342210');
    expect(rows[1].text()).toContain('RAMON.HOJE.DIAS');
  });

  it('busca com debounce usa filtros próprios, sem tocar no funil', async () => {
    vi.useFakeTimers();
    const wrapper = mountPage();
    await wrapper.find('[data-testid="clientes-busca"]').setValue('joao');
    vi.advanceTimersByTime(299);
    expect(LeadsAPI.get).not.toHaveBeenCalledWith({ q: 'joao' });
    vi.advanceTimersByTime(1);
    expect(LeadsAPI.get).toHaveBeenCalledWith({ q: 'joao' });
    expect(dispatch).not.toHaveBeenCalledWith(
      'leads/setFilters',
      expect.anything()
    );
    expect(JSON.parse(localStorage.getItem('ramon_clientes_filtros')).q).toBe(
      'joao'
    );
    expect(localStorage.getItem('ramon_lead_filters')).toBeNull();
    vi.useRealTimers();
  });

  it('o campo de busca reflete o q salvo depois do load', () => {
    localStorage.setItem(
      'ramon_clientes_filtros',
      JSON.stringify({ q: 'ana', thesisId: 4 })
    );
    const wrapper = mountPage();
    expect(wrapper.find('[data-testid="clientes-busca"]').element.value).toBe(
      'ana'
    );
    expect(LeadsAPI.get).toHaveBeenCalledWith({ q: 'ana', thesis_id: 4 });
  });

  it('clique na linha abre a ficha', async () => {
    const wrapper = mountPage();
    await flushPromises();
    await wrapper.findAll('[data-testid="cliente-row"]')[1].trigger('click');
    expect(routerPush).toHaveBeenCalledWith({
      name: 'ramon_lead_dossie',
      params: { leadId: 1 },
    });
  });
});
