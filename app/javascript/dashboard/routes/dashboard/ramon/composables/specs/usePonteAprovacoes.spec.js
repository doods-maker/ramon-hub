import { defineComponent, h, ref, shallowRef } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import RamonAprovacoesAgenteAPI from 'dashboard/api/ramonAprovacoesAgente';
import { usePonteAprovacoes } from '../usePonteAprovacoes';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: (k, p) => (p ? `${k} ${JSON.stringify(p)}` : k) }),
}));
vi.mock('dashboard/api/ramonAprovacoesAgente', () => ({
  default: { get: vi.fn(), update: vi.fn() },
}));

const ORIGEM = 'https://painel.example.com:8443';
const PEDIDO = {
  id: 7,
  caso: 'Maria Exemplo #123',
  ferramenta: 'mcp__advbox__advbox_criar_tarefa',
  nomes: { responsavel: 'Eduardo' },
  entrada: { responsavel_id: 5, descricao: 'SITUAÇÃO: resumo do caso' },
  created_at: '2026-11-07T10:00:00Z',
};

let painel;
let tela;

const montar = () => {
  painel = { postMessage: vi.fn() };
  const Host = defineComponent({
    setup() {
      usePonteAprovacoes(
        shallowRef({ contentWindow: painel }),
        ref(`${ORIGEM}/`)
      );
      return () => h('div');
    },
  });
  tela = mount(Host);
};

// O MessageEvent do jsdom não aceita janela de mentira em `source`.
const chegar = (data, { origin = ORIGEM, source = painel } = {}) => {
  const evento = new Event('message');
  Object.assign(evento, { data, origin, source });
  window.dispatchEvent(evento);
  return flushPromises();
};

const ouvir = (extra = {}) =>
  chegar({ fonte: 'painel-agentes', tipo: 'ouvir' }, extra);
const enviadas = tipo =>
  painel.postMessage.mock.calls.filter(([msg]) => msg.tipo === tipo);

describe('usePonteAprovacoes', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    RamonAprovacoesAgenteAPI.get.mockReset();
    RamonAprovacoesAgenteAPI.update.mockReset();
    RamonAprovacoesAgenteAPI.get.mockResolvedValue({
      data: { pode_decidir: true, pedidos: [PEDIDO] },
    });
    montar();
  });

  afterEach(() => {
    tela.unmount();
    vi.useRealTimers();
  });

  it('ignora outra origem, outra janela e fonte errada', async () => {
    await ouvir({ origin: 'https://outro.example.com' });
    await ouvir({ source: { postMessage: vi.fn() } });
    await chegar({ fonte: 'hub', tipo: 'ouvir' });
    await chegar('ouvir');
    expect(RamonAprovacoesAgenteAPI.get).not.toHaveBeenCalled();
    expect(painel.postMessage).not.toHaveBeenCalled();
  });

  it('ouvir manda a lista descrita, só para a origem do painel', async () => {
    await ouvir();
    expect(painel.postMessage).toHaveBeenCalledWith(
      {
        fonte: 'hub',
        tipo: 'aprovacoes',
        podeDecidir: true,
        itens: [
          {
            id: 7,
            titulo:
              'RAMON.AGENTES.APROVACOES.ACOES.TAREFA {"ferramenta":"advbox_criar_tarefa"}',
            linhas: [
              'Maria Exemplo · RAMON.AGENTES.APROVACOES.CASO {"numero":"123"}',
              'RAMON.AGENTES.APROVACOES.CAMPOS.PARA: Eduardo',
              'SITUAÇÃO: resumo do caso',
            ],
            entrada: JSON.stringify(PEDIDO.entrada, null, 2),
            criadoEm: PEDIDO.created_at,
          },
        ],
      },
      ORIGEM
    );
  });

  it('corta a entrada em 4000 caracteres', async () => {
    RamonAprovacoesAgenteAPI.get.mockResolvedValue({
      data: {
        pode_decidir: false,
        pedidos: [{ ...PEDIDO, entrada: { texto: 'x'.repeat(5000) } }],
      },
    });
    await ouvir();
    const [[msg]] = enviadas('aprovacoes');
    expect(msg.podeDecidir).toBe(false);
    expect(msg.itens[0].entrada).toHaveLength(4000);
  });

  it('repete a cada 5 s enquanto houve ouvir no último minuto', async () => {
    await ouvir();
    await vi.advanceTimersByTimeAsync(5000);
    expect(RamonAprovacoesAgenteAPI.get).toHaveBeenCalledTimes(2);

    await vi.advanceTimersByTimeAsync(60000);
    const chamadas = RamonAprovacoesAgenteAPI.get.mock.calls.length;
    await vi.advanceTimersByTimeAsync(20000);
    expect(RamonAprovacoesAgenteAPI.get).toHaveBeenCalledTimes(chamadas);

    await ouvir();
    expect(RamonAprovacoesAgenteAPI.get).toHaveBeenCalledTimes(chamadas + 1);
  });

  it('para de consultar ao sair da tela', async () => {
    await ouvir();
    tela.unmount();
    await vi.advanceTimersByTimeAsync(20000);
    expect(RamonAprovacoesAgenteAPI.get).toHaveBeenCalledTimes(1);
    await ouvir();
    expect(RamonAprovacoesAgenteAPI.get).toHaveBeenCalledTimes(1);
    montar(); // o afterEach desmonta de novo
  });

  it('decidir chama a API e responde decidida; motivo só na negativa', async () => {
    RamonAprovacoesAgenteAPI.update.mockResolvedValue({});
    const base = { fonte: 'painel-agentes', tipo: 'decidir', id: 7 };
    await chegar({ ...base, decisao: 'negada', motivo: 'já existe' });
    await chegar({ ...base, decisao: 'aprovada', motivo: 'x' });
    expect(RamonAprovacoesAgenteAPI.update.mock.calls).toEqual([
      [7, { decisao: 'negada', motivo: 'já existe' }],
      [7, { decisao: 'aprovada' }],
    ]);
    expect(enviadas('decidida').map(([msg, origem]) => [msg, origem])).toEqual([
      [{ fonte: 'hub', tipo: 'decidida', id: 7, ok: true }, ORIGEM],
      [{ fonte: 'hub', tipo: 'decidida', id: 7, ok: true }, ORIGEM],
    ]);
  });

  it.each([
    [409, 'ja_decidida'],
    [422, 'invalida'],
    [403, 'proibido'],
    [500, 'falha'],
    [undefined, 'falha'],
  ])('decidir com HTTP %s responde erro %s', async (status, erro) => {
    RamonAprovacoesAgenteAPI.update.mockRejectedValue(
      status ? { response: { status } } : new Error('rede')
    );
    await chegar({
      fonte: 'painel-agentes',
      tipo: 'decidir',
      id: 7,
      decisao: 'aprovada',
    });
    expect(enviadas('decidida')[0][0]).toEqual({
      fonte: 'hub',
      tipo: 'decidida',
      id: 7,
      ok: false,
      erro,
    });
  });

  it('decidir sem id numérico nem chega à API', async () => {
    await chegar({
      fonte: 'painel-agentes',
      tipo: 'decidir',
      id: '7/../8',
      decisao: 'aprovada',
    });
    expect(RamonAprovacoesAgenteAPI.update).not.toHaveBeenCalled();
  });
});
