import { ref } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import RascunhoAcoes from '../RascunhoAcoes.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

const dispatch = vi.fn(async () => {});
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: (...args) => dispatch(...args) }),
}));

const useAlert = vi.fn();
vi.mock('dashboard/composables', () => ({
  useAlert: (...args) => useAlert(...args),
}));

const emit = vi.fn();
vi.mock('shared/helpers/mitt', () => ({
  emitter: { emit: (...args) => emit(...args) },
}));

const copyTextToClipboard = vi.fn(async () => {});
vi.mock('shared/helpers/clipboard', () => ({
  copyTextToClipboard: (...args) => copyTextToClipboard(...args),
}));

const content = ref('');
const conversationId = ref(19);
vi.mock('../provider.js', () => ({
  useMessageContext: () => ({ content, conversationId }),
}));

const NOTA =
  'RASCUNHO (revisar antes de enviar):\nSe desistir, você não paga nada.\n\nQuer seguir?';
const TEXTO = 'Se desistir, você não paga nada.\n\nQuer seguir?';

describe('RascunhoAcoes.vue', () => {
  beforeEach(() => {
    content.value = NOTA;
    dispatch.mockClear();
    emit.mockClear();
    useAlert.mockClear();
    copyTextToClipboard.mockClear();
  });

  it('Enviar manda só o texto (sem o cabeçalho RASCUNHO) como resposta pública, uma vez', async () => {
    const wrapper = mount(RascunhoAcoes);
    await wrapper.find('[data-testid="rascunho-enviar"]').trigger('click');
    await flushPromises();

    expect(dispatch).toHaveBeenCalledWith('createPendingMessageAndSend', {
      conversationId: 19,
      message: TEXTO,
      private: false,
    });
    expect(wrapper.find('[data-testid="rascunho-enviar"]').exists()).toBe(
      false
    );
    expect(wrapper.text()).toContain('RAMON.RASCUNHO_ACOES.ENVIADO');
  });

  it('modo enviar: só o botão Enviar (sem lápis/copiar)', () => {
    const wrapper = mount(RascunhoAcoes);

    expect(wrapper.find('[data-testid="rascunho-enviar"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="rascunho-editar"]').exists()).toBe(
      false
    );
  });

  it('Editar (lápis) põe o texto limpo na caixa de resposta, sem enviar', async () => {
    const wrapper = mount(RascunhoAcoes, { props: { modo: 'icones' } });
    await wrapper.find('[data-testid="rascunho-editar"]').trigger('click');

    expect(emit).toHaveBeenCalledWith('insertIntoNormalEditor', TEXTO);
    expect(dispatch).not.toHaveBeenCalled();
  });

  it('Copiar copia só o texto', async () => {
    const wrapper = mount(RascunhoAcoes, { props: { modo: 'icones' } });
    await wrapper.find('[data-testid="rascunho-copiar"]').trigger('click');
    await flushPromises();

    expect(copyTextToClipboard).toHaveBeenCalledWith(TEXTO);
    expect(useAlert).toHaveBeenCalledWith('RAMON.RASCUNHO_ACOES.COPIADO');
  });

  it('nota só com o cabeçalho (sem texto) não mostra botões', () => {
    content.value = 'RASCUNHO (revisar antes de enviar):';

    expect(
      mount(RascunhoAcoes).find('[data-testid="rascunho-acoes"]').exists()
    ).toBe(false);
  });
});
