import { shallowMount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import LeadConversationPanel from '../LeadConversationPanel.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));

const lead = { id: 5, conversation_id: 42, name: 'Zé' };
const build = (ensureSpy, thesesGetSpy = vi.fn(), leadGetter = () => lead) =>
  createStore({
    modules: {
      leads: {
        namespaced: true,
        getters: { getLeadByConversationId: () => leadGetter },
        actions: { ensureForConversation: ensureSpy },
      },
      theses: {
        namespaced: true,
        getters: { getTheses: () => [] },
        actions: { get: thesesGetSpy },
      },
    },
  });
const mountPanel = (
  ensureSpy = vi.fn().mockResolvedValue(lead),
  thesesGetSpy = vi.fn(),
  leadGetter = () => lead
) =>
  shallowMount(LeadConversationPanel, {
    props: { conversationId: 42 },
    global: {
      plugins: [build(ensureSpy, thesesGetSpy, leadGetter)],
      mocks: { $t: k => k },
      stubs: { LeadPanelBody: true },
    },
  });

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

  it('renders the shared LeadPanelBody with the conversation context', async () => {
    const wrapper = mountPanel();
    await flushPromises();
    const body = wrapper.findComponent({ name: 'LeadPanelBody' });
    expect(body.exists()).toBe(true);
    expect(body.props('lead')).toEqual(lead);
    expect(body.props('context')).toBe('conversation');
  });

  it('forwards discarded from the body', async () => {
    const wrapper = mountPanel();
    await flushPromises();
    wrapper.findComponent({ name: 'LeadPanelBody' }).vm.$emit('discarded');
    expect(wrapper.emitted('discarded')).toBeTruthy();
  });

  it('emits close when clicking the close button', async () => {
    const wrapper = mountPanel();
    await flushPromises();
    await wrapper.find('[data-testid="lead-panel-close"]').trigger('click');
    expect(wrapper.emitted('close')).toBeTruthy();
  });

  it('shows the retry state when ensure fails and no lead is cached', async () => {
    const ensure = vi.fn().mockRejectedValue(new Error('boom'));
    const wrapper = mountPanel(ensure, vi.fn(), () => null);
    await flushPromises();
    expect(wrapper.find('[data-testid="lead-panel-retry"]').exists()).toBe(
      true
    );
    await wrapper.find('[data-testid="lead-panel-retry"]').trigger('click');
    expect(ensure).toHaveBeenCalledTimes(2);
  });

  it('dispatches theses/get on mount when no theses are loaded yet', async () => {
    const thesesGet = vi.fn();
    mountPanel(vi.fn().mockResolvedValue(lead), thesesGet);
    await flushPromises();
    expect(thesesGet).toHaveBeenCalled();
  });

  describe('caixa do escritório (ensure devolve null)', () => {
    const mountSemLead = (meta = {}, encaminharSpy = vi.fn()) =>
      shallowMount(LeadConversationPanel, {
        props: { conversationId: 42 },
        global: {
          plugins: [
            createStore({
              getters: {
                getSelectedChat: () => ({
                  id: 42,
                  meta,
                }),
              },
              modules: {
                leads: {
                  namespaced: true,
                  getters: { getLeadByConversationId: () => () => null },
                  actions: {
                    ensureForConversation: vi.fn().mockResolvedValue(null),
                    encaminharComercial: encaminharSpy,
                  },
                },
                theses: {
                  namespaced: true,
                  getters: { getTheses: () => [] },
                  actions: { get: vi.fn() },
                },
              },
            }),
          ],
          mocks: { $t: k => k },
          stubs: { LeadPanelBody: true, ClientePanel: true },
        },
      });

    it('mostra o painel do cliente (ClientePanel) no lugar do lead', async () => {
      const wrapper = mountSemLead();
      await flushPromises();
      const painel = wrapper.findComponent({ name: 'ClientePanel' });
      expect(painel.exists()).toBe(true);
      expect(painel.props('conversationId')).toBe(42);
      expect(wrapper.text()).toContain('RAMON.CLIENTE_PANEL.CLIENTE');
    });

    it('encaminhar do painel do cliente dispara a action com a conversa', async () => {
      const encaminhar = vi.fn().mockResolvedValue(lead);
      const wrapper = mountSemLead({}, encaminhar);
      await flushPromises();
      wrapper.findComponent({ name: 'ClientePanel' }).vm.$emit('encaminhar');
      await flushPromises();
      expect(encaminhar).toHaveBeenCalledWith(expect.anything(), {
        conversationId: 42,
      });
    });
  });
});
