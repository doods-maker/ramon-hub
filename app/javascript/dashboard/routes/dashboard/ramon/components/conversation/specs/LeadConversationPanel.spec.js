import { shallowMount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import LeadConversationPanel from '../LeadConversationPanel.vue';

const lead = { id: 5, conversation_id: 42, name: 'Zé' };
const build = (ensureSpy, deleteSpy) =>
  createStore({
    modules: {
      leads: {
        namespaced: true,
        getters: { getLeadByConversationId: () => () => lead },
        actions: {
          ensureForConversation: ensureSpy,
          delete: deleteSpy,
          select: vi.fn(),
        },
      },
      leadConfig: {
        namespaced: true,
        getters: {
          getStages: () => [],
          getBenefitTypes: () => [],
          getPriorities: () => [],
        },
      },
      agents: { namespaced: true, getters: { getAgents: () => [] } },
    },
  });
const mountPanel = (
  ensureSpy = vi.fn().mockResolvedValue(lead),
  deleteSpy = vi.fn()
) =>
  shallowMount(LeadConversationPanel, {
    props: { conversationId: 42, inboxId: 1 },
    global: {
      plugins: [build(ensureSpy, deleteSpy)],
      mocks: { $t: k => k },
      stubs: {
        ConversationAction: true,
        MacrosList: true,
        ResolveAction: true,
        LeadFields: true,
      },
    },
  });

describe('LeadConversationPanel', () => {
  it('ensures the lead on mount', async () => {
    const ensure = vi.fn().mockResolvedValue(lead);
    mountPanel(ensure);
    await flushPromises();
    expect(ensure).toHaveBeenCalledWith(expect.anything(), {
      conversationId: 42,
    });
  });

  it('discards the lead and emits discarded', async () => {
    const del = vi.fn();
    const wrapper = mountPanel(vi.fn().mockResolvedValue(lead), del);
    await flushPromises();
    await wrapper.find('[data-testid="lead-discard"]').trigger('click');
    expect(del).toHaveBeenCalledWith(expect.anything(), 5);
    expect(wrapper.emitted('discarded')).toBeTruthy();
  });
});
