import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import Clientes from '../Clientes.vue';

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
      leads: {
        namespaced: true,
        getters: {
          getLeads: () => leads,
          getFilters: () => ({ q: '', thesisId: null, leadStageId: null }),
          getUIFlags: () => ({ isFetching: false }),
        },
      },
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
    global: { plugins: [store], mocks: { $t: k => k } },
  });
};

describe('Clientes.vue', () => {
  beforeEach(() => {
    dispatch.mockClear();
    routerPush.mockClear();
  });

  it('carrega leads, etapas, teses e agentes no mount', () => {
    mountPage();
    expect(dispatch).toHaveBeenCalledWith('leads/loadFilters');
    expect(dispatch).toHaveBeenCalledWith('leadConfig/get');
    expect(dispatch).toHaveBeenCalledWith('theses/get');
    expect(dispatch).toHaveBeenCalledWith('agents/get');
  });

  it('lista em ordem alfabética com etapa, tese, responsável e telefone', () => {
    const rows = mountPage().findAll('[data-testid="cliente-row"]');
    expect(rows).toHaveLength(2);
    expect(rows[0].text()).toContain('Ana Souza');
    expect(rows[0].text()).toContain('Caio');
    expect(rows[1].text()).toContain('Em qualificação');
    expect(rows[1].text()).toContain('Auxílio-acidente');
    expect(rows[1].text()).toContain('Sara');
    expect(rows[1].text()).toContain('+5547996342210');
    expect(rows[1].text()).toContain('RAMON.HOJE.DIAS');
  });

  it('busca chama a action com q depois do debounce', async () => {
    vi.useFakeTimers();
    const wrapper = mountPage();
    await wrapper.find('[data-testid="clientes-busca"]').setValue('joao');
    expect(dispatch).not.toHaveBeenCalledWith('leads/setFilters', {
      q: 'joao',
    });
    vi.advanceTimersByTime(300);
    expect(dispatch).toHaveBeenCalledWith('leads/setFilters', { q: 'joao' });
    vi.useRealTimers();
  });

  it('clique na linha abre a ficha', async () => {
    const wrapper = mountPage();
    await wrapper.findAll('[data-testid="cliente-row"]')[1].trigger('click');
    expect(routerPush).toHaveBeenCalledWith({
      name: 'ramon_lead_dossie',
      params: { leadId: 1 },
    });
  });
});
