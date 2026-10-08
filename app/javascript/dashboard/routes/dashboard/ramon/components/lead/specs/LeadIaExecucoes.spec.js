import { mount, flushPromises } from '@vue/test-utils';
import CaptainToolRunsAPI from 'dashboard/api/captainToolRuns';
import RamonAgenteExecucoesAPI from 'dashboard/api/ramonAgenteExecucoes';
import LeadIaExecucoes from '../LeadIaExecucoes.vue';

vi.mock('dashboard/api/captainToolRuns', () => ({
  default: { list: vi.fn() },
}));
vi.mock('dashboard/api/ramonAgenteExecucoes', () => ({
  default: { list: vi.fn() },
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('vue-router', () => ({ useRouter: () => ({ push: vi.fn() }) }));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: vi.fn() }),
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ accountScopedRoute: n => n }),
}));

describe('LeadIaExecucoes (I-X8)', () => {
  it('junta ferramentas e agente do caso, mais nova primeiro', async () => {
    CaptainToolRunsAPI.list.mockResolvedValue({
      data: {
        items: [
          {
            id: 1,
            tool_name: 'mover_etapa',
            status: 'ok',
            created_at: '2026-10-07T10:00:00Z',
          },
        ],
        catalogo: [
          { id: 'mover_etapa', title: 'Mover de etapa', nivel: 'sugestao' },
        ],
      },
    });
    RamonAgenteExecucoesAPI.list.mockResolvedValue({
      data: {
        items: [
          {
            id: 7,
            pedido: 'anote a ligação',
            status: 'ok',
            created_at: '2026-10-07T11:00:00Z',
          },
        ],
      },
    });
    const wrapper = mount(LeadIaExecucoes, { props: { leadId: 12 } });
    await flushPromises();
    expect(CaptainToolRunsAPI.list).toHaveBeenCalledWith({ lead_id: 12 });
    expect(RamonAgenteExecucoesAPI.list).toHaveBeenCalledWith({ lead_id: 12 });
    expect(
      wrapper.findAll('[data-testid="caso-ia-linha"]').map(l => l.text())
    ).toEqual([
      expect.stringContaining('INTEL.CASO_IA.AGENTE'),
      expect.stringContaining('Mover de etapa'),
    ]);
  });

  it('nada no caso: aviso', async () => {
    CaptainToolRunsAPI.list.mockResolvedValue({
      data: { items: [], catalogo: [] },
    });
    RamonAgenteExecucoesAPI.list.mockResolvedValue({ data: { items: [] } });
    const wrapper = mount(LeadIaExecucoes, { props: { leadId: 12 } });
    await flushPromises();
    expect(wrapper.text()).toContain('INTEL.CASO_IA.VAZIO');
  });
});
