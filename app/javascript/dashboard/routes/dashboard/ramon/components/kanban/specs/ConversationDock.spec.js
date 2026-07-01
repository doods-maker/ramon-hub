import { mount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import ConversationDock from '../ConversationDock.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));

const chat = { id: 42, inbox_id: 3, meta: { sender: { name: 'Zé' } } };
const build = ({ startWithChat = true, lead = null } = {}) => {
  let present = startWithChat;
  const getConversation = vi.fn().mockImplementation(() => {
    present = true;
  });
  const setActiveChat = vi.fn();
  const closeDock = vi.fn();
  const store = createStore({
    modules: {
      leads: {
        namespaced: true,
        getters: {
          getDockConversationId: () => 42,
          getSelectedLead: () => lead,
        },
        actions: { closeDock },
      },
      conversations: {
        namespaced: true,
        getters: {
          getConversationById: () => () => (present ? chat : undefined),
        },
        actions: { getConversation, setActiveChat },
      },
    },
  });
  return { store, getConversation, setActiveChat, closeDock };
};
const mountDock = ctx => {
  const { store, ...spies } = build(ctx);
  const wrapper = mount(ConversationDock, {
    global: {
      plugins: [store],
      mocks: { $t: k => k },
      stubs: { ConversationBox: true },
    },
  });
  return { wrapper, ...spies };
};

describe('ConversationDock', () => {
  it('fetches the conversation when absent, then activates it', async () => {
    const { getConversation, setActiveChat } = mountDock({
      startWithChat: false,
    });
    await flushPromises();
    expect(getConversation).toHaveBeenCalledWith(expect.anything(), 42);
    expect(setActiveChat).toHaveBeenCalledWith(expect.anything(), {
      data: expect.any(Object),
    });
  });

  it('does not refetch when the conversation is already in the store', async () => {
    const { getConversation, setActiveChat } = mountDock({
      startWithChat: true,
    });
    await flushPromises();
    expect(getConversation).not.toHaveBeenCalled();
    expect(setActiveChat).toHaveBeenCalledWith(expect.anything(), {
      data: chat,
    });
  });

  it('closes via the X button', async () => {
    const { wrapper, closeDock } = mountDock({});
    await flushPromises();
    await wrapper.find('[data-testid="dock-close"]').trigger('click');
    expect(closeDock).toHaveBeenCalled();
  });

  it('shifts left when the lead drawer is open', async () => {
    const { wrapper } = mountDock({ lead: { id: 1 } });
    await flushPromises();
    expect(
      wrapper.find('[data-testid="conversation-dock"]').classes().join(' ')
    ).toContain('right-[25rem]');
  });
});
