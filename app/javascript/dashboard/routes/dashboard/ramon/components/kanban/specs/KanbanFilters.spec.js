import { mount } from '@vue/test-utils';
import KanbanFilters from '../KanbanFilters.vue';

const stubStore = {
  getters: {
    'leadConfig/getBenefitTypes': [{ id: 1, name: 'BPC' }],
    'leadConfig/getPriorities': [{ id: 2, name: 'Alta' }],
    'leadConfig/getSources': ['Meta Ads'],
    'leadConfig/getChannels': [{ key: 'meta_ads', label: 'Meta Ads' }],
    'agents/getAgents': [{ id: 3, name: 'Eduardo' }],
  },
};

const mountFilters = () =>
  mount(KanbanFilters, {
    props: {
      filters: {
        benefitTypeId: null,
        leadPriorityId: null,
        agentId: null,
        source: '',
        q: '',
      },
    },
    global: {
      mocks: { $t: k => k },
      plugins: [
        {
          install: app => {
            app.config.globalProperties.$store = stubStore;
          },
        },
      ],
    },
  });

describe('KanbanFilters', () => {
  it('emite update ao escolher um benefício', async () => {
    const wrapper = mountFilters();
    await wrapper.find('[data-testid="filter-benefit"]').setValue('1');
    expect(wrapper.emitted().update[0][0]).toEqual({ benefitTypeId: '1' });
  });

  it('alterna ganhos/perdidos entre 90 dias e todos', async () => {
    const wrapper = mountFilters();
    const select = wrapper.find('[data-testid="filter-closed-all"]');
    await select.setValue('all');
    await select.setValue('');
    expect(wrapper.emitted().update.map(([partial]) => partial)).toEqual([
      { closedAll: true },
      { closedAll: false },
    ]);
  });
});
