import { mount } from '@vue/test-utils';
import FilterChips from '../FilterChips.vue';

const translate = (key, vars) =>
  vars ? `${key} ${JSON.stringify(vars)}` : key;

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: translate }),
}));

const stubStore = {
  getters: {
    'leadConfig/getBenefitTypes': [{ id: 1, name: 'BPC' }],
    'leadConfig/getPriorities': [],
    'leadConfig/getChannels': [{ key: 'whatsapp', label: 'WhatsApp' }],
    'leadConfig/getStages': [
      { id: 1, name: 'Novo', probability: 50 },
      { id: 2, name: 'Perdido', probability: 0 },
    ],
    'agents/getAgents': [{ id: 3, name: 'Eduardo' }],
    'leads/getLeads': [
      { id: 10, lead_stage_id: 1, value: 100 },
      { id: 11, lead_stage_id: 2, value: 40 },
    ],
  },
  dispatch: vi.fn(),
};

const emptyFilters = {
  q: '',
  benefitTypeId: null,
  leadPriorityId: null,
  agentId: null,
  source: '',
  channel: '',
  leadStageId: null,
  createdAfter: null,
  createdBefore: null,
  stalled: false,
  noOpenTask: false,
};

const mountChips = (filters = {}) =>
  mount(FilterChips, {
    props: { filters: { ...emptyFilters, ...filters } },
    global: {
      mocks: { $t: translate },
      plugins: [
        {
          install: app => {
            app.config.globalProperties.$store = stubStore;
          },
        },
      ],
    },
  });

describe('FilterChips', () => {
  it('não renderiza chips sem filtro ativo, mas mantém o resumo', () => {
    const wrapper = mountChips();
    expect(wrapper.findAll('[data-testid^="filter-chip-"]')).toHaveLength(0);
    expect(wrapper.find('[data-testid="pipeline-summary"]').exists()).toBe(
      true
    );
  });

  it('mostra um chip por filtro ativo com o nome resolvido', () => {
    const wrapper = mountChips({
      agentId: 3,
      channel: 'whatsapp',
      stalled: true,
    });
    expect(
      wrapper.find('[data-testid="filter-chip-agentId"]').text()
    ).toContain('Eduardo');
    expect(
      wrapper.find('[data-testid="filter-chip-channel"]').text()
    ).toContain('WhatsApp');
    expect(wrapper.find('[data-testid="filter-chip-stalled"]').exists()).toBe(
      true
    );
  });

  it('o ✕ do chip emite update zerando SÓ aquele filtro', async () => {
    const wrapper = mountChips({ agentId: 3, channel: 'whatsapp' });
    await wrapper
      .find('[data-testid="filter-chip-remove-agentId"]')
      .trigger('click');
    expect(wrapper.emitted().update[0][0]).toEqual({ agentId: null });
  });

  it('resumo traz contagem, soma e previsão ponderada pela etapa', () => {
    const wrapper = mountChips();
    const summary = wrapper.find('[data-testid="pipeline-summary"]').text();
    // 2 leads · R$ 140 no total · previsão = 100×50% + 40×0% = R$ 50
    expect(summary).toContain('"count":2');
    expect(summary).toContain('140');
    expect(summary).toContain('50');
  });
});
