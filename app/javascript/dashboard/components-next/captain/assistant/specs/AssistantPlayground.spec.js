import { mount, flushPromises } from '@vue/test-utils';
import CaptainAssistant from 'dashboard/api/captain/assistant';
import AssistantPlayground from '../AssistantPlayground.vue';
import { conversaDe, limparConversa } from '../testarConversas';

vi.mock('dashboard/api/captain/assistant', () => ({
  default: { playground: vi.fn() },
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

const enviar = async (wrapper, texto) => {
  const campo = wrapper.find('input');
  await campo.setValue(texto);
  await campo.trigger('keydown', { key: 'Enter' });
};

describe('AssistantPlayground', () => {
  beforeEach(() => {
    limparConversa(1);
    limparConversa(2);
    CaptainAssistant.playground.mockReset();
  });

  it('mostra as ferramentas usadas debaixo da resposta (I-PG2)', async () => {
    CaptainAssistant.playground.mockResolvedValue({
      data: {
        response: 'Pronto',
        ferramentas: [
          {
            id: 'mover_etapa',
            title: 'Mover de etapa',
            nivel: 'sugestao',
            status: 'ok',
          },
          {
            id: 'checar_prescricao',
            title: 'Checar prescrição',
            nivel: 'consulta',
            status: 'erro',
          },
        ],
      },
    });
    const wrapper = mount(AssistantPlayground, { props: { assistantId: 1 } });
    await enviar(wrapper, 'prepare a reunião');
    await flushPromises();
    const chips = wrapper.findAll('[data-testid="testar-ferramenta"]');
    expect(chips.map(chip => chip.text())).toEqual([
      'Mover de etapa',
      'INTEL.TESTAR.FERRAMENTA_ERRO',
    ]);
  });

  it('trocar de assistente e voltar mantém a conversa (I-PG3)', async () => {
    CaptainAssistant.playground.mockResolvedValue({ data: { response: 'Oi' } });
    const wrapper = mount(AssistantPlayground, { props: { assistantId: 1 } });
    await enviar(wrapper, 'olá');
    await flushPromises();
    await wrapper.setProps({ assistantId: 2 });
    expect(conversaDe(2)).toHaveLength(0);
    await wrapper.setProps({ assistantId: 1 });
    expect(conversaDe(1)).toHaveLength(2);
  });

  it('resposta atrasada vai para a conversa de quem perguntou', async () => {
    let responder;
    CaptainAssistant.playground.mockReturnValue(
      new Promise(resolve => {
        responder = resolve;
      })
    );
    const wrapper = mount(AssistantPlayground, { props: { assistantId: 1 } });
    await enviar(wrapper, 'olá');
    await wrapper.setProps({ assistantId: 2 });
    responder({ data: { response: 'Oi' } });
    await flushPromises();
    expect(conversaDe(1).map(m => m.sender)).toEqual(['user', 'assistant']);
    expect(conversaDe(2)).toHaveLength(0);
  });

  it('escrever e anexar mexem só no campo', async () => {
    const wrapper = mount(AssistantPlayground, { props: { assistantId: 1 } });
    wrapper.vm.escrever('Prepare a reunião deste caso.');
    wrapper.vm.anexar('caso 12 (Maria)');
    await flushPromises();
    expect(wrapper.find('input').element.value).toBe(
      'Prepare a reunião deste caso. caso 12 (Maria)'
    );
    expect(CaptainAssistant.playground).not.toHaveBeenCalled();
  });
});
