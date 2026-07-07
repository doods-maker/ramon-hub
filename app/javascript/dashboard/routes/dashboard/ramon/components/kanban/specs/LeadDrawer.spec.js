import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import LeadDrawer from '../LeadDrawer.vue';

const lead = {
  id: 10,
  name: 'João',
  lead_stage_id: 1,
  benefit_type_id: null,
  lead_priority_id: null,
  sdr_id: null,
  closer_id: null,
  value: '5000.00',
  source: 'Meta Ads',
  notes: 'nota',
  conversation_id: 77,
  contact_name: 'João Cliente',
  contact_phone: '+55479999',
  contact_email: 'j@cli.com',
};

const buildStore = (updateSpy, selectSpy) =>
  createStore({
    modules: {
      leads: {
        namespaced: true,
        getters: { getSelectedLead: () => lead },
        actions: {
          update: updateSpy,
          select: selectSpy,
          fetchNotes: vi.fn().mockResolvedValue([]),
          createNote: vi.fn(),
        },
      },
      leadConfig: {
        namespaced: true,
        getters: {
          getStages: () => [
            { id: 1, name: 'Novo' },
            { id: 2, name: 'Negociação' },
          ],
          getBenefitTypes: () => [{ id: 3, name: 'Auxílio-acidente' }],
          getPriorities: () => [{ id: 4, name: 'Alta' }],
          getChannels: () => [],
        },
      },
      agents: {
        namespaced: true,
        getters: { getAgents: () => [{ id: 8, name: 'Eduardo' }] },
      },
      theses: {
        namespaced: true,
        getters: { getTheses: () => [] },
      },
    },
  });

const mountDrawer = (updateSpy = vi.fn(), selectSpy = vi.fn()) =>
  mount(LeadDrawer, {
    global: {
      plugins: [buildStore(updateSpy, selectSpy)],
      mocks: { $t: k => k },
    },
  });

describe('LeadDrawer.vue', () => {
  it('carrega o lead selecionado e mostra dados de contato (só leitura)', () => {
    const wrapper = mountDrawer();
    expect(wrapper.text()).toContain('João Cliente');
    expect(wrapper.text()).toContain('+55479999');
  });

  it('salva o nome no blur quando muda', async () => {
    const update = vi.fn();
    const wrapper = mountDrawer(update);
    const input = wrapper.find('[data-testid="field-name"]');
    await input.setValue('João Silva');
    await input.trigger('blur');
    expect(update).toHaveBeenCalledWith(expect.anything(), {
      id: 10,
      name: 'João Silva',
    });
  });

  it('NÃO salva no blur quando o valor não mudou', async () => {
    const update = vi.fn();
    const wrapper = mountDrawer(update);
    await wrapper.find('[data-testid="field-name"]').trigger('blur');
    expect(update).not.toHaveBeenCalled();
  });

  it('salva a etapa no change', async () => {
    const update = vi.fn();
    const wrapper = mountDrawer(update);
    const select = wrapper.find('[data-testid="field-stage"]');
    await select.setValue(2);
    expect(update).toHaveBeenCalledWith(expect.anything(), {
      id: 10,
      lead_stage_id: 2,
    });
  });

  it('fecha desselecionando o lead', async () => {
    const select = vi.fn();
    const wrapper = mountDrawer(vi.fn(), select);
    await wrapper.find('[data-testid="drawer-close"]').trigger('click');
    expect(select).toHaveBeenCalledWith(expect.anything(), null);
  });

  it('emite open-conversation', async () => {
    const wrapper = mountDrawer();
    await wrapper
      .find('[data-testid="drawer-open-conversation"]')
      .trigger('click');
    expect(wrapper.emitted('openConversation')[0][0]).toBe(77);
  });

  it('fecha ao apertar Esc (listener no documento)', async () => {
    const select = vi.fn();
    mountDrawer(vi.fn(), select);
    document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }));
    expect(select).toHaveBeenCalledWith(expect.anything(), null);
  });
});
