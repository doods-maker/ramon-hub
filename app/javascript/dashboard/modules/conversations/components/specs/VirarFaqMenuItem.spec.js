import { mount, flushPromises } from '@vue/test-utils';
import { useAlert } from 'dashboard/composables';
import FaqDeConversaAPI from 'dashboard/api/captain/faqDeConversa';
import VirarFaqMenuItem from '../VirarFaqMenuItem.vue';

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    accountScopedRoute: (name, params) => ({ name, params }),
  }),
}));
vi.mock('dashboard/api/captain/faqDeConversa', () => ({
  default: { virarFaq: vi.fn() },
}));

const montar = () =>
  mount(VirarFaqMenuItem, {
    props: { conversationId: 12, messageId: 345 },
    global: { stubs: { 'fluent-icon': true } },
  });

const clicar = async wrapper => {
  await wrapper.find('[data-testid="virar-faq"]').trigger('click');
  await flushPromises();
};

describe('Virar FAQ (menu da mensagem)', () => {
  it('cria a FAQ pendente e o aviso leva às pendentes do assistente', async () => {
    FaqDeConversaAPI.virarFaq.mockResolvedValue({
      data: { id: 9, assistant_id: 3, ja_existia: false },
    });
    const wrapper = montar();

    await clicar(wrapper);

    expect(FaqDeConversaAPI.virarFaq).toHaveBeenCalledWith(12, 345);
    expect(useAlert).toHaveBeenCalledWith(
      'FAQ created as pending. An administrator approves it before the assistant uses it.',
      {
        type: 'link',
        to: {
          name: 'captain_assistants_responses_pending',
          params: { assistantId: 3 },
        },
        message: 'See pending FAQs',
      }
    );
    expect(wrapper.emitted('close')).toHaveLength(1);
  });

  it('2º clique na mesma resposta avisa que já virou FAQ', async () => {
    FaqDeConversaAPI.virarFaq.mockResolvedValue({
      data: { id: 9, assistant_id: 3, ja_existia: true },
    });
    const wrapper = montar();

    await clicar(wrapper);

    expect(useAlert.mock.calls[0][0]).toBe(
      'This reply is already a FAQ (pending or approved).'
    );
  });

  it.each([
    ['SEM_PERGUNTA', 'No lead question found before this reply.'],
    ['QUALQUER', 'Could not create the FAQ. Try again.'],
  ])('erro %s vira texto claro', async (erro, texto) => {
    FaqDeConversaAPI.virarFaq.mockRejectedValue({
      response: { data: { erro } },
    });
    const wrapper = montar();

    await clicar(wrapper);

    expect(useAlert).toHaveBeenCalledWith(texto);
    expect(wrapper.emitted('close')).toHaveLength(1);
  });

  it('clique duplo enquanto envia chama a API uma vez', async () => {
    FaqDeConversaAPI.virarFaq.mockResolvedValue({
      data: { id: 9, assistant_id: 3, ja_existia: false },
    });
    const wrapper = montar();
    const item = wrapper.find('[data-testid="virar-faq"]');

    item.trigger('click');
    await item.trigger('click');
    await flushPromises();

    expect(FaqDeConversaAPI.virarFaq).toHaveBeenCalledTimes(1);
  });
});
