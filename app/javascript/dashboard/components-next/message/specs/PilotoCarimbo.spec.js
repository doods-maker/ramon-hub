import { ref } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import PilotoCarimbo from '../PilotoCarimbo.vue';

const translations = {
  'RAMON.IA_CONVERSA.CARIMBO': ({ perfil }) => `enviada pela IA (${perfil})`,
  'RAMON.IA_CONVERSA.PAUSAR_CARIMBO': () => 'Pausar',
  'RAMON.IA_CONVERSA.PAUSADO': () => 'IA em só rascunho nesta conversa.',
  'RAMON.IA_CONVERSA.PAUSA_FALHOU': () =>
    'Não consegui pausar — tente de novo.',
};

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, params) => {
      const fn = translations[key];
      return fn ? fn(params || {}) : key;
    },
  }),
}));

const currentChat = ref(null);
// A mutation do Vuex só comita quando o PATCH dá certo; mutar o getter mockado reproduz isso.
const dispatch = vi.fn(async (action, { customAttributes }) => {
  currentChat.value = {
    ...currentChat.value,
    custom_attributes: customAttributes,
  };
});
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: (...args) => dispatch(...args) }),
  useMapGetter: () => currentChat,
}));

const useAlert = vi.fn();
vi.mock('dashboard/composables', () => ({
  useAlert: (...args) => useAlert(...args),
}));

const contentAttributes = ref({});
vi.mock('../provider.js', () => ({
  useMessageContext: () => ({ contentAttributes }),
}));

const carimbo = {
  ramonPiloto: { perfil: 'Equilibrada', alvo: 'padrao', etapa: 'fase-novo' },
};

describe('PilotoCarimbo.vue', () => {
  beforeEach(() => {
    dispatch.mockClear();
    useAlert.mockClear();
  });

  it('mostra o perfil do carimbo', () => {
    currentChat.value = { id: 42, custom_attributes: {} };
    contentAttributes.value = carimbo;

    const stamp = mount(PilotoCarimbo).find('[data-testid="piloto-carimbo"]');

    expect(stamp.text()).toContain('enviada pela IA (Equilibrada)');
  });

  it('Pausar grava ia_pausa rascunho com o merge completo e avisa', async () => {
    currentChat.value = { id: 42, custom_attributes: { foo: 'bar' } };
    contentAttributes.value = carimbo;

    const wrapper = mount(PilotoCarimbo);
    await wrapper.find('[data-testid="piloto-pausar"]').trigger('click');
    await flushPromises();

    expect(dispatch).toHaveBeenCalledWith('updateCustomAttributes', {
      conversationId: 42,
      customAttributes: { foo: 'bar', ia_pausa: 'rascunho' },
    });
    expect(useAlert).toHaveBeenCalledWith('IA em só rascunho nesta conversa.');
  });

  it('PATCH engolido (estado não muda) avisa a falha, não um falso sucesso', async () => {
    currentChat.value = { id: 42, custom_attributes: {} };
    contentAttributes.value = carimbo;
    dispatch.mockImplementationOnce(async () => {});

    const wrapper = mount(PilotoCarimbo);
    await wrapper.find('[data-testid="piloto-pausar"]').trigger('click');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith(
      'Não consegui pausar — tente de novo.'
    );
  });

  it('conversa já pausada: sem o botão Pausar', () => {
    currentChat.value = { id: 42, custom_attributes: { ia_pausa: 'pausada' } };
    contentAttributes.value = carimbo;

    const wrapper = mount(PilotoCarimbo);

    expect(wrapper.find('[data-testid="piloto-pausar"]').exists()).toBe(false);
  });

  it('sem ramonPiloto não mostra nada', () => {
    currentChat.value = { id: 42, custom_attributes: {} };
    contentAttributes.value = {};

    expect(
      mount(PilotoCarimbo).find('[data-testid="piloto-carimbo"]').exists()
    ).toBe(false);
  });
});
