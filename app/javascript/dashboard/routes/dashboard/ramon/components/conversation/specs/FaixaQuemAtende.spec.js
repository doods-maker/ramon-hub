import { mount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import FaixaQuemAtende from '../FaixaQuemAtende.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: (key, p) => (p?.nome ? `${p.nome} ${key}` : key) }),
}));

const montar = chat => {
  const assignAgent = vi.fn();
  const updateCustomAttributes = vi.fn();
  const toggleStatus = vi.fn();
  const store = createStore({
    state: () => ({ chat }),
    getters: {
      getSelectedChat: state => state.chat,
      getCurrentUser: () => ({ id: 7 }),
    },
    actions: { assignAgent, updateCustomAttributes, toggleStatus },
  });
  const wrapper = mount(FaixaQuemAtende, { global: { plugins: [store] } });
  return { wrapper, assignAgent, updateCustomAttributes, toggleStatus };
};

describe('FaixaQuemAtende.vue', () => {
  it('IA atendendo: mostra o estado e o botão Assumir', async () => {
    const { wrapper, assignAgent, toggleStatus } = montar({
      id: 42,
      status: 'pending',
      custom_attributes: {},
    });

    expect(wrapper.attributes('data-estado')).toBe('ia');
    expect(wrapper.text()).toContain('RAMON.IA_CONVERSA.FAIXA.ia');
    await wrapper.find('[data-testid="faixa-assumir"]').trigger('click');
    await flushPromises();

    expect(assignAgent).toHaveBeenCalledWith(expect.anything(), {
      conversationId: 42,
      agentId: 7,
    });
    expect(toggleStatus).toHaveBeenCalledWith(expect.anything(), {
      conversationId: 42,
      status: 'open',
    });
  });

  it('pessoa atendendo: mostra o nome e Devolver à IA', async () => {
    const { wrapper, assignAgent } = montar({
      id: 42,
      status: 'open',
      meta: { assignee: { id: 2, name: 'Eduardo' } },
      custom_attributes: { ia_pausa: 'pausada' },
    });

    expect(wrapper.attributes('data-estado')).toBe('pessoa');
    expect(wrapper.text()).toContain('Eduardo');
    await wrapper.find('[data-testid="faixa-devolver"]').trigger('click');
    await flushPromises();

    expect(assignAgent).toHaveBeenCalledWith(expect.anything(), {
      conversationId: 42,
      agentId: 0,
    });
  });
});
