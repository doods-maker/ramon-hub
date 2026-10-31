import { setActivePinia, createPinia } from 'pinia';
import { useChatStore } from './chat';
import ChatAPI from 'dashboard/api/ramonChat';

vi.mock('dashboard/api/ramonChat', () => ({
  default: {
    get: vi.fn(),
    mensagens: vi.fn(),
    enviar: vi.fn(),
    ler: vi.fn(() => Promise.resolve()),
    direto: vi.fn(),
  },
}));

const canal = (over = {}) => ({
  id: 1,
  tipo: 'geral',
  nome: null,
  participante: true,
  nao_lidas: 0,
  ...over,
});
const msg = (over = {}) => ({
  id: 100,
  canal_id: 1,
  conteudo: 'oi',
  autor: { id: 20, name: 'Brenda' },
  ...over,
});

describe('useChatStore', () => {
  let store;

  beforeEach(() => {
    vi.clearAllMocks();
    setActivePinia(createPinia());
    store = useChatStore();
    store.canais = [canal(), canal({ id: 2, tipo: 'direto', nao_lidas: 2 })];
  });

  it('mensagem de colega fora da conversa aberta soma não-lida e avisa', async () => {
    expect(await store.receber(msg(), 10)).toBe(true);
    expect(store.canais[0].nao_lidas).toBe(1);
    expect(store.totalNaoLidas).toBe(3);
  });

  it('a minha própria não soma nem avisa', async () => {
    expect(await store.receber(msg({ autor: { id: 10 } }), 10)).toBe(false);
    expect(store.totalNaoLidas).toBe(2);
  });

  it('na conversa aberta e à vista: entra na lista, marca lido e não avisa', async () => {
    store.abertoId = 1;
    store.mensagens[1] = [];
    expect(await store.receber(msg(), 10)).toBe(false);
    expect(store.mensagens[1]).toHaveLength(1);
    expect(ChatAPI.ler).toHaveBeenCalledWith(1);
    await store.receber(msg(), 10);
    expect(store.mensagens[1]).toHaveLength(1);
  });

  it('canal desconhecido (1:1 recém-aberto): recarrega a lista sem contar duas vezes', async () => {
    ChatAPI.get.mockResolvedValue({
      data: {
        payload: [canal({ id: 3, tipo: 'direto', nao_lidas: 1 })],
        admin: false,
      },
    });
    expect(await store.receber(msg({ canal_id: 3 }), 10)).toBe(true);
    expect(ChatAPI.get).toHaveBeenCalled();
    expect(store.totalNaoLidas).toBe(1);
  });

  it('administrador lendo canal alheio não é avisado', async () => {
    store.canais = [canal({ participante: false })];
    expect(await store.receber(msg(), 10)).toBe(false);
    expect(store.totalNaoLidas).toBe(0);
  });
});
