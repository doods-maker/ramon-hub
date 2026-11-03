import { mount, flushPromises } from '@vue/test-utils';
import RamonAprovacoesAgenteAPI from 'dashboard/api/ramonAprovacoesAgente';
import { useAlert } from 'dashboard/composables';
import AprovacoesAgentes from '../AprovacoesAgentes.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: k => k }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/ramonAprovacoesAgente', () => ({
  default: { get: vi.fn(), update: vi.fn() },
}));

const PEDIDO = {
  id: 7,
  caso: 'Maria Exemplo #123',
  ferramenta: 'mcp__advbox__advbox_criar_tarefa',
  nomes: { responsavel: 'Eduardo' },
  entrada: { responsavel_id: 5, descricao: 'SITUAÇÃO: resumo do caso' },
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

const clicar = async (tela, texto) => {
  await tela
    .findAll('button')
    .find(item => item.text().endsWith(texto))
    .trigger('click');
  await flushPromises();
};

describe('AprovacoesAgentes', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    RamonAprovacoesAgenteAPI.get.mockResolvedValue({ data: [PEDIDO] });
    RamonAprovacoesAgenteAPI.update.mockResolvedValue({});
  });

  it('mostra a ação em português, o cliente, a quem vai e o texto', async () => {
    const tela = await montar();
    expect(tela.text()).toContain('RAMON.AGENTES.APROVACOES.ACOES.TAREFA');
    expect(tela.text()).toContain('Maria Exemplo');
    expect(tela.text()).toContain('Eduardo');
    expect(tela.text()).toContain('SITUAÇÃO');
    expect(tela.text()).toContain('resumo do caso');
    tela.unmount();
  });

  it('sem pedido pendente, não ocupa espaço na tela', async () => {
    RamonAprovacoesAgenteAPI.get.mockResolvedValue({ data: [] });
    const tela = await montar();
    expect(tela.find('ul').exists()).toBe(false);
    tela.unmount();
  });

  it('aprovar responde e tira o pedido da lista', async () => {
    const tela = await montar();
    await clicar(tela, 'APROVAR');
    expect(RamonAprovacoesAgenteAPI.update).toHaveBeenCalledWith(7, {
      decisao: 'aprovada',
    });
    expect(tela.find('ul').exists()).toBe(false);
    tela.unmount();
  });

  it('negar sem motivo responde só a decisão', async () => {
    const tela = await montar();
    await clicar(tela, 'NEGAR');
    expect(RamonAprovacoesAgenteAPI.update).not.toHaveBeenCalled();
    await clicar(tela, 'CONFIRMAR_NEGATIVA');
    expect(RamonAprovacoesAgenteAPI.update).toHaveBeenCalledWith(7, {
      decisao: 'negada',
    });
    expect(tela.find('ul').exists()).toBe(false);
    tela.unmount();
  });

  it('negar com motivo leva a orientação', async () => {
    const tela = await montar();
    await clicar(tela, 'NEGAR');
    await tela.find('textarea').setValue('Use a tarefa que já existe');
    await clicar(tela, 'CONFIRMAR_NEGATIVA');
    expect(RamonAprovacoesAgenteAPI.update).toHaveBeenCalledWith(7, {
      decisao: 'negada',
      motivo: 'Use a tarefa que já existe',
    });
    tela.unmount();
  });

  it('voltar desiste da negativa sem responder', async () => {
    const tela = await montar();
    await clicar(tela, 'NEGAR');
    await clicar(tela, 'VOLTAR');
    expect(RamonAprovacoesAgenteAPI.update).not.toHaveBeenCalled();
    expect(tela.find('textarea').exists()).toBe(false);
    tela.unmount();
  });

  it('se a resposta falha, avisa e mantém o pedido na lista', async () => {
    RamonAprovacoesAgenteAPI.update.mockRejectedValue(new Error('rede'));
    const tela = await montar();
    await clicar(tela, 'APROVAR');
    expect(useAlert).toHaveBeenCalled();
    expect(tela.text()).toContain('Maria Exemplo');
    tela.unmount();
  });
});
