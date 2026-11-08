import { mount, flushPromises } from '@vue/test-utils';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));
vi.mock('dashboard/api/ramonPainelAgentes', () => ({
  default: { get: vi.fn() },
}));
vi.mock('../../composables/usePonteAprovacoes', () => ({
  usePonteAprovacoes: vi.fn(),
}));

// O pedido é único por carga da página: cada caso precisa de um módulo novo.
const montar = async url => {
  vi.resetModules();
  const { default: API } = await import('dashboard/api/ramonPainelAgentes');
  API.get.mockResolvedValue({ data: { url } });
  const { usePonteAprovacoes } = await import(
    '../../composables/usePonteAprovacoes'
  );
  const { default: PainelAgentes } = await import('../PainelAgentes.vue');
  const tela = mount(PainelAgentes, {
    global: { stubs: { RamonPageHeader: true } },
  });
  await flushPromises();
  return { tela, ponte: usePonteAprovacoes.mock.calls[0] };
};

describe('PainelAgentes', () => {
  it('mostra o painel no endereço que o hub entregou', async () => {
    const { tela } = await montar('https://painel.example.com:8443/');
    expect(tela.find('iframe').attributes('src')).toBe(
      'https://painel.example.com:8443/'
    );
  });

  it('a ponte das aprovações fala com o iframe do painel, no endereço dele', async () => {
    const { tela, ponte } = await montar('https://painel.example.com:8443/');
    const [iframe, url] = ponte;
    expect(iframe.value).toBe(tela.find('iframe').element);
    expect(url.value).toBe('https://painel.example.com:8443/');
  });

  it('sem endereço, avisa que não há acesso e não abre nada', async () => {
    const { tela } = await montar(null);
    expect(tela.find('iframe').exists()).toBe(false);
    expect(tela.text()).toContain('RAMON.AGENTES.SEM_ACESSO');
  });
});
