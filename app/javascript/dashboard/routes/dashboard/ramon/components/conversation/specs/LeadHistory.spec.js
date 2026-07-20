import { shallowMount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import LeadHistory from '../LeadHistory.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: k => k, te: () => true }),
}));

const activities = [
  {
    id: 1,
    kind: 'created',
    from_value: null,
    to_value: 'instagram',
    author_name: null,
    created_at: '2026-06-01T10:00:00Z',
  },
  {
    id: 2,
    kind: 'stage_changed',
    from_value: 'Novo',
    to_value: 'Qualificação',
    author_name: 'Ana',
    created_at: '2026-06-02T10:00:00Z',
  },
];
const build = fetchSpy =>
  createStore({
    modules: {
      leads: { namespaced: true, actions: { fetchActivities: fetchSpy } },
    },
  });
const mountHistory = (fetchSpy = vi.fn().mockResolvedValue(activities)) =>
  shallowMount(LeadHistory, {
    props: { leadId: 7 },
    global: { plugins: [build(fetchSpy)], mocks: { $t: k => k } },
  });

it('fetches activities on mount', async () => {
  const fetchSpy = vi.fn().mockResolvedValue(activities);
  mountHistory(fetchSpy);
  await flushPromises();
  expect(fetchSpy).toHaveBeenCalledWith(expect.anything(), 7);
});

it('renders one row per activity, most recent first', async () => {
  const wrapper = mountHistory();
  await flushPromises();
  const rows = wrapper.findAll('[data-testid="activity-row"]');
  expect(rows).toHaveLength(2);
  expect(rows[0].text()).toContain('Qualificação'); // ordem invertida = mais recente no topo
});
