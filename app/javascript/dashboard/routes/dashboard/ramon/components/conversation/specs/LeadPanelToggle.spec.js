import { shallowMount } from '@vue/test-utils';
import Button from 'dashboard/components-next/button/Button.vue';
import LeadPanelToggle from '../LeadPanelToggle.vue';

const updateSpy = vi.fn();
const settings = { is_contact_sidebar_open: false };
vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({
    uiSettings: { value: settings },
    updateUISettings: (...a) => updateSpy(...a),
  }),
}));

const mountToggle = () =>
  shallowMount(LeadPanelToggle, { global: { mocks: { $t: k => k } } });

describe('LeadPanelToggle.vue', () => {
  beforeEach(() => {
    updateSpy.mockClear();
    settings.is_contact_sidebar_open = false;
  });

  it('opens the lead panel (and closes copilot) when closed', () => {
    const wrapper = mountToggle();
    wrapper.findComponent(Button).vm.$emit('click');
    expect(updateSpy).toHaveBeenCalledWith({
      is_contact_sidebar_open: true,
      is_copilot_panel_open: false,
    });
  });

  it('closes the lead panel when open', () => {
    settings.is_contact_sidebar_open = true;
    const wrapper = mountToggle();
    wrapper.findComponent(Button).vm.$emit('click');
    expect(updateSpy).toHaveBeenCalledWith({
      is_contact_sidebar_open: false,
      is_copilot_panel_open: false,
    });
  });

  it('uses the panel label from i18n', () => {
    const wrapper = mountToggle();
    expect(wrapper.findComponent(Button).props('label')).toBe(
      'CONVERSATION.SIDEBAR.CONTACT'
    );
  });
});
