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
      { id: 2, name: 'Assinatura', probability: 80 },
      { id: 3, name: 'Ganho', probability: 100, is_won: true },
      { id: 4, name: 'Perdido', probability: 0, is_lost: true },
    ],
    'agents/getAgents': [{ id: 3, name: 'Eduardo' }],
    'leads/getLeads': [
      { id: 10, lead_stage_id: 1, value: 100 },
      { id: 11, lead_stage_id: 2, value: 40 },
      { id: 12, lead_stage_id: 3, value: 900 },
      { id: 13, lead_stage_id: 4, value: 700 },
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
  overdueTask: false,
  taskDueToday: false,
  wonSince: null,
  newFromLp: false,
  closedAll: false,
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

  it('mostra chip removível pros atalhos dos KPIs do Centro', async () => {
    const wrapper = mountChips({
      overdueTask: true,
      taskDueToday: true,
      wonSince: '2026-10-05',
      newFromLp: true,
    });
    expect(
      wrapper.find('[data-testid="filter-chip-wonSince"]').text()
    ).toContain('05/10');
    ['overdueTask', 'taskDueToday', 'newFromLp'].forEach(key => {
      expect(wrapper.find(`[data-testid="filter-chip-${key}"]`).exists()).toBe(
        true
      );
    });
    await wrapper
      .find('[data-testid="filter-chip-remove-wonSince"]')
      .trigger('click');
    expect(wrapper.emitted().update[0][0]).toEqual({ wonSince: null });
  });

  it('chip de ganhos/perdidos de todas as datas volta aos 90 dias no ✕', async () => {
    const wrapper = mountChips({ closedAll: true });
    await wrapper
      .find('[data-testid="filter-chip-remove-closedAll"]')
      .trigger('click');
    expect(wrapper.emitted().update[0][0]).toEqual({ closedAll: false });
  });

  it('resumo conta só o pipeline em aberto (sem ganhos e perdidos)', () => {
    const wrapper = mountChips();
    const summary = wrapper.find('[data-testid="pipeline-summary"]').text();
    // 2 em aberto · R$ 140 · previsão = 100×50% + 40×80% = R$ 82
    expect(summary).toContain('"count":2');
    expect(summary).toContain('140');
    expect(summary).toContain('82');
  });
});
