import { mount, flushPromises } from '@vue/test-utils';
import RamonCopilotAPI from 'dashboard/api/ramonCopilot';
import LeadCopilot from '../LeadCopilot.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/ramonCopilot', () => ({
  default: { generate: vi.fn() },
}));

const mountCopilot = conversationId =>
  mount(LeadCopilot, {
    props: { conversationId },
    global: { mocks: { $t: k => k } },
  });
const resumo = w => w.find('[data-testid="copilot-summary"]').text();

it('mantém o resumo da IA da conversa depois de desmontar e montar de novo', async () => {
  RamonCopilotAPI.generate.mockResolvedValue({
    data: { content: 'Lead quer saber do auxílio.' },
  });
  const first = mountCopilot(101);
  await first.find('[data-testid="copilot-summarize"]').trigger('click');
  await flushPromises();
  expect(resumo(first)).toBe('Lead quer saber do auxílio.');
  first.unmount();

  // troca de aba = remount: mostra o mesmo resumo sem gerar de novo
  const again = mountCopilot(101);
  expect(resumo(again)).toBe('Lead quer saber do auxílio.');
  expect(again.find('[data-testid="copilot-summary-time"]').exists()).toBe(
    true
  );
  expect(RamonCopilotAPI.generate).toHaveBeenCalledTimes(1);

  // outra conversa não herda o resumo
  expect(resumo(mountCopilot(202))).toBe('RAMON.COPILOT.EMPTY');
});
