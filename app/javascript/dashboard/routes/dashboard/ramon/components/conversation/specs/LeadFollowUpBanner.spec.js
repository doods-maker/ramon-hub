import { mount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import LeadFollowUpBanner from '../LeadFollowUpBanner.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));

const updateSpy = vi.fn();
vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({
    uiSettings: { value: {} },
    updateUISettings: (...a) => updateSpy(...a),
  }),
}));

const baseLead = {
  id: 1,
  conversation_id: 42,
  stalled: false,
  follow_up_count: 0,
  stage_entered_at: '2026-07-10T12:00:00Z',
};

const mountBanner = ({ lead, chatId = 42 } = {}) => {
  const ensure = vi.fn().mockResolvedValue(lead);
  const store = createStore({
    getters: { getSelectedChat: () => ({ id: chatId }) },
    modules: {
      leads: {
        namespaced: true,
        getters: {
          getLeadByConversationId: () => id =>
            lead && lead.conversation_id === id ? lead : undefined,
        },
        actions: { peekForConversation: ensure },
      },
    },
  });
  const wrapper = mount(LeadFollowUpBanner, {
    global: { plugins: [store], mocks: { $t: k => k } },
  });
  return { wrapper, ensure };
};

describe('LeadFollowUpBanner.vue', () => {
  beforeEach(() => updateSpy.mockClear());

  it('shows the stalled pill with the days count', async () => {
    const { wrapper } = mountBanner({
      lead: structuredClone({ ...baseLead, stalled: true }),
    });
    await flushPromises();
    const pill = wrapper.find('[data-testid="lead-follow-up-banner"]');
    expect(pill.exists()).toBe(true);
    expect(pill.text()).toContain('RAMON.FOLLOW_UP.BANNER_STALLED');
  });

  it('shows the retries part when follow_up_count > 0 (without stalled)', async () => {
    const { wrapper } = mountBanner({
      lead: structuredClone({ ...baseLead, follow_up_count: 3 }),
    });
    await flushPromises();
    const pill = wrapper.find('[data-testid="lead-follow-up-banner"]');
    expect(pill.text()).toContain('RAMON.FOLLOW_UP.BANNER_RETRIES');
    expect(pill.text()).not.toContain('RAMON.FOLLOW_UP.BANNER_STALLED');
  });

  it('renders nothing when the lead is neither stalled nor followed up', async () => {
    const { wrapper } = mountBanner({ lead: structuredClone(baseLead) });
    await flushPromises();
    expect(wrapper.find('[data-testid="lead-follow-up-banner"]').exists()).toBe(
      false
    );
  });

  it('opens the lead panel on click (same effect as the toggle)', async () => {
    const { wrapper } = mountBanner({
      lead: structuredClone({ ...baseLead, stalled: true }),
    });
    await flushPromises();
    await wrapper
      .find('[data-testid="lead-follow-up-banner"]')
      .trigger('click');
    expect(updateSpy).toHaveBeenCalledWith({
      is_contact_sidebar_open: true,
      is_copilot_panel_open: false,
    });
  });

  it('dispatches peekForConversation when the lead is not in the store', async () => {
    const { wrapper, ensure } = mountBanner({ lead: null });
    await flushPromises();
    expect(ensure).toHaveBeenCalledWith(expect.anything(), {
      conversationId: 42,
    });
    expect(wrapper.find('[data-testid="lead-follow-up-banner"]').exists()).toBe(
      false
    );
  });

  it('shows the banner from the peek result when the getter misses (contact fallback)', async () => {
    // lead achado por contato: conversation_id aponta pra OUTRA conversa
    const fallbackLead = structuredClone({
      ...baseLead,
      conversation_id: 7,
      stalled: true,
    });
    const ensure = vi.fn().mockResolvedValue(fallbackLead);
    const store = createStore({
      getters: { getSelectedChat: () => ({ id: 42 }) },
      modules: {
        leads: {
          namespaced: true,
          getters: { getLeadByConversationId: () => () => undefined },
          actions: { peekForConversation: ensure },
        },
      },
    });
    const wrapper = mount(LeadFollowUpBanner, {
      global: { plugins: [store], mocks: { $t: k => k } },
    });
    await flushPromises();
    expect(wrapper.find('[data-testid="lead-follow-up-banner"]').exists()).toBe(
      true
    );
  });

  it('does not dispatch when the lead is already in the store', async () => {
    const { ensure } = mountBanner({
      lead: structuredClone({ ...baseLead, stalled: true }),
    });
    await flushPromises();
    expect(ensure).not.toHaveBeenCalled();
  });
});
