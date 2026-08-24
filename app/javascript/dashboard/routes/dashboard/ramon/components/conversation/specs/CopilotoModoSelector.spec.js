import { mount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import { nextTick } from 'vue';
import CopilotoModoSelector from '../CopilotoModoSelector.vue';

const translations = {
  'RAMON.COPILOTO.BTN': ({ modo }) => `Copiloto: ${modo}`,
  'RAMON.COPILOTO.MODOS.manual.NOME': () => 'Manual',
  'RAMON.COPILOTO.MODOS.manual.DESC': () =>
    'A IA não sugere nada. Você escreve tudo.',
  'RAMON.COPILOTO.MODOS.rascunho.NOME': () => 'Rascunho',
  'RAMON.COPILOTO.MODOS.rascunho.DESC': () =>
    'A IA prepara respostas; nada sai sem você apertar Enviar.',
  'RAMON.COPILOTO.MODOS.piloto_limitado.NOME': () => 'Piloto com limites',
  'RAMON.COPILOTO.MODOS.piloto_limitado.DESC': () =>
    'A IA envia sozinha SÓ mensagens de logística: cobrança de documentos, confirmação de horário, mensagem de cadência.',
  'RAMON.COPILOTO.MODOS.piloto_limitado.NOTA': () =>
    'Nunca envia: valores, análise do caso, promessas. Toda mensagem enviada fica marcada na conversa e você pode pausar com 1 clique.',
  'RAMON.COPILOTO.MODOS.piloto_total.NOME': () => 'Piloto total',
  'RAMON.COPILOTO.MODOS.piloto_total.DESC': () =>
    'A IA responde tudo sozinha. Toda mensagem fica carimbada e você pode pausar com 1 clique.',
};

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, params) => {
      const fn = translations[key];
      return fn ? fn(params || {}) : key;
    },
  }),
}));

const mountSelector = ({
  chat = { id: 42, custom_attributes: {} },
  updateCustomAttributes = vi.fn().mockResolvedValue(),
  toggleStatus = vi.fn().mockResolvedValue(),
} = {}) => {
  const store = createStore({
    state: () => ({ chat }),
    getters: { getSelectedChat: state => state.chat },
    actions: { updateCustomAttributes, toggleStatus },
  });
  const wrapper = mount(CopilotoModoSelector, {
    global: { plugins: [store] },
  });
  return { wrapper, store, updateCustomAttributes, toggleStatus };
};

// Simula o comportamento real da action: comita no store só no sucesso.
const updateQueComita = () =>
  vi.fn(({ state }, { customAttributes }) => {
    state.chat = { ...state.chat, custom_attributes: customAttributes };
  });

const escolherManual = async wrapper => {
  await wrapper.find('[data-testid="copiloto-modo-btn"]').trigger('click');
  await nextTick();
  await wrapper
    .find('[data-testid="copiloto-modo-opcao-manual"]')
    .trigger('click');
  await flushPromises();
};

describe('CopilotoModoSelector.vue', () => {
  it('opens a PENDING conversation when picking "Manual" (no handoff would leave it stuck with the bot)', async () => {
    const toggleStatus = vi.fn().mockResolvedValue();
    const { wrapper } = mountSelector({
      chat: { id: 42, status: 'pending', custom_attributes: {} },
      updateCustomAttributes: updateQueComita(),
      toggleStatus,
    });
    await escolherManual(wrapper);

    expect(toggleStatus).toHaveBeenCalledWith(expect.anything(), {
      conversationId: 42,
      status: 'open',
    });
  });

  it('does NOT touch the status when picking "Manual" on an already open conversation', async () => {
    const toggleStatus = vi.fn().mockResolvedValue();
    const { wrapper } = mountSelector({
      chat: { id: 42, status: 'open', custom_attributes: {} },
      updateCustomAttributes: updateQueComita(),
      toggleStatus,
    });
    await escolherManual(wrapper);

    expect(toggleStatus).not.toHaveBeenCalled();
  });

  it('does NOT open the conversation when saving the mode failed (store unchanged)', async () => {
    const toggleStatus = vi.fn().mockResolvedValue();
    const { wrapper } = mountSelector({
      chat: { id: 42, status: 'pending', custom_attributes: {} },
      updateCustomAttributes: vi.fn().mockResolvedValue(), // não comita
      toggleStatus,
    });
    await escolherManual(wrapper);

    expect(toggleStatus).not.toHaveBeenCalled();
  });

  it('shows the current mode on the button (defaults to Rascunho when the key is missing)', async () => {
    const { wrapper } = mountSelector();
    await flushPromises();
    const btn = wrapper.find('[data-testid="copiloto-modo-btn"]');
    expect(btn.exists()).toBe(true);
    expect(btn.text()).toContain('Rascunho');
  });

  it('lists the 4 modes with descriptions when the popup opens', async () => {
    const { wrapper } = mountSelector();
    await wrapper.find('[data-testid="copiloto-modo-btn"]').trigger('click');
    await nextTick();

    const manual = wrapper.find('[data-testid="copiloto-modo-opcao-manual"]');
    const rascunho = wrapper.find(
      '[data-testid="copiloto-modo-opcao-rascunho"]'
    );
    const limitado = wrapper.find(
      '[data-testid="copiloto-modo-opcao-piloto_limitado"]'
    );
    const total = wrapper.find(
      '[data-testid="copiloto-modo-opcao-piloto_total"]'
    );

    expect(manual.text()).toContain('Manual');
    expect(manual.text()).toContain('A IA não sugere nada');
    expect(rascunho.text()).toContain('Rascunho');
    expect(limitado.text()).toContain('Piloto com limites');
    expect(limitado.text()).toContain('Nunca envia: valores');
    expect(total.text()).toContain('Piloto total');
  });

  it('dispatches updateCustomAttributes with the full merged hash when picking "Piloto total"', async () => {
    const updateCustomAttributes = vi.fn().mockResolvedValue();
    const { wrapper } = mountSelector({
      chat: {
        id: 42,
        custom_attributes: { copiloto_modo: 'rascunho', foo: 'bar' },
      },
      updateCustomAttributes,
    });
    await wrapper.find('[data-testid="copiloto-modo-btn"]').trigger('click');
    await nextTick();

    await wrapper
      .find('[data-testid="copiloto-modo-opcao-piloto_total"]')
      .trigger('click');
    await flushPromises();

    expect(updateCustomAttributes).toHaveBeenCalledWith(expect.anything(), {
      conversationId: 42,
      customAttributes: { copiloto_modo: 'piloto_total', foo: 'bar' },
    });
  });

  it('updates the button label when custom_attributes changes via broadcast (getter reactivity)', async () => {
    const { wrapper, store } = mountSelector();
    await flushPromises();
    expect(wrapper.find('[data-testid="copiloto-modo-btn"]').text()).toContain(
      'Rascunho'
    );

    store.state.chat = {
      id: 42,
      custom_attributes: { copiloto_modo: 'piloto_total' },
    };
    await nextTick();

    expect(wrapper.find('[data-testid="copiloto-modo-btn"]').text()).toContain(
      'Piloto total'
    );
  });
});
