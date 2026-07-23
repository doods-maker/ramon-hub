import { mount, flushPromises } from '@vue/test-utils';
import { ref } from 'vue';
import NightCopilot from '../NightCopilot.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));

const dispatchSpy = vi.fn();
const suggestionsRef = ref([]);
const metaRef = ref({ reviewedCount: 32 });
const flagsRef = ref({ isFetching: false, isApplying: false, hasError: false });
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: dispatchSpy }),
  useStoreGetters: () => ({
    'copilotSuggestions/getSuggestions': suggestionsRef,
    'copilotSuggestions/getMeta': metaRef,
    'copilotSuggestions/getUIFlags': flagsRef,
  }),
}));

const alertSpy = vi.fn();
vi.mock('dashboard/composables', () => ({
  useAlert: (...a) => alertSpy(...a),
}));

const suggestions = () => [
  {
    id: 1,
    lead_id: 10,
    lead_name: 'Rosana Beltrão',
    kind: 'draft',
    run_at: '2026-07-23T08:00:00Z',
    payload: {
      texto: 'Oi Rosana, ficou alguma dúvida sobre os documentos do BPC?',
      days_stalled: 3,
    },
  },
  {
    id: 2,
    lead_id: 11,
    lead_name: 'Ivone Castro Dias',
    kind: 'move_stage',
    run_at: '2026-07-23T08:00:00Z',
    payload: {
      etapa_sugerida: 'Qualificação',
      justificativa: 'Triagem concluída: preenche requisitos.',
    },
  },
  {
    id: 3,
    lead_id: 12,
    lead_name: 'Sebastião Ramos',
    kind: 'alert',
    run_at: '2026-07-23T08:00:00Z',
    payload: { justificativa: 'Mencionou "outro advogado me ligou".' },
  },
];

const mountBlock = async () => {
  const wrapper = mount(NightCopilot, { global: { mocks: { $t: k => k } } });
  await flushPromises();
  return wrapper;
};

describe('NightCopilot.vue', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    suggestionsRef.value = suggestions();
    flagsRef.value = { isFetching: false, isApplying: false, hasError: false };
  });

  it('fetches on mount and renders one card per suggestion with its tag', async () => {
    const wrapper = await mountBlock();
    expect(dispatchSpy).toHaveBeenCalledWith('copilotSuggestions/fetch');
    const cards = wrapper.findAll('[data-testid="night-copilot-card"]');
    expect(cards).toHaveLength(3);
    expect(cards[0].text()).toContain('RAMON.NIGHT_COPILOT.TAG_DRAFT');
    expect(cards[0].text()).toContain('Rosana Beltrão');
    expect(cards[1].text()).toContain('RAMON.NIGHT_COPILOT.TAG_MOVE_STAGE');
    expect(cards[2].text()).toContain('RAMON.NIGHT_COPILOT.TAG_ALERT');
  });

  it('shows the draft text and the move_stage justification', async () => {
    const wrapper = await mountBlock();
    const cards = wrapper.findAll('[data-testid="night-copilot-card"]');
    expect(cards[0].text()).toContain('documentos do BPC');
    expect(cards[1].text()).toContain('Triagem concluída');
    expect(cards[1].text()).toContain('RAMON.NIGHT_COPILOT.MOVE_TO');
  });

  it('apply calls the store with the suggestion id', async () => {
    const wrapper = await mountBlock();
    await wrapper.find('[data-testid="night-copilot-apply"]').trigger('click');
    expect(dispatchSpy).toHaveBeenCalledWith('copilotSuggestions/apply', 1);
  });

  it('dismiss calls the store with the suggestion id', async () => {
    const wrapper = await mountBlock();
    await wrapper
      .find('[data-testid="night-copilot-dismiss"]')
      .trigger('click');
    expect(dispatchSpy).toHaveBeenCalledWith('copilotSuggestions/dismiss', 1);
  });

  it('approve all counts only drafts and alerts and dispatches applyAll', async () => {
    const wrapper = await mountBlock();
    const button = wrapper.find('[data-testid="night-copilot-apply-all"]');
    expect(button.text()).toContain('RAMON.NIGHT_COPILOT.APPROVE_ALL');
    await button.trigger('click');
    expect(dispatchSpy).toHaveBeenCalledWith('copilotSuggestions/applyAll');
  });

  it('escalate on an alert creates a follow_up task for today and applies', async () => {
    const wrapper = await mountBlock();
    await wrapper
      .find('[data-testid="night-copilot-escalate"]')
      .trigger('click');
    await flushPromises();
    expect(dispatchSpy).toHaveBeenCalledWith(
      'leadTasks/create',
      expect.objectContaining({ leadId: 12, kind: 'follow_up' })
    );
    expect(dispatchSpy).toHaveBeenCalledWith('copilotSuggestions/apply', 3);
  });

  it('disappears entirely when there are no pending suggestions', async () => {
    suggestionsRef.value = [];
    const wrapper = await mountBlock();
    expect(wrapper.find('[data-testid="night-copilot"]').exists()).toBe(false);
  });

  it('shows the error state with retry', async () => {
    flagsRef.value = { isFetching: false, isApplying: false, hasError: true };
    const wrapper = await mountBlock();
    expect(wrapper.find('[data-testid="night-copilot-error"]').exists()).toBe(
      true
    );
    dispatchSpy.mockClear();
    await wrapper.find('[data-testid="night-copilot-retry"]').trigger('click');
    expect(dispatchSpy).toHaveBeenCalledWith('copilotSuggestions/fetch');
  });
});
