import { mount, flushPromises } from '@vue/test-utils';
import CaptainAssistant from 'dashboard/api/captain/assistant';
import PassoAPasso from '../PassoAPasso.vue';

vi.mock('dashboard/api/captain/assistant', () => ({
  default: {
    passosAPasso: vi.fn(),
    subirPassoAPasso: vi.fn(),
    removerPassoAPasso: vi.fn(),
  },
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

const corpo = (ligado, url = null) => ({
  data: {
    ligado,
    temas: [
      { tema: 'meu_inss_cnis', nome: url && 'meu_inss_cnis.png', url },
      { tema: 'meu_inss_cat', nome: null, url: null },
    ],
  },
});
const montar = async () => {
  const wrapper = mount(PassoAPasso, {
    props: { assistantId: 7 },
    global: { stubs: { Button: true } },
  });
  await flushPromises();
  return wrapper;
};

describe('PassoAPasso (imagens por tema, etapa Documentos)', () => {
  it('só aceita JPG e PNG; recusa do servidor aparece com o motivo dele', async () => {
    CaptainAssistant.passosAPasso.mockResolvedValue(corpo(true));
    CaptainAssistant.subirPassoAPasso.mockRejectedValue({
      response: { data: { error: 'envie uma imagem JPG ou PNG de até 5 MB' } },
    });
    const wrapper = await montar();
    const input = wrapper.find(
      '[data-testid="tema-meu_inss_cat"] input[type="file"]'
    );
    expect(input.attributes('accept')).toBe('image/jpeg,image/png');

    const arquivo = new File(['x'], 'print.gif', { type: 'image/gif' });
    Object.defineProperty(input.element, 'files', { value: [arquivo] });
    await input.trigger('change');
    await flushPromises();
    expect(wrapper.text()).toContain('envie uma imagem JPG ou PNG de até 5 MB');
  });

  it('chave desligada: a seção nem aparece', async () => {
    CaptainAssistant.passosAPasso.mockResolvedValue(corpo(false));
    const wrapper = await montar();
    expect(CaptainAssistant.passosAPasso).toHaveBeenCalledWith(7);
    expect(wrapper.find('[data-testid="passo-a-passo"]').exists()).toBe(false);
  });

  it('um tema por linha, com a imagem quando há; escolher arquivo sobe pelo tema', async () => {
    CaptainAssistant.passosAPasso.mockResolvedValue(corpo(true, '/blob/1'));
    CaptainAssistant.subirPassoAPasso.mockResolvedValue(corpo(true, '/blob/2'));
    const wrapper = await montar();
    expect(
      wrapper.find('[data-testid="tema-meu_inss_cnis"] img').attributes('src')
    ).toBe('/blob/1');
    expect(wrapper.find('[data-testid="tema-meu_inss_cat"] img').exists()).toBe(
      false
    );

    const input = wrapper.find(
      '[data-testid="tema-meu_inss_cat"] input[type="file"]'
    );
    const arquivo = new File(['x'], 'print.png', { type: 'image/png' });
    Object.defineProperty(input.element, 'files', { value: [arquivo] });
    await input.trigger('change');
    await flushPromises();
    expect(CaptainAssistant.subirPassoAPasso).toHaveBeenCalledWith(
      7,
      'meu_inss_cat',
      arquivo
    );
    expect(
      wrapper.find('[data-testid="tema-meu_inss_cnis"] img').attributes('src')
    ).toBe('/blob/2');
  });
});
