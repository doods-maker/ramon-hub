import { mount, flushPromises } from '@vue/test-utils';
import CaptainAssistantAPI from 'dashboard/api/captain/assistant';
import TestarPergunta from '../TestarPergunta.vue';

vi.mock('dashboard/api/captain/assistant', () => ({
  default: { buscarFaq: vi.fn() },
}));

const montar = () => mount(TestarPergunta, { props: { assistantId: 1 } });
const perguntar = async (wrapper, texto) => {
  await wrapper.find('[data-testid="testar-pergunta-campo"]').setValue(texto);
  await wrapper.find('form').trigger('submit');
  await flushPromises();
};

describe('TestarPergunta.vue', () => {
  it('mostra as FAQs que o assistente acharia, na ordem da busca', async () => {
    CaptainAssistantAPI.buscarFaq.mockResolvedValue({
      data: {
        payload: [
          {
            id: 7,
            question: 'Posso trabalhar recebendo auxílio-acidente?',
            answer: 'Pode.',
            tese: 'auxilio-acidente',
          },
          { id: 3, question: 'Quanto custa?', answer: '30% + 3.', tese: null },
        ],
      },
    });
    const wrapper = montar();
    await perguntar(wrapper, '  posso trabalhar?  ');

    expect(CaptainAssistantAPI.buscarFaq).toHaveBeenCalledWith(
      1,
      'posso trabalhar?'
    );
    const itens = wrapper.findAll('[data-testid="testar-pergunta-faq"]');
    expect(itens).toHaveLength(2);
    expect(itens[0].text()).toContain('Posso trabalhar recebendo');
    expect(itens[0].text()).toContain('Accident benefit');
    expect(itens[1].text()).toContain('Quanto custa?');
  });

  it('nenhuma FAQ: avisa que vale criar uma', async () => {
    CaptainAssistantAPI.buscarFaq.mockResolvedValue({ data: { payload: [] } });
    const wrapper = montar();
    await perguntar(wrapper, 'foguete lunar');
    expect(wrapper.find('[data-testid="testar-pergunta-nada"]').exists()).toBe(
      true
    );
  });

  it('em branco não chama a API', async () => {
    const wrapper = montar();
    await perguntar(wrapper, '   ');
    expect(CaptainAssistantAPI.buscarFaq).not.toHaveBeenCalled();
  });

  it('erro da API: mensagem, sem lista', async () => {
    CaptainAssistantAPI.buscarFaq.mockRejectedValue(new Error('500'));
    const wrapper = montar();
    await perguntar(wrapper, 'posso trabalhar?');
    expect(wrapper.text()).toContain('Could not test right now');
    expect(wrapper.findAll('[data-testid="testar-pergunta-faq"]')).toHaveLength(
      0
    );
  });
});
