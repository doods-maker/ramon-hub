import { nextTick, ref } from 'vue';
import LeadTasksAPI from 'dashboard/api/leadTasks';
import RamonConteudoAPI from 'dashboard/api/ramonConteudo';
import ConversationAPI from 'dashboard/api/inbox/conversation';
import { useNavContadores } from '../useNavContadores';

vi.mock('dashboard/api/leadTasks', () => ({
  default: { getAccountScope: vi.fn() },
}));
vi.mock('dashboard/api/ramonConteudo', () => ({ default: { get: vi.fn() } }));
vi.mock('dashboard/api/inbox/conversation', () => ({
  default: { meta: vi.fn() },
}));

const META = { data: { meta: { mine_count: 4, unassigned_count: 7 } } };

describe('useNavContadores', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    ConversationAPI.meta.mockResolvedValue(META);
    LeadTasksAPI.getAccountScope.mockResolvedValue({ data: { payload: [] } });
  });

  it('conta minhas conversas abertas, tarefas de hoje e peças em rascunho (gestor)', async () => {
    LeadTasksAPI.getAccountScope.mockResolvedValue({
      data: { payload: [{}, {}, {}] },
    });
    RamonConteudoAPI.get.mockResolvedValue({
      data: {
        payload: [
          { status: 'rascunho' },
          { status: 'publicado' },
          { status: 'rascunho' },
        ],
      },
    });
    const c = useNavContadores(ref('gestor'));
    await c.carregar();
    expect(ConversationAPI.meta).toHaveBeenCalledWith({ status: 'open' });
    expect(LeadTasksAPI.getAccountScope).toHaveBeenCalledWith('today');
    expect(c.agenda.value).toBe(3);
    expect(c.conteudo.value).toBe(2);
    expect(c.conversas.value).toBe(4);
  });

  it('recepção conta as conversas sem responsável', async () => {
    const c = useNavContadores(ref('recepcao'));
    await c.carregar();
    expect(c.conversas.value).toBe(7);
  });

  it('papel muda (times carregaram depois) → recarrega com a contagem certa', async () => {
    const papel = ref('equipe');
    const c = useNavContadores(papel);
    await c.carregar();
    expect(c.conversas.value).toBe(4);
    papel.value = 'recepcao';
    await nextTick();
    await vi.waitFor(() => expect(c.conversas.value).toBe(7));
  });

  it('não-gestor não busca conteúdo', async () => {
    const c = useNavContadores(ref('sdr'));
    await c.carregar();
    expect(RamonConteudoAPI.get).not.toHaveBeenCalled();
  });

  it('API fora do ar: contadores ficam zerados, sem lançar', async () => {
    ConversationAPI.meta.mockRejectedValue(new Error('500'));
    LeadTasksAPI.getAccountScope.mockRejectedValue(new Error('500'));
    RamonConteudoAPI.get.mockRejectedValue(new Error('500'));
    const c = useNavContadores(ref('gestor'));
    await expect(c.carregar()).resolves.toBeUndefined();
    expect(c.conversas.value).toBe(0);
    expect(c.agenda.value).toBe(0);
    expect(c.conteudo.value).toBe(0);
  });
});
