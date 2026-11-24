import { mount, flushPromises } from '@vue/test-utils';
import BiEscritorio from '../BiEscritorio.vue';
import RamonBiAPI from 'dashboard/api/ramonBi';

const t = (key, params) => (params ? `${key} ${JSON.stringify(params)}` : key);
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t }) }));

vi.mock('dashboard/api/ramonBi', () => ({
  default: { get: vi.fn(), enviar: vi.fn() },
}));

const HTML_A = '<html><body>teste</body></html>';
const HTML_B = '<html><body>teste novo</body></html>';
const enviado = html => ({
  data: {
    enviado: true,
    html,
    enviado_em: '2026-11-23T12:00:00Z',
    enviado_por: 'Fulano',
  },
});

const mountPage = () => mount(BiEscritorio);

const escolher = async (wrapper, nome = 'bi.html') => {
  const input = wrapper.find('input[type="file"]');
  const file = new File([HTML_B], nome, { type: 'text/html' });
  Object.defineProperty(input.element, 'files', { value: [file] });
  await input.trigger('change');
  await flushPromises();
  return file;
};

describe('BiEscritorio', () => {
  beforeEach(() => vi.clearAllMocks());

  it('sem versão enviada mostra VAZIO e o botão, sem iframe', async () => {
    RamonBiAPI.get.mockResolvedValue({ data: { enviado: false } });
    const wrapper = mountPage();
    await flushPromises();
    expect(wrapper.text()).toContain('RAMON.BI_ESCRITORIO.VAZIO');
    expect(wrapper.text()).toContain('RAMON.BI_ESCRITORIO.ENVIAR');
    expect(wrapper.find('iframe').exists()).toBe(false);
  });

  it('com versão enviada mostra iframe sandbox allow-scripts com o html', async () => {
    RamonBiAPI.get.mockResolvedValue(enviado(HTML_A));
    const wrapper = mountPage();
    await flushPromises();
    const iframe = wrapper.find('iframe');
    expect(iframe.attributes('sandbox')).toBe('allow-scripts');
    expect(iframe.attributes('srcdoc')).toBe(HTML_A);
    expect(wrapper.text()).toContain('Fulano');
  });

  it('escolher arquivo envia e troca o srcdoc pelo novo html', async () => {
    RamonBiAPI.get.mockResolvedValue(enviado(HTML_A));
    RamonBiAPI.enviar.mockResolvedValue(enviado(HTML_B));
    const wrapper = mountPage();
    await flushPromises();
    const file = await escolher(wrapper);
    expect(RamonBiAPI.enviar).toHaveBeenCalledWith(file);
    expect(wrapper.find('iframe').attributes('srcdoc')).toBe(HTML_B);
  });

  it('erro 422 mostra a mensagem do servidor e mantém o iframe anterior', async () => {
    RamonBiAPI.get.mockResolvedValue(enviado(HTML_A));
    RamonBiAPI.enviar.mockRejectedValue({
      response: { status: 422, data: { error: 'Arquivo inválido' } },
    });
    const wrapper = mountPage();
    await flushPromises();
    await escolher(wrapper);
    expect(wrapper.text()).toContain('Arquivo inválido');
    expect(wrapper.find('iframe').attributes('srcdoc')).toBe(HTML_A);
  });

  it('arquivo que não é .html nem chega ao servidor: ERRO_TIPO', async () => {
    RamonBiAPI.get.mockResolvedValue(enviado(HTML_A));
    const wrapper = mountPage();
    await flushPromises();
    await escolher(wrapper, 'dados.pdf');
    expect(RamonBiAPI.enviar).not.toHaveBeenCalled();
    expect(wrapper.text()).toContain('RAMON.BI_ESCRITORIO.ERRO_TIPO');
  });
});
