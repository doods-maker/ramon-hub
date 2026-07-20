import { shallowMount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import LeadConversationPanel from '../LeadConversationPanel.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));

const lead = { id: 5, conversation_id: 42, name: 'Zé' };
const build = (ensureSpy, deleteSpy, thesesGetSpy = vi.fn()) =>
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
      theses: {
        namespaced: true,
        getters: { getTheses: () => [] },
        actions: { get: thesesGetSpy },
      },
    },
  });
const mountPanel = (
  ensureSpy = vi.fn().mockResolvedValue(lead),
  deleteSpy = vi.fn(),
  thesesGetSpy = vi.fn()
) =>
  shallowMount(LeadConversationPanel, {
    props: { conversationId: 42, inboxId: 1 },
    global: {
      plugins: [build(ensureSpy, deleteSpy, thesesGetSpy)],
      mocks: { $t: k => k },
      stubs: {
        // AccordionItem real p/ testar abrir/recolher; filhos stubados.
        AccordionItem: false,
        EmojiOrIcon: true,
        FluentIcon: true,
        ConversationAction: true,
        MacrosList: true,
        ResolveAction: true,
        LeadFields: true,
        LeadHistory: true,
        LeadPlaybook: true,
        LeadTriage: true,
        LeadKit: true,
        LeadSimulador: true,
      },
    },
  });

const toggleSection = (wrapper, id) =>
  wrapper.find(`[data-testid="section-${id}"] button`).trigger('click');

describe('LeadConversationPanel', () => {
  beforeEach(() => localStorage.clear());

  it('ensures the lead on mount', async () => {
    const ensure = vi.fn().mockResolvedValue(lead);
    mountPanel(ensure);
    await flushPromises();
    expect(ensure).toHaveBeenCalledWith(expect.anything(), {
      conversationId: 42,
    });
  });

  it('discards the lead only after inline confirmation', async () => {
    const del = vi.fn();
    const wrapper = mountPanel(vi.fn().mockResolvedValue(lead), del);
    await flushPromises();
    // 1º clique abre o prompt — nada é deletado ainda
    await wrapper.find('[data-testid="lead-discard"]').trigger('click');
    expect(del).not.toHaveBeenCalled();
    await wrapper.find('[data-testid="lead-discard-confirm"]').trigger('click');
    await flushPromises();
    expect(del).toHaveBeenCalledWith(expect.anything(), 5);
    expect(wrapper.emitted('discarded')).toBeTruthy();
  });

  it('cancels the discard prompt without deleting', async () => {
    const del = vi.fn();
    const wrapper = mountPanel(vi.fn().mockResolvedValue(lead), del);
    await flushPromises();
    await wrapper.find('[data-testid="lead-discard"]').trigger('click');
    await wrapper.find('[data-testid="lead-discard-cancel"]').trigger('click');
    expect(del).not.toHaveBeenCalled();
    expect(wrapper.find('[data-testid="lead-discard"]').exists()).toBe(true);
  });

  it('emits close when clicking the close button', async () => {
    const wrapper = mountPanel();
    await flushPromises();
    await wrapper.find('[data-testid="lead-panel-close"]').trigger('click');
    expect(wrapper.emitted('close')).toBeTruthy();
  });

  it('starts with Resumo open and the other sections collapsed', async () => {
    const wrapper = mountPanel();
    await flushPromises();
    expect(wrapper.findComponent({ name: 'LeadFields' }).exists()).toBe(true);
    expect(wrapper.findComponent({ name: 'LeadHistory' }).exists()).toBe(false);
    expect(wrapper.findComponent({ name: 'LeadKit' }).exists()).toBe(false);
  });

  it('opens the Histórico section and renders LeadHistory', async () => {
    const wrapper = mountPanel();
    await flushPromises();
    await toggleSection(wrapper, 'historico');
    expect(wrapper.findComponent({ name: 'LeadHistory' }).exists()).toBe(true);
  });

  it('opens the Playbook section and renders LeadPlaybook', async () => {
    const wrapper = mountPanel();
    await flushPromises();
    await toggleSection(wrapper, 'playbook');
    expect(wrapper.findComponent({ name: 'LeadPlaybook' }).exists()).toBe(true);
  });

  it('opens the Kit section and renders LeadKit', async () => {
    const wrapper = mountPanel();
    await flushPromises();
    await toggleSection(wrapper, 'kit');
    expect(wrapper.findComponent({ name: 'LeadKit' }).exists()).toBe(true);
  });

  it('persists the open/collapsed state per section in localStorage', async () => {
    const wrapper = mountPanel();
    await flushPromises();
    await toggleSection(wrapper, 'kit');
    await toggleSection(wrapper, 'resumo');
    const saved = JSON.parse(localStorage.getItem('ramon_lead_panel_sections'));
    expect(saved.kit).toBe(true);
    expect(saved.resumo).toBe(false);
  });

  it('restores the persisted state on mount', async () => {
    localStorage.setItem(
      'ramon_lead_panel_sections',
      JSON.stringify({ resumo: false, kit: true })
    );
    const wrapper = mountPanel();
    await flushPromises();
    expect(wrapper.findComponent({ name: 'LeadFields' }).exists()).toBe(false);
    expect(wrapper.findComponent({ name: 'LeadKit' }).exists()).toBe(true);
  });

  it('dispatches theses/get on mount when no theses are loaded yet', async () => {
    const thesesGet = vi.fn();
    mountPanel(vi.fn().mockResolvedValue(lead), vi.fn(), thesesGet);
    await flushPromises();
    expect(thesesGet).toHaveBeenCalled();
  });
});
