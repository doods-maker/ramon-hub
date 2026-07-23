import { mount, flushPromises } from '@vue/test-utils';
import { ref } from 'vue';
import TvBoard from '../TvBoard.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));

const dispatchSpy = vi.fn();
const subscribers = [];
const unsubscribeSpy = vi.fn();
const dataRef = ref(null);
const flagsRef = ref({ isFetching: false, hasError: false });
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({
    dispatch: dispatchSpy,
    subscribe: handler => {
      subscribers.push(handler);
      return unsubscribeSpy;
    },
  }),
  useStoreGetters: () => ({
    'ramonDashboard/getData': dataRef,
    'ramonDashboard/getUIFlags': flagsRef,
  }),
}));

const payload = () => ({
  funnel: [
    { stage_id: 1, name: 'Novo', count: 12, is_won: false, is_lost: false },
    { stage_id: 2, name: 'Contato', count: 8, is_won: false, is_lost: false },
    { stage_id: 5, name: 'Ganhamos', count: 3, is_won: true, is_lost: false },
  ],
  tv: {
    month: {
      won_value: 312000,
      won_count: 8,
      goal: 400000,
      business_days_left: 6,
      today: { won_count: 2, new_count: 9, avg_first_response_minutes: 18.4 },
    },
    by_thesis: [
      {
        thesis_id: 1,
        name: 'Restabelecimento B31',
        leads_count: 14,
        new_week: 5,
        won_month: 4,
        won_value_month: 146000,
        conversion_pct: 29,
        prescribing_count: 2,
        prescribing_monthly: 2824,
        stalled_count: 1,
      },
      {
        thesis_id: 2,
        name: 'Auxílio-acidente (B94)',
        leads_count: 6,
        new_week: 1,
        won_month: 3,
        won_value_month: 84000,
        conversion_pct: 50,
        prescribing_count: 0,
        prescribing_monthly: 0,
        stalled_count: 0,
      },
      {
        thesis_id: 3,
        name: 'Aposentadoria invalidez (B32)',
        leads_count: 5,
        new_week: 0,
        won_month: 1,
        won_value_month: 24000,
        conversion_pct: 20,
        prescribing_count: 0,
        prescribing_monthly: 0,
        stalled_count: 2,
      },
      {
        thesis_id: null,
        name: 'Sem tese',
        leads_count: 3,
        new_week: 0,
        won_month: 0,
        won_value_month: 0,
        conversion_pct: null,
        prescribing_count: 0,
        prescribing_monthly: 0,
        stalled_count: 0,
      },
    ],
    race: [
      { name: 'Camila', won_count: 4, won_value: 168000 },
      { name: 'Eduardo', won_count: 3, won_value: 144000 },
    ],
    prescribing_total_monthly: 11240,
    next_meeting: {
      at: '2026-07-23T18:00:00Z',
      lead_name: 'Antônio Carlos Nunes',
      user_name: 'Camila',
    },
    last_won: {
      lead_name: 'Zilda Pereira Lima',
      closer_name: 'Camila',
      value: 39800,
      benefit: 'Aposentadoria por invalidez',
      at: '2026-07-23T17:20:00Z',
    },
  },
});

const mountPage = async (data = payload()) => {
  dataRef.value = data;
  const wrapper = mount(TvBoard, { global: { mocks: { $t: k => k } } });
  await flushPromises();
  return wrapper;
};

describe('TvBoard.vue', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    subscribers.length = 0;
    dataRef.value = null;
    window.innerWidth = 1280;
    window.innerHeight = 720;
  });

  it('fetches on mount and applies the viewport scale to the 1280×720 stage', async () => {
    window.innerWidth = 2560;
    window.innerHeight = 1440;
    const wrapper = await mountPage();
    expect(dispatchSpy).toHaveBeenCalledWith('ramonDashboard/fetch');
    const stage = wrapper.find('[data-testid="tv-stage"]');
    expect(stage.attributes('style')).toContain('scale(2)');

    // letterbox: a menor razão vence (aqui a altura)
    window.innerWidth = 2560;
    window.innerHeight = 720;
    window.dispatchEvent(new Event('resize'));
    await flushPromises();
    expect(stage.attributes('style')).toContain('scale(1)');
  });

  it('renders hero, goal, today, theses, race, prescribing and next meeting', async () => {
    const wrapper = await mountPage();
    expect(wrapper.find('[data-testid="tv-hero-value"]').text()).toContain(
      'R$'
    );
    expect(wrapper.find('[data-testid="tv-goal"]').text()).toContain('78%');
    expect(wrapper.find('[data-testid="tv-today"]').text()).toContain('18min');
    expect(wrapper.findAll('[data-testid="tv-thesis-row"]')).toHaveLength(4);
    expect(wrapper.find('[data-testid="tv-funnel-line"]').text()).toContain(
      'RAMON.TV.FUNNEL_LINE'
    );
    const race = wrapper.findAll('[data-testid="tv-race-row"]');
    expect(race).toHaveLength(2);
    expect(race[0].text()).toContain('Camila');
    expect(wrapper.find('[data-testid="tv-prescribing"]').text()).toContain(
      'RAMON.TV.PRESCRIBING_MONTH'
    );
    expect(wrapper.find('[data-testid="tv-next-meeting"]').text()).toContain(
      'Antônio Carlos Nunes'
    );
    expect(wrapper.find('[data-testid="tv-ticker"]').text()).toContain(
      'RAMON.TV.TICKER'
    );
  });

  it('hides the goal block when there is no monthly goal', async () => {
    const data = payload();
    data.tv.month.goal = 0;
    const wrapper = await mountPage(data);
    expect(wrapper.find('[data-testid="tv-goal"]').exists()).toBe(false);
  });

  it('picks the thesis subnote by priority: prescribing > best > stalled > steady', async () => {
    const wrapper = await mountPage();
    const notes = wrapper
      .findAll('[data-testid="tv-thesis-note"]')
      .map(n => n.text());
    expect(notes[0]).toBe('RAMON.TV.NOTE_PRESCRIBING'); // prescreve mesmo com parado
    expect(notes[1]).toBe('RAMON.TV.NOTE_BEST'); // maior conversão com ganho
    expect(notes[2]).toBe('RAMON.TV.NOTE_STALLED');
    expect(notes[3]).toBe('RAMON.TV.NOTE_STABLE');
  });

  it('hides the ticker when there is no win today', async () => {
    const data = payload();
    data.tv.last_won = null;
    const wrapper = await mountPage(data);
    expect(wrapper.find('[data-testid="tv-ticker"]').exists()).toBe(false);
  });

  it('re-fetches with a 5s debounce when a lead broadcast lands in the store', async () => {
    vi.useFakeTimers();
    const wrapper = await mountPage();
    dispatchSpy.mockClear();

    subscribers.forEach(fn => fn({ type: 'leads/MERGE_LEAD' }));
    subscribers.forEach(fn => fn({ type: 'leads/MERGE_LEAD' }));
    vi.advanceTimersByTime(4999);
    expect(dispatchSpy).not.toHaveBeenCalled();
    vi.advanceTimersByTime(1);
    expect(dispatchSpy).toHaveBeenCalledTimes(1);
    expect(dispatchSpy).toHaveBeenCalledWith('ramonDashboard/fetch');

    // mutação de outro módulo (ou type sem namespace) não agenda nada
    dispatchSpy.mockClear();
    subscribers.forEach(fn => fn({ type: 'leads/SET_LEAD_SELECTION' }));
    subscribers.forEach(fn => fn({ type: 'MERGE_LEAD' }));
    vi.advanceTimersByTime(5000);
    expect(dispatchSpy).not.toHaveBeenCalled();

    wrapper.unmount();
    expect(unsubscribeSpy).toHaveBeenCalled();
    vi.useRealTimers();
  });
});
