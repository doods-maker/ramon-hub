import { mount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import LeadDrawer from '../LeadDrawer.vue';
import LeadsAPI from 'dashboard/api/leads';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
// A gaveta busca o lead completo ao abrir (índice slim, sem custom_attributes)
vi.mock('dashboard/api/leads', () => ({
  default: { show: vi.fn() },
}));

const lead = {
  id: 10,
  name: 'João',
  lead_stage_id: 1,
  conversation_id: 77,
  contact_name: 'João Cliente',
  contact_phone: '+55479999',
};

const buildStore = (selectSpy, upsertSpy = vi.fn()) =>
  createStore({
    modules: {
      leads: {
        namespaced: true,
        getters: {
          getSelectedLead: () => lead,
          getDockConversationId: () => null,
        },
        actions: { select: selectSpy, upsert: upsertSpy },
      },
    },
  });

const mountDrawer = (selectSpy = vi.fn(), upsertSpy = vi.fn()) =>
  mount(LeadDrawer, {
    global: {
      plugins: [buildStore(selectSpy, upsertSpy)],
      mocks: { $t: k => k },
      stubs: { LeadPanelBody: true },
    },
  });

describe('LeadDrawer.vue', () => {
  // mockReset do vitest.config zera implementações — re-arma a cada teste
  beforeEach(() => LeadsAPI.show.mockResolvedValue({ data: { id: 10 } }));

  it('busca o lead completo ao abrir e faz upsert na store', async () => {
    const upsert = vi.fn();
    mountDrawer(vi.fn(), upsert);
    await flushPromises();
    expect(LeadsAPI.show).toHaveBeenCalledWith(10);
    expect(upsert).toHaveBeenCalledWith(expect.anything(), { id: 10 });
  });

  it('renderiza o corpo compartilhado no contexto drawer', () => {
    const wrapper = mountDrawer();
    const body = wrapper.findComponent({ name: 'LeadPanelBody' });
    expect(body.exists()).toBe(true);
    expect(body.props('context')).toBe('drawer');
    expect(body.props('lead')).toEqual(lead);
  });

  it('fecha desselecionando o lead', async () => {
    const select = vi.fn();
    const wrapper = mountDrawer(select);
    await wrapper.find('[data-testid="drawer-close"]').trigger('click');
    expect(select).toHaveBeenCalledWith(expect.anything(), null);
  });

  it('repassa openConversation vindo do corpo', () => {
    const wrapper = mountDrawer();
    wrapper
      .findComponent({ name: 'LeadPanelBody' })
      .vm.$emit('openConversation', 77);
    expect(wrapper.emitted('openConversation')[0][0]).toBe(77);
  });

  it('fecha quando o corpo navega (Dossiê)', () => {
    const select = vi.fn();
    const wrapper = mountDrawer(select);
    wrapper.findComponent({ name: 'LeadPanelBody' }).vm.$emit('navigate');
    expect(select).toHaveBeenCalledWith(expect.anything(), null);
  });

  it('fecha ao apertar Esc', async () => {
    const select = vi.fn();
    mountDrawer(select);
    // bubbles: como um keydown real, o evento sobe até a window (onKeyStroke)
    window.dispatchEvent(
      new KeyboardEvent('keydown', { key: 'Escape', bubbles: true })
    );
    expect(select).toHaveBeenCalledWith(expect.anything(), null);
  });
});
