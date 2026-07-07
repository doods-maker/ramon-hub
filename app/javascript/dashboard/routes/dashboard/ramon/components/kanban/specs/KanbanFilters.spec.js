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
});
