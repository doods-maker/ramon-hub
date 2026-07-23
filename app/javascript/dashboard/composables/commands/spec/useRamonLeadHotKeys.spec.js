import { useRamonLeadHotKeys } from '../useRamonLeadHotKeys';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { brlCompact } from 'dashboard/routes/dashboard/ramon/helpers/currency';

vi.mock('dashboard/composables/store');
vi.mock('vue-i18n');
vi.mock('vue-router');
vi.mock('dashboard/composables');

const STAGES = [
  { id: 1, name: 'Novo', position: 1 },
  { id: 2, name: 'Qualificado', position: 2 },
  { id: 3, name: 'Perdemos', position: 3, is_lost: true },
];

const LEADS = [
  {
    id: 10,
    name: 'Ana Souza',
    value: 5000,
    stage_name: 'Novo',
    benefit_type_name: 'B31',
    contact_phone: '+5548999990000',
  },
  {
    id: 11,
    name: 'Bia Lima',
    value: 50000,
    stage_name: 'Qualificado',
    benefit_type_name: 'B91',
  },
  {
    id: 12,
    name: 'Caio Prado',
    value: 100,
    stage_name: 'Novo',
    // tarefa vencida → risco → topo da lista mesmo com valor baixo
    next_task_due_at: '2020-01-01T09:00:00.000Z',
  },
];

describe('useRamonLeadHotKeys', () => {
  let store;
  let router;

  const setup = ({ leads = LEADS, stages = STAGES } = {}) => {
    store = {
      getters: {
        'leads/getLeads': leads,
        'leads/getUIFlags': { isFetching: false },
        'leadConfig/getStages': stages,
        getCurrentAccountId: 1,
      },
      dispatch: vi.fn().mockResolvedValue({}),
    };
    useStore.mockReturnValue(store);
    useMapGetter.mockImplementation(key => ({ value: store.getters[key] }));
    useI18n.mockReturnValue({ t: vi.fn(key => key) });
    router = { push: vi.fn() };
    useRouter.mockReturnValue(router);
    useAlert.mockReturnValue(undefined);
    return useRamonLeadHotKeys();
  };

  const rootItems = actions => actions.filter(a => !a.parent);

  beforeEach(() => {
    vi.clearAllMocks();
    localStorage.clear();
  });

  it('returns no actions when no leads are loaded', () => {
    const { ramonLeadHotKeys } = setup({ leads: [] });
    expect(ramonLeadHotKeys.value).toEqual([]);
  });

  it('builds a Leads section item per lead with compact title and keywords', () => {
    const { ramonLeadHotKeys } = setup();
    const ana = ramonLeadHotKeys.value.find(a => a.id === 'ramon_lead_10');
    expect(ana.section).toBe('RAMON.CMDK.SECTION');
    expect(ana.title).toBe(`Ana Souza — Novo · B31 · ${brlCompact(5000)}`);
    expect(ana.keywords).toBe('Ana Souza +5548999990000');
  });

  it('orders at-risk leads first, then by value descending', () => {
    const { ramonLeadHotKeys } = setup();
    const ids = rootItems(ramonLeadHotKeys.value).map(a => a.id);
    expect(ids).toEqual(['ramon_lead_12', 'ramon_lead_11', 'ramon_lead_10']);
  });

  it('caps the section at 15 leads', () => {
    const many = Array.from({ length: 20 }, (_, i) => ({
      id: i + 1,
      name: `Lead ${i + 1}`,
      value: i,
    }));
    const { ramonLeadHotKeys } = setup({ leads: many });
    expect(rootItems(ramonLeadHotKeys.value)).toHaveLength(15);
  });

  it('opens the funnel drawer on lead selection and keeps the palette open', () => {
    const { ramonLeadHotKeys } = setup();
    const ana = ramonLeadHotKeys.value.find(a => a.id === 'ramon_lead_10');
    const result = ana.handler();
    expect(router.push).toHaveBeenCalledWith({
      name: 'ramon_funil',
      params: { accountId: 1 },
    });
    expect(store.dispatch).toHaveBeenCalledWith('leads/select', 10);
    expect(result).toEqual({ keepOpen: true });
  });

  it('exposes move/task/dossie/simulate as children of the lead', () => {
    const { ramonLeadHotKeys } = setup();
    const ana = ramonLeadHotKeys.value.find(a => a.id === 'ramon_lead_10');
    expect(ana.children).toEqual([
      'ramon_lead_10_move',
      'ramon_lead_10_task',
      'ramon_lead_10_dossie',
      'ramon_lead_10_sim',
    ]);
    ana.children.forEach(childId => {
      const child = ramonLeadHotKeys.value.find(a => a.id === childId);
      expect(child.parent).toBe('ramon_lead_10');
    });
  });

  it('lists stages ordered and without lost stages under "move to stage"', () => {
    const { ramonLeadHotKeys } = setup();
    const move = ramonLeadHotKeys.value.find(
      a => a.id === 'ramon_lead_10_move'
    );
    expect(move.children).toEqual([
      'ramon_lead_10_move_1',
      'ramon_lead_10_move_2',
    ]);
    expect(
      ramonLeadHotKeys.value.find(a => a.id === 'ramon_lead_10_move_3')
    ).toBeUndefined();
  });

  it('dispatches leads/move when a stage is picked', async () => {
    const { ramonLeadHotKeys } = setup();
    const stage = ramonLeadHotKeys.value.find(
      a => a.id === 'ramon_lead_10_move_2'
    );
    await stage.handler();
    expect(store.dispatch).toHaveBeenCalledWith('leads/move', {
      id: 10,
      leadStageId: 2,
    });
    expect(useAlert).toHaveBeenCalledWith('RAMON.KANBAN.MOVE_DONE');
  });

  it('creates a follow-up task for tomorrow 9h with the default title', async () => {
    const { ramonLeadHotKeys } = setup();
    const task = ramonLeadHotKeys.value.find(
      a => a.id === 'ramon_lead_10_task'
    );
    await task.handler();
    const [action, payload] = store.dispatch.mock.calls.find(
      call => call[0] === 'leadTasks/create'
    );
    expect(action).toBe('leadTasks/create');
    expect(payload).toMatchObject({
      leadId: 10,
      kind: 'follow_up',
      title: 'RAMON.KANBAN.BELL.DEFAULT_TITLE',
    });
    const due = new Date(payload.dueAt);
    expect(due.getTime()).toBeGreaterThan(Date.now());
    expect(due.getHours()).toBe(9);
    expect(useAlert).toHaveBeenCalledWith('RAMON.KANBAN.CARD.TASK_SCHEDULED');
  });

  it('alerts on task creation failure', async () => {
    const { ramonLeadHotKeys } = setup();
    store.dispatch.mockRejectedValueOnce(new Error('boom'));
    const task = ramonLeadHotKeys.value.find(
      a => a.id === 'ramon_lead_10_task'
    );
    await task.handler();
    expect(useAlert).toHaveBeenCalledWith('RAMON.TASKS.CREATE_ERROR');
  });

  it('routes to the dossie page', () => {
    const { ramonLeadHotKeys } = setup();
    const dossie = ramonLeadHotKeys.value.find(
      a => a.id === 'ramon_lead_10_dossie'
    );
    dossie.handler();
    expect(router.push).toHaveBeenCalledWith({
      name: 'ramon_lead_dossie',
      params: { accountId: 1, leadId: 10 },
    });
  });

  it('pre-selects the simulator tab and opens the drawer', () => {
    const { ramonLeadHotKeys } = setup();
    const sim = ramonLeadHotKeys.value.find(a => a.id === 'ramon_lead_10_sim');
    sim.handler();
    expect(localStorage.getItem('ramon_lead_panel_tab')).toBe('simulador');
    expect(store.dispatch).toHaveBeenCalledWith('leads/select', 10);
    expect(router.push).toHaveBeenCalledWith({
      name: 'ramon_funil',
      params: { accountId: 1 },
    });
  });

  describe('ensureLeadsLoaded', () => {
    it('fetches leads and stages when both are empty', () => {
      const { ensureLeadsLoaded } = setup({ leads: [], stages: [] });
      ensureLeadsLoaded();
      expect(store.dispatch).toHaveBeenCalledWith('leads/get');
      expect(store.dispatch).toHaveBeenCalledWith('leadConfig/get');
    });

    it('does nothing when leads are already loaded', () => {
      const { ensureLeadsLoaded } = setup();
      ensureLeadsLoaded();
      expect(store.dispatch).not.toHaveBeenCalled();
    });

    it('does not refetch while a fetch is in flight', () => {
      const { ensureLeadsLoaded } = setup({ leads: [] });
      store.getters['leads/getUIFlags'] = { isFetching: true };
      ensureLeadsLoaded();
      expect(store.dispatch).not.toHaveBeenCalledWith('leads/get');
    });
  });
});
