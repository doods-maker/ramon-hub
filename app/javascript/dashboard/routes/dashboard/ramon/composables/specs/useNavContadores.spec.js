import { ref } from 'vue';
import LeadTasksAPI from 'dashboard/api/leadTasks';
import RamonConteudoAPI from 'dashboard/api/ramonConteudo';
import { useNavContadores } from '../useNavContadores';

vi.mock('dashboard/api/leadTasks', () => ({
  default: { getAccountScope: vi.fn() },
}));
vi.mock('dashboard/api/ramonConteudo', () => ({ default: { get: vi.fn() } }));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ref(4),
}));

describe('useNavContadores', () => {
  beforeEach(() => vi.clearAllMocks());

  it('conta tarefas de hoje e peças em rascunho (gestor)', async () => {
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
    expect(LeadTasksAPI.getAccountScope).toHaveBeenCalledWith('today');
    expect(c.agenda.value).toBe(3);
    expect(c.conteudo.value).toBe(2);
    expect(c.conversas.value).toBe(4);
  });

  it('não-gestor não busca conteúdo', async () => {
    LeadTasksAPI.getAccountScope.mockResolvedValue({ data: { payload: [] } });
    const c = useNavContadores(ref('sdr'));
    await c.carregar();
    expect(RamonConteudoAPI.get).not.toHaveBeenCalled();
  });

  it('API fora do ar: contadores ficam zerados, sem lançar', async () => {
    LeadTasksAPI.getAccountScope.mockRejectedValue(new Error('500'));
    RamonConteudoAPI.get.mockRejectedValue(new Error('500'));
    const c = useNavContadores(ref('gestor'));
    await expect(c.carregar()).resolves.toBeUndefined();
    expect(c.agenda.value).toBe(0);
    expect(c.conteudo.value).toBe(0);
  });
});
