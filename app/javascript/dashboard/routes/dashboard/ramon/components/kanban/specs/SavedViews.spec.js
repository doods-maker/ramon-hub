import { mount } from '@vue/test-utils';
import SavedViews from '../SavedViews.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

// Mesmo padrão do LeadPanelToggle.spec: stub com .value lido sob demanda.
const updateUISettings = vi.fn();
const settings = { current: {} };
vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({
    uiSettings: {
      get value() {
        return settings.current;
      },
    },
    updateUISettings: (...args) => updateUISettings(...args),
  }),
}));

const dispatch = vi.fn();
const stubStore = {
  getters: {
    'leads/getLeads': [
      { id: 1, lead_stage_id: 1, channel: 'whatsapp' },
      { id: 2, lead_stage_id: 2, channel: 'meta_ads' },
    ],
    'leads/getFilters': { channel: '', q: '' },
  },
  dispatch,
};

const mountViews = () =>
  mount(SavedViews, {
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

describe('SavedViews (quadros salvos)', () => {
  beforeEach(() => {
    dispatch.mockClear();
    updateUISettings.mockClear();
    settings.current = {};
    localStorage.clear();
  });

  it('converte o legado ramon_lead_views em ramon_lead_boards uma única vez', () => {
    settings.current = {
      ramon_lead_views: [
        { name: 'WhatsApp', filters: { channel: 'whatsapp' } },
      ],
    };
    mountViews();
    expect(updateUISettings).toHaveBeenCalledTimes(1);
    const [payload] = updateUISettings.mock.calls[0];
    expect(payload.ramon_lead_boards).toHaveLength(1);
    expect(payload.ramon_lead_boards[0]).toMatchObject({
      name: 'WhatsApp',
      filters: { channel: 'whatsapp' },
      view: 'columns',
      groupBy: 'thesis',
    });
  });

  it('NÃO converte quando ramon_lead_boards já existe', () => {
    settings.current = {
      ramon_lead_views: [{ name: 'X', filters: {} }],
      ramon_lead_boards: [],
    };
    mountViews();
    expect(updateUISettings).not.toHaveBeenCalled();
  });

  it('lista os quadros com contagem client-side e aplica ao clicar', async () => {
    settings.current = {
      ramon_lead_boards: [
        {
          id: 7,
          name: 'WhatsApp',
          color: '#c9a97c',
          filters: { channel: 'whatsapp' },
          collapsed: [3],
          view: 'lanes',
          groupBy: 'sdr',
        },
      ],
    };
    const wrapper = mountViews();
    await wrapper
      .find('[data-testid="board-dropdown-toggle"]')
      .trigger('click');

    const item = wrapper.find('[data-testid="board-item"]');
    expect(item.text()).toContain('WhatsApp');
    expect(wrapper.find('[data-testid="board-count"]').text()).toBe('1');

    await item.trigger('click');
    expect(dispatch).toHaveBeenCalledWith(
      'leads/setFilters',
      expect.objectContaining({ channel: 'whatsapp', q: '' })
    );
    expect(wrapper.emitted().apply[0][0]).toMatchObject({ id: 7 });
    // o quadro aplicado grava o colapso salvo das colunas
    expect(localStorage.getItem('ramon_kanban_collapsed')).toBe('[3]');
  });

  it('cria quadro novo a partir dos filtros atuais', async () => {
    settings.current = { ramon_lead_boards: [] };
    const wrapper = mountViews();
    await wrapper
      .find('[data-testid="board-dropdown-toggle"]')
      .trigger('click');
    await wrapper.find('[data-testid="board-new"]').trigger('click');

    const modal = wrapper.findComponent({ name: 'NamePromptModal' });
    await modal
      .find('[data-testid="name-prompt-input"]')
      .setValue('Meu quadro');
    await modal.find('[data-testid="name-prompt-confirm"]').trigger('click');

    const [payload] = updateUISettings.mock.calls.at(-1);
    expect(payload.ramon_lead_boards[0]).toMatchObject({
      name: 'Meu quadro',
      filters: { channel: '', q: '' },
    });
    expect(wrapper.emitted().apply).toBeTruthy();
  });

  it('excluir quadro remove da lista e volta para Todos quando era o ativo', async () => {
    settings.current = {
      ramon_lead_boards: [
        { id: 7, name: 'X', color: '#c9a97c', filters: {}, collapsed: [] },
      ],
    };
    localStorage.setItem('ramon_lead_board_active', '7');
    const wrapper = mountViews();
    await wrapper
      .find('[data-testid="board-dropdown-toggle"]')
      .trigger('click');
    await wrapper.find('[data-testid="board-remove"]').trigger('click');
    await wrapper.findComponent({ name: 'ConfirmModal' }).vm.$emit('confirm');
    await wrapper.vm.$nextTick();

    const [payload] = updateUISettings.mock.calls.at(-1);
    expect(payload.ramon_lead_boards).toEqual([]);
    expect(wrapper.emitted().apply.at(-1)[0]).toBeNull();
  });
});
