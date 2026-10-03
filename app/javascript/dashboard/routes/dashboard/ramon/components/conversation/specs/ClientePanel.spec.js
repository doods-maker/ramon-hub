import { mount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import ClientePanel from '../ClientePanel.vue';
import RamonClienteAPI from 'dashboard/api/ramonCliente';
import { useAlert } from 'dashboard/composables';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/ramonCliente', () => ({ default: { get: vi.fn() } }));

const CLIENTE = {
  cliente: true,
  nome: 'Maria',
  desde: '2023-03',
  advogada: { nome: 'Dra. Tamires', user_id: 7 },
  telefone: '+5548991203381',
  processos: [
    {
      numero: '5003412-18.2024.4.04.7207',
      tipo: 'Auxílio-doença',
      fase: 'Perícia',
      ultimo_andamento: { data: '2026-09-30', titulo: 'Perícia designada' },
    },
  ],
  compromisso: {
    tipo: 'pericia',
    data: '2026-10-07',
    hora: '09:00',
    notas: 'INSS Tubarão',
  },
  sugestao_user_id: 7,
};
const ADVOGADAS = [
  { id: 5, name: 'Dra. Brenda' },
  { id: 7, name: 'Dra. Tamires' },
];

// assignAgent/assignTeam de verdade só mudam o estado no sucesso (engolem
// o erro); aqui `falha` simula a requisição que não pegou.
const montar = ({
  dados = CLIENTE,
  chat = {},
  userId = 1,
  falha = false,
  erroCliente = false,
} = {}) => {
  if (erroCliente) RamonClienteAPI.get.mockRejectedValue(new Error('fora'));
  else RamonClienteAPI.get.mockResolvedValue({ data: dados });
  const chamadas = [];
  const assignAgent = vi.fn(({ state }, { agentId }) => {
    chamadas.push('agente');
    if (!falha) state.meta.assignee = agentId ? { id: agentId } : null;
  });
  const assignTeam = vi.fn(({ state }, { teamId }) => {
    chamadas.push('time');
    if (!falha) state.meta.team = teamId ? { id: teamId } : null;
  });
  const store = createStore({
    state: () => ({ id: 42, meta: {}, ...chat }),
    getters: {
      getSelectedChat: state => state,
      getCurrentUserID: () => userId,
    },
    actions: { assignAgent, assignTeam },
    modules: {
      teams: {
        namespaced: true,
        getters: {
          getTeams: () => [
            { id: 1, name: 'Advogados' },
            { id: 2, name: 'Controladoria' },
          ],
        },
      },
      teamMembers: {
        namespaced: true,
        getters: {
          getTeamMembers: () => id =>
            id === 1 ? ADVOGADAS : [{ id: 9, name: 'Thaís' }],
        },
        actions: { get: vi.fn() },
      },
    },
  });
  const wrapper = mount(ClientePanel, {
    props: { conversationId: 42 },
    global: { plugins: [store] },
  });
  return { wrapper, assignAgent, assignTeam, chamadas };
};

describe('ClientePanel', () => {
  beforeEach(() => useAlert.mockClear());

  it('Atribuir a… lista a advogada do processo primeiro, marcada', async () => {
    const { wrapper, assignAgent } = montar();
    await flushPromises();
    await wrapper.find('[data-testid="cliente-atribuir"]').trigger('click');
    const pessoas = wrapper.findAll('[data-testid="cliente-pessoa"]');
    expect(pessoas[0].text()).toContain('Dra. Tamires');
    expect(pessoas[0].text()).toContain('RAMON.CLIENTE_PANEL.DO_PROCESSO');
    expect(pessoas[1].text()).not.toContain('DO_PROCESSO');
    await pessoas[1].trigger('click');
    expect(assignAgent).toHaveBeenCalledWith(expect.anything(), {
      conversationId: 42,
      agentId: 5,
    });
  });

  it('só avisa sucesso se a conversa mudou de fato', async () => {
    const { wrapper } = montar({ falha: true });
    await flushPromises();
    await wrapper.find('[data-testid="cliente-atribuir"]').trigger('click');
    await wrapper.findAll('[data-testid="cliente-pessoa"]')[0].trigger('click');
    await flushPromises();
    expect(useAlert).toHaveBeenCalledWith('RAMON.CLIENTE_PANEL.ERRO_ATRIBUIR');
    expect(useAlert).not.toHaveBeenCalledWith('CONVERSATION.CHANGE_AGENT');
  });

  it('erro ao buscar o cliente: avisa e ainda deixa encaminhar', async () => {
    const { wrapper } = montar({ erroCliente: true });
    await flushPromises();
    expect(wrapper.text()).toContain('RAMON.CLIENTE_PANEL.ERRO');
    expect(
      wrapper.find('[data-testid="lead-panel-encaminhar-comercial"]').exists()
    ).toBe(true);
  });

  it('Controladoria atribui o time', async () => {
    const { wrapper, assignTeam } = montar();
    await flushPromises();
    await wrapper.find('[data-testid="cliente-atribuir"]').trigger('click');
    const controladoria = wrapper.find('[data-testid="cliente-controladoria"]');
    expect(controladoria.text()).toContain(
      'RAMON.CLIENTE_PANEL.CONTROLADORIA_COM'
    );
    await controladoria.trigger('click');
    expect(assignTeam).toHaveBeenCalledWith(expect.anything(), {
      conversationId: 42,
      teamId: 2,
    });
  });

  it('mostra cliente, telefone, compromisso e processos', async () => {
    const { wrapper } = montar();
    await flushPromises();
    expect(wrapper.text()).toContain('RAMON.CLIENTE_PANEL.CLIENTE_DESDE');
    expect(wrapper.text()).toContain('(48) 9 9120-3381');
    expect(wrapper.find('[data-testid="cliente-compromisso"]').text()).toBe(
      'RAMON.CLIENTE_PANEL.COMPROMISSO.pericia · 07/10, 09:00INSS Tubarão'
    );
    expect(wrapper.text()).toContain('5003412-18.2024.4.04.7207');
    expect(wrapper.text()).toContain('30/09 · Perícia designada');
  });

  it('advogada atribuída vê a faixa (sem o Atribuir a…) e devolve', async () => {
    const { wrapper, assignAgent, assignTeam, chamadas } = montar({
      userId: 7,
      chat: {
        meta: { assignee: { id: 7 } },
        additional_attributes: {
          ramon_atribuicao: {
            por_id: 3,
            por_nome: 'Gabriela',
            em: '2026-10-03T16:52:00Z',
          },
        },
      },
    });
    await flushPromises();
    expect(wrapper.find('[data-testid="cliente-atribuir"]').exists()).toBe(
      false
    );
    expect(
      wrapper.find('[data-testid="cliente-faixa-atribuida"]').exists()
    ).toBe(true);
    await wrapper.find('[data-testid="cliente-devolver"]').trigger('click');
    await flushPromises();
    expect(assignAgent).toHaveBeenCalledWith(expect.anything(), {
      conversationId: 42,
      agentId: null,
    });
    expect(assignTeam).toHaveBeenCalledWith(expect.anything(), {
      conversationId: 42,
      teamId: 0,
    });
    // time primeiro: ela ainda é a responsável quando tira o time
    expect(chamadas).toEqual(['time', 'agente']);
  });

  it('atribuição por automação (sem nome) não mostra a faixa', async () => {
    const { wrapper } = montar({
      userId: 7,
      chat: { meta: { assignee: { id: 7 } } },
    });
    await flushPromises();
    expect(
      wrapper.find('[data-testid="cliente-faixa-atribuida"]').exists()
    ).toBe(false);
  });

  it('número novo: sem dados de cliente, encaminha ao comercial e Atribuir a… segue', async () => {
    const { wrapper } = montar({ dados: { cliente: false } });
    await flushPromises();
    expect(wrapper.text()).toContain('RAMON.CLIENTE_PANEL.NUMERO_NOVO');
    expect(wrapper.text()).not.toContain('RAMON.CLIENTE_PANEL.PROCESSOS');
    expect(wrapper.find('[data-testid="cliente-atribuir"]').exists()).toBe(
      true
    );
    await wrapper
      .find('[data-testid="lead-panel-encaminhar-comercial"]')
      .trigger('click');
    expect(wrapper.emitted('encaminhar')).toBeTruthy();
  });

  it('número novo já com responsável: sem o encaminhar', async () => {
    const { wrapper } = montar({
      dados: { cliente: false },
      chat: { meta: { team: { id: 2 } } },
    });
    await flushPromises();
    expect(
      wrapper.find('[data-testid="lead-panel-encaminhar-comercial"]').exists()
    ).toBe(false);
  });
});
