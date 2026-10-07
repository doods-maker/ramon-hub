import { mount } from '@vue/test-utils';
import CopilotEmptyState from '../CopilotEmptyState.vue';

vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: 2 } }),
}));

const montar = props =>
  mount(CopilotEmptyState, {
    props: { hasAssistants: true, ...props },
    global: { stubs: { RouterLink: true } },
  });

const rotulos = wrapper => wrapper.findAll('button').map(b => b.text());

describe('atalhos do painel do Copiloto', () => {
  it('equipe com conversa aberta: os 3 atalhos do caso; o clique manda o pedido', async () => {
    const wrapper = montar({ equipe: true, naConversa: true });

    expect(rotulos(wrapper)).toEqual([
      "This client's case status",
      'Missing documents',
      'Prepare the meeting',
    ]);
    expect(wrapper.text()).toContain('Ask about the open case');
    expect(wrapper.text()).toContain('Nothing goes to the client.');

    await wrapper.findAll('button')[0].trigger('click');
    expect(wrapper.emitted('useSuggestion')[0][0]).toContain('AdvBox');
  });

  it('equipe fora de conversa: agenda, funil e prazos, sem falar de caso aberto', () => {
    const wrapper = montar({ equipe: true, naConversa: false });

    expect(rotulos(wrapper)).toEqual([
      "Today's agenda",
      'Funnel today',
      "This week's AdvBox deadlines",
    ]);
    expect(wrapper.text()).toContain('Ask about the schedule, the funnel');
    expect(wrapper.text()).not.toContain('open case');
  });

  it('assistente de leads segue com os comandos de antes', () => {
    expect(rotulos(montar({ equipe: false, naConversa: true }))).toEqual([
      'Summarize this conversation',
      'Suggest an answer',
      'Rate this conversation',
    ]);
    expect(rotulos(montar({ equipe: false, naConversa: false }))).toEqual([
      'High priority conversations',
      'List contacts',
    ]);
  });
});
