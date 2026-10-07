import { mount, flushPromises } from '@vue/test-utils';
import CaptainToolRunsAPI from 'dashboard/api/captainToolRuns';
import Execucoes from '../Execucoes.vue';

const push = vi.fn();
const dispatch = vi.fn();
let query = {};
vi.mock('vue-router', () => ({
  useRouter: () => ({ push }),
  useRoute: () => ({ query }),
}));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch }),
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    accountScopedRoute: (name, params, q) => ({ name, params, query: q }),
  }),
}));
vi.mock('dashboard/api/captainToolRuns', () => ({
  default: { list: vi.fn() },
}));
vi.mock('../ExecucoesAgente.vue', () => ({
  default: { template: '<div data-testid="aba-agente-conteudo" />' },
}));

const RUN = {
  id: 1,
  tool_name: 'mover_etapa',
  status: 'ok',
  duration_ms: 420,
  params: { etapa: 'Reunião' },
  resultado: 'movido',
  lead_id: 123,
  lead_nome: 'Maria Souza',
  conversation_id: 9,
  conversa_display_id: 482,
  assistant_id: 1,
  assistente_nome: 'Atendimento (rascunho)',
  created_at: '2026-10-07T12:00:00Z',
};
const montar = async () => {
  CaptainToolRunsAPI.list.mockResolvedValue({
    data: {
      resumo: {
        total_24h: 2,
        erros_24h: 0,
        por_tool: { mover_etapa: 2 },
        tools: ['mover_etapa'],
      },
      items: [
        RUN,
        {
          ...RUN,
          id: 2,
          lead_id: null,
          lead_nome: null,
          conversa_display_id: null,
          assistente_nome: null,
        },
      ],
      catalogo: [
        { id: 'mover_etapa', title: 'Mover de etapa', nivel: 'sugestao' },
      ],
    },
  });
  const wrapper = mount(Execucoes);
  await flushPromises();
  return wrapper;
};

describe('Execucoes.vue', () => {
  beforeEach(() => {
    query = {};
  });

  it('caso clicável abre o Funil com o caso selecionado', async () => {
    const wrapper = await montar();
    const caso = wrapper.find('[data-testid="execucoes-caso"]');
    expect(caso.text()).toContain('Maria Souza');
    await caso.trigger('click');
    expect(push).toHaveBeenCalledWith(
      expect.objectContaining({ name: 'ramon_funil' })
    );
    expect(dispatch).toHaveBeenCalledWith('leads/select', 123);
  });

  it('conversa clicável abre a conversa pelo nº; assistente aparece', async () => {
    const wrapper = await montar();
    await wrapper.find('[data-testid="execucoes-conversa"]').trigger('click');
    expect(push).toHaveBeenCalledWith(
      expect.objectContaining({
        name: 'inbox_conversation',
        params: { conversation_id: 482 },
      })
    );
    expect(wrapper.find('[data-testid="execucoes-assistente"]').text()).toBe(
      'Atendimento (rascunho)'
    );
  });

  it('linha sem caso nem conversa não mostra os links', async () => {
    const wrapper = await montar();
    const linha = wrapper.findAll('[data-testid="execucoes-linha"]')[1];
    expect(linha.find('[data-testid="execucoes-caso"]').exists()).toBe(false);
    expect(linha.find('[data-testid="execucoes-conversa"]').exists()).toBe(
      false
    );
  });

  it('?aba=agente abre a aba do agente Claude; a aba de ferramentas volta', async () => {
    query = { aba: 'agente' };
    const wrapper = await montar();
    expect(wrapper.find('[data-testid="aba-agente-conteudo"]').exists()).toBe(
      true
    );
    expect(wrapper.find('[data-testid="execucoes-linha"]').exists()).toBe(
      false
    );
    await wrapper
      .find('[data-testid="execucoes-aba-ferramentas"]')
      .trigger('click');
    expect(wrapper.findAll('[data-testid="execucoes-linha"]')).toHaveLength(2);
  });
});
