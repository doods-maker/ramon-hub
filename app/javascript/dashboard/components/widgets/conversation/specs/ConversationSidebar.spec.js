import { shallowMount } from '@vue/test-utils';
import { createStore } from 'vuex';
import ConversationSidebar from '../ConversationSidebar.vue';

const build = () =>
  createStore({
    state: { currentUser: { ui_settings: { is_contact_sidebar_open: true } } },
    getters: {
      getUISettings: state => state.currentUser.ui_settings,
    },
  });

const mountSidebar = () =>
  shallowMount(ConversationSidebar, {
    props: { currentChat: { id: 42, inbox_id: 1 } },
    global: {
      plugins: [build()],
      mocks: { $t: k => k },
      stubs: { ContactPanel: true, LeadConversationPanel: true },
    },
  });

describe('ConversationSidebar', () => {
  it('renders LeadConversationPanel instead of ContactPanel by default', () => {
    const wrapper = mountSidebar();
    expect(
      wrapper.findComponent({ name: 'LeadConversationPanel' }).exists()
    ).toBe(true);
    expect(wrapper.findComponent({ name: 'ContactPanel' }).exists()).toBe(
      false
    );
  });

  it('falls back to ContactPanel after discard', async () => {
    const wrapper = mountSidebar();
    wrapper
      .findComponent({ name: 'LeadConversationPanel' })
      .vm.$emit('discarded');
    await wrapper.vm.$nextTick();
    expect(wrapper.findComponent({ name: 'ContactPanel' }).exists()).toBe(true);
    expect(
      wrapper.findComponent({ name: 'LeadConversationPanel' }).exists()
    ).toBe(false);
  });
});
