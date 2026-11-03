import { mount, flushPromises } from '@vue/test-utils';
import RamonAprovacoesAgenteAPI from 'dashboard/api/ramonAprovacoesAgente';
import { useAlert } from 'dashboard/composables';
import AprovacoesAgentes from '../AprovacoesAgentes.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: (k, v) => (v ? `${k}|${v.caso}|${v.ferramenta}` : k) }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/ramonAprovacoesAgente', () => ({
  default: { get: vi.fn(), update: vi.fn() },
}));

const PEDIDO = {
  id: 7,
  caso: '123',
  ferramenta: 'advbox_criar_tarefa',
  entrada: { descricao: 'resumo do caso' },
};

const ButtonStub = {
  props: ['label'],
  emits: ['click'],
  template: '<button @click="$emit(`click`)">{{ label }}</button>',
};

const montar = async () => {
  const tela = mount(AprovacoesAgentes, {
    global: { stubs: { Button: ButtonStub } },
  });
  await flushPromises();
  return tela;
};

const botao = (tela, texto) =>
  tela.findAll('button').find(item => item.text().includes(texto));

describe('AprovacoesAgentes', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    RamonAprovacoesAgenteAPI.get.mockResolvedValue({ data: [PEDIDO] });
    RamonAprovacoesAgenteAPI.update.mockResolvedValue({});
  });

  it('mostra o pedido, o caso, a ferramenta e o que será gravado', async () => {
    const tela = await montar();
    expect(tela.text()).toContain('123|advbox_criar_tarefa');
    expect(tela.text()).toContain('resumo do caso');
    tela.unmount();
  });

  it('sem pedido pendente, não ocupa espaço na tela', async () => {
    RamonAprovacoesAgenteAPI.get.mockResolvedValue({ data: [] });
    const tela = await montar();
    expect(tela.find('ul').exists()).toBe(false);
    tela.unmount();
  });

  it.each([
    ['APROVAR', 'aprovada'],
    ['NEGAR', 'negada'],
  ])('%s responde %s e tira o pedido da lista', async (texto, decisao) => {
    const tela = await montar();
    await botao(tela, texto).trigger('click');
    await flushPromises();
    expect(RamonAprovacoesAgenteAPI.update).toHaveBeenCalledWith(7, {
      decisao,
    });
    expect(tela.find('ul').exists()).toBe(false);
    tela.unmount();
  });

  it('se a resposta falha, avisa e mantém o pedido na lista', async () => {
    RamonAprovacoesAgenteAPI.update.mockRejectedValue(new Error('rede'));
    const tela = await montar();
    await botao(tela, 'APROVAR').trigger('click');
    await flushPromises();
    expect(useAlert).toHaveBeenCalled();
    expect(tela.text()).toContain('123|advbox_criar_tarefa');
    tela.unmount();
  });
});
