import { mount, flushPromises } from '@vue/test-utils';
import CaptainAssistant from 'dashboard/api/captain/assistant';
import TextoFinal from '../TextoFinal.vue';

vi.mock('dashboard/api/captain/assistant', () => ({
  default: { textoFinal: vi.fn() },
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

describe('TextoFinal (I-CF6)', () => {
  it('mostra o texto do assistente e o de cada skill', async () => {
    CaptainAssistant.textoFinal.mockResolvedValue({
      data: {
        assistente: 'Você é o Atendimento.',
        skills: [{ title: 'Funil hoje', texto: 'Use funil_hoje.' }],
      },
    });
    const wrapper = mount(TextoFinal, {
      props: { assistantId: 1 },
      global: { stubs: { Button: true } },
    });
    await flushPromises();
    expect(CaptainAssistant.textoFinal).toHaveBeenCalledWith(1);
    expect(wrapper.findAll('pre').map(pre => pre.text())).toEqual([
      'Você é o Atendimento.',
      'Use funil_hoje.',
    ]);
  });

  it('erro vira aviso, sem quebrar', async () => {
    CaptainAssistant.textoFinal.mockRejectedValue(new Error('x'));
    const wrapper = mount(TextoFinal, {
      props: { assistantId: 1 },
      global: { stubs: { Button: true } },
    });
    await flushPromises();
    expect(wrapper.text()).toContain('INTEL.CONFIG.TEXTO_FINAL_ERRO');
  });
});
