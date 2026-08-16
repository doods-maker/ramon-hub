import { ref } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import PilotoCarimbo from '../PilotoCarimbo.vue';

const translations = {
  'RAMON.COPILOTO.CARIMBO': ({ modo }) => `enviada pelo piloto (${modo})`,
  'RAMON.COPILOTO.MODOS.piloto_total.NOME': () => 'Piloto total',
  'RAMON.COPILOTO.MODOS.piloto_limitado.NOME': () => 'Piloto com limites',
  'RAMON.COPILOTO.PAUSAR': () => 'Pausar piloto',
  'RAMON.COPILOTO.PAUSADO': () => 'Piloto pausado — voltou pro modo Rascunho.',
  'RAMON.COPILOTO.PAUSA_FALHOU': () => 'Não consegui pausar — tente de novo.',
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
// Por padrão simula o PATCH indo OK: a mutation do Vuex só comita quando o
// dispatch de fato tem sucesso, então mutar o getter mockado aqui reproduz
// isso. O teste de falha sobrescreve com um dispatch que resolve mas NÃO
// muta nada — reproduzindo o PATCH engolido pela action.
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

describe('PilotoCarimbo.vue', () => {
  beforeEach(() => {
    dispatch.mockClear();
    useAlert.mockClear();
  });

  it('renders the stamp with the translated mode when ramonPiloto is present', () => {
    currentChat.value = {
      id: 42,
      custom_attributes: { copiloto_modo: 'piloto_total' },
    };
    contentAttributes.value = {
      ramonPiloto: { modo: 'piloto_total', em: '2026-08-15T10:00:00Z' },
    };

    const wrapper = mount(PilotoCarimbo);
    const stamp = wrapper.find('[data-testid="piloto-carimbo"]');

    expect(stamp.exists()).toBe(true);
    expect(stamp.text()).toContain('enviada pelo piloto (Piloto total)');
  });

  it('clicking Pausar dispatches updateCustomAttributes with the full merge + copiloto_modo rascunho and shows the PAUSADO alert', async () => {
    currentChat.value = {
      id: 42,
      custom_attributes: { copiloto_modo: 'piloto_total', foo: 'bar' },
    };
    contentAttributes.value = {
      ramonPiloto: { modo: 'piloto_total', em: '2026-08-15T10:00:00Z' },
    };

    const wrapper = mount(PilotoCarimbo);
    await wrapper.find('[data-testid="piloto-pausar"]').trigger('click');
    await flushPromises();

    expect(dispatch).toHaveBeenCalledWith('updateCustomAttributes', {
      conversationId: 42,
      customAttributes: { copiloto_modo: 'rascunho', foo: 'bar' },
    });
    expect(useAlert).toHaveBeenCalledWith(
      'Piloto pausado — voltou pro modo Rascunho.'
    );
  });

  it('clicking Pausar when the PATCH silently fails (state stays piloto_*) shows PAUSA_FALHOU instead of a false PAUSADO', async () => {
    currentChat.value = {
      id: 42,
      custom_attributes: { copiloto_modo: 'piloto_total', foo: 'bar' },
    };
    contentAttributes.value = {
      ramonPiloto: { modo: 'piloto_total', em: '2026-08-15T10:00:00Z' },
    };
    // updateCustomAttributes engole o erro do PATCH: resolve sem rejeitar, mas
    // a mutation nunca comita — o getter mockado continua igual.
    dispatch.mockImplementationOnce(async () => {});

    const wrapper = mount(PilotoCarimbo);
    await wrapper.find('[data-testid="piloto-pausar"]').trigger('click');
    await flushPromises();

    expect(dispatch).toHaveBeenCalledWith('updateCustomAttributes', {
      conversationId: 42,
      customAttributes: { copiloto_modo: 'rascunho', foo: 'bar' },
    });
    expect(useAlert).toHaveBeenCalledWith(
      'Não consegui pausar — tente de novo.'
    );
    expect(useAlert).not.toHaveBeenCalledWith(
      'Piloto pausado — voltou pro modo Rascunho.'
    );
  });

  it('renders nothing without ramonPiloto', () => {
    currentChat.value = { id: 42, custom_attributes: {} };
    contentAttributes.value = {};

    const wrapper = mount(PilotoCarimbo);

    expect(wrapper.find('[data-testid="piloto-carimbo"]').exists()).toBe(false);
  });
});
