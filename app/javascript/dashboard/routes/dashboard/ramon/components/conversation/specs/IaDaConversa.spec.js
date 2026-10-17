import { mount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import { nextTick } from 'vue';
import IaDaConversa from '../IaDaConversa.vue';

const translations = {
  'RAMON.IA_CONVERSA.BTN': ({ perfil, origem, etapa }) =>
    `IA: ${perfil} (${origem}) · ${etapa}`,
  'RAMON.IA_CONVERSA.ORIGEM.tese': () => 'da tese',
  'RAMON.IA_CONVERSA.PAUSADA': () => 'IA pausada',
  'RAMON.IA_CONVERSA.RASCUNHO': () => 'Só rascunho',
};
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, params) => {
      const fn = translations[key];
      return fn ? fn(params || {}) : key;
    },
  }),
}));

const push = vi.fn();
vi.mock('vue-router', () => ({ useRouter: () => ({ push }) }));

const get = vi.fn();
vi.mock('dashboard/api/ramonIaConversas', () => ({
  default: { get: (...args) => get(...args) },
}));

const INFO = {
  perfil: 'Equilibrada',
  origem: 'tese',
  etapa: 'Qualificação',
  pausa: null,
  alvo: 'tese:3',
};

// Simula a action real: comita no store só no sucesso.
const comita = ({ state }, { customAttributes }) => {
  state.chat = { ...state.chat, custom_attributes: customAttributes };
};

const montar = ({
  chat = { id: 42, status: 'open', custom_attributes: { foo: 'bar' } },
  updateCustomAttributes = vi.fn(comita),
} = {}) => {
  const toggleStatus = vi.fn();
  const assignAgent = vi.fn();
  const store = createStore({
    state: () => ({ chat }),
    getters: {
      getSelectedChat: state => state.chat,
      getCurrentUser: () => ({ id: 7 }),
    },
    actions: { updateCustomAttributes, toggleStatus, assignAgent },
  });
  const wrapper = mount(IaDaConversa, { global: { plugins: [store] } });
  return { wrapper, store, updateCustomAttributes, toggleStatus, assignAgent };
};

const abrir = async wrapper => {
  await flushPromises();
  await wrapper.find('[data-testid="ia-conversa-btn"]').trigger('click');
  await nextTick();
};
const clicar = async (wrapper, id) => {
  await wrapper.find(`[data-testid="ia-conversa-${id}"]`).trigger('click');
  await flushPromises();
};

describe('IaDaConversa.vue', () => {
  beforeEach(() => {
    get.mockReset().mockResolvedValue({ data: INFO });
    push.mockClear();
  });

  it('mostra perfil, origem e etapa', async () => {
    const { wrapper } = montar();
    await flushPromises();

    expect(get).toHaveBeenCalledWith(42);
    expect(wrapper.find('[data-testid="ia-conversa-btn"]').text()).toBe(
      'IA: Equilibrada (da tese) · Qualificação'
    );
  });

  it('pausada mostra o estado no lugar do perfil', async () => {
    const { wrapper } = montar({
      chat: { id: 42, custom_attributes: { ia_pausa: 'pausada' } },
    });
    await flushPromises();

    expect(wrapper.find('[data-testid="ia-conversa-btn"]').text()).toBe(
      'IA pausada'
    );
  });

  it('Pausar grava ia_pausa pausada (merge completo) e abre a conversa pendente', async () => {
    const { wrapper, updateCustomAttributes, toggleStatus } = montar({
      chat: { id: 42, status: 'pending', custom_attributes: { foo: 'bar' } },
    });
    await abrir(wrapper);
    await clicar(wrapper, 'pausar');

    expect(updateCustomAttributes).toHaveBeenCalledWith(expect.anything(), {
      conversationId: 42,
      customAttributes: { foo: 'bar', ia_pausa: 'pausada' },
    });
    expect(toggleStatus).toHaveBeenCalledWith(expect.anything(), {
      conversationId: 42,
      status: 'open',
    });
  });

  it('não abre a conversa quando a gravação falhou (store igual)', async () => {
    const { wrapper, toggleStatus } = montar({
      chat: { id: 42, status: 'pending', custom_attributes: {} },
      updateCustomAttributes: vi.fn(),
    });
    await abrir(wrapper);
    await clicar(wrapper, 'pausar');

    expect(toggleStatus).not.toHaveBeenCalled();
  });

  it('Só rascunho grava rascunho e não mexe no status', async () => {
    const { wrapper, updateCustomAttributes, toggleStatus } = montar({
      chat: { id: 42, status: 'pending', custom_attributes: {} },
    });
    await abrir(wrapper);
    await clicar(wrapper, 'rascunho');

    expect(updateCustomAttributes).toHaveBeenCalledWith(expect.anything(), {
      conversationId: 42,
      customAttributes: { ia_pausa: 'rascunho' },
    });
    expect(toggleStatus).not.toHaveBeenCalled();
  });

  it('Voltar a seguir o perfil tira a chave', async () => {
    const { wrapper, updateCustomAttributes } = montar({
      chat: { id: 42, custom_attributes: { foo: 'bar', ia_pausa: 'rascunho' } },
    });
    await abrir(wrapper);
    await clicar(wrapper, 'voltar');

    expect(updateCustomAttributes).toHaveBeenCalledWith(expect.anything(), {
      conversationId: 42,
      customAttributes: { foo: 'bar' },
    });
  });

  it('Ver na trilha vai para a tela com ?alvo=', async () => {
    const { wrapper } = montar();
    await abrir(wrapper);
    await clicar(wrapper, 'trilha');

    expect(push).toHaveBeenCalledWith({
      name: 'captain_como_ia_atende_index',
      query: { alvo: 'tese:3' },
    });
  });

  it('Assumir atribui a mim e pausa a IA', async () => {
    const { wrapper, assignAgent, updateCustomAttributes } = montar();
    await abrir(wrapper);
    await clicar(wrapper, 'assumir');

    expect(assignAgent).toHaveBeenCalledWith(expect.anything(), {
      conversationId: 42,
      agentId: 7,
    });
    expect(updateCustomAttributes).toHaveBeenCalledWith(expect.anything(), {
      conversationId: 42,
      customAttributes: { foo: 'bar', ia_pausa: 'pausada' },
    });
  });

  it('refaz a leitura quando a pausa muda', async () => {
    const { wrapper, store } = montar();
    await flushPromises();
    store.state.chat = { id: 42, custom_attributes: { ia_pausa: 'rascunho' } };
    await flushPromises();

    expect(get).toHaveBeenCalledTimes(2);
    expect(wrapper.find('[data-testid="ia-conversa-btn"]').text()).toBe(
      'Só rascunho'
    );
  });
});
