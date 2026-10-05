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
const resumo = w => w.find('[data-testid="copilot-summary"]');

describe('LeadCopilot (linha Resumo da IA)', () => {
  beforeEach(() => RamonCopilotAPI.generate.mockReset());

  it('sem resumo: uma linha "gerar →" que gera ao clicar', async () => {
    RamonCopilotAPI.generate.mockResolvedValue({ data: { content: 'Curto.' } });
    const wrapper = mountCopilot(301);
    expect(resumo(wrapper).exists()).toBe(false);
    const linha = wrapper.find('[data-testid="copilot-summarize"]');
    expect(linha.text()).toContain('RAMON.COPILOT.GENERATE');
    await linha.trigger('click');
    await flushPromises();
    expect(RamonCopilotAPI.generate).toHaveBeenCalledWith(301, 'summary');
    expect(resumo(wrapper).text()).toBe('Curto.');
    // texto curto: sem "ver tudo"
    expect(wrapper.find('[data-testid="copilot-toggle"]').exists()).toBe(false);
  });

  it('resumo longo abre em 3 linhas; "ver tudo" expande e "ver menos" recolhe', async () => {
    RamonCopilotAPI.generate.mockResolvedValue({
      data: { content: 'x'.repeat(300) },
    });
    const wrapper = mountCopilot(302);
    await wrapper.find('[data-testid="copilot-summarize"]').trigger('click');
    await flushPromises();
    expect(resumo(wrapper).classes()).toContain('line-clamp-3');
    const toggle = wrapper.find('[data-testid="copilot-toggle"]');
    expect(toggle.text()).toBe('RAMON.COPILOT.SEE_ALL');
    await toggle.trigger('click');
    expect(resumo(wrapper).classes()).not.toContain('line-clamp-3');
    expect(toggle.text()).toBe('RAMON.COPILOT.SEE_LESS');
  });

  it('mantém o resumo da IA da conversa depois de desmontar e montar de novo', async () => {
    RamonCopilotAPI.generate.mockResolvedValue({
      data: { content: 'Lead quer saber do auxílio.' },
    });
    const first = mountCopilot(101);
    await first.find('[data-testid="copilot-summarize"]').trigger('click');
    await flushPromises();
    expect(resumo(first).text()).toBe('Lead quer saber do auxílio.');
    first.unmount();

    // troca de aba = remount: mostra o mesmo resumo sem gerar de novo
    const again = mountCopilot(101);
    expect(resumo(again).text()).toBe('Lead quer saber do auxílio.');
    expect(again.find('[data-testid="copilot-summary-time"]').exists()).toBe(
      true
    );
    // botão de atualizar (ícone) gera de novo
    await again.find('[data-testid="copilot-summarize"]').trigger('click');
    await flushPromises();
    expect(RamonCopilotAPI.generate).toHaveBeenCalledTimes(2);

    // outra conversa não herda o resumo
    expect(resumo(mountCopilot(202)).exists()).toBe(false);
  });
});
