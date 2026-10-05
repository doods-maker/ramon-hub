import { mount, flushPromises } from '@vue/test-utils';
import RamonCopilotAPI from 'dashboard/api/ramonCopilot';
import { useAlert } from 'dashboard/composables';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import LeadSugerirResposta from '../LeadSugerirResposta.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('shared/helpers/mitt', () => ({ emitter: { emit: vi.fn() } }));
vi.mock('dashboard/api/ramonCopilot', () => ({
  default: { generate: vi.fn() },
}));

const mountSugerir = () =>
  mount(LeadSugerirResposta, {
    props: { conversationId: 101 },
    global: { mocks: { $t: k => k } },
  });

describe('LeadSugerirResposta', () => {
  beforeEach(() => vi.clearAllMocks());

  it('gera o rascunho e joga no editor (nada é enviado)', async () => {
    RamonCopilotAPI.generate.mockResolvedValue({
      data: { content: 'Oi João!' },
    });
    const wrapper = mountSugerir();
    await wrapper.find('[data-testid="copilot-suggest"]').trigger('click');
    await flushPromises();
    expect(RamonCopilotAPI.generate).toHaveBeenCalledWith(101, 'draft');
    expect(emitter.emit).toHaveBeenCalledWith(
      BUS_EVENTS.INSERT_INTO_NORMAL_EDITOR,
      'Oi João!'
    );
    expect(useAlert).toHaveBeenCalledWith('RAMON.COPILOT.DRAFT_READY');
  });

  it('guard de duplo-clique enquanto gera', async () => {
    RamonCopilotAPI.generate.mockReturnValue(new Promise(() => {}));
    const wrapper = mountSugerir();
    const botao = wrapper.find('[data-testid="copilot-suggest"]');
    await botao.trigger('click');
    await botao.trigger('click');
    expect(RamonCopilotAPI.generate).toHaveBeenCalledTimes(1);
  });
});
