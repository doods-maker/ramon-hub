import { mount, flushPromises, RouterLinkStub } from '@vue/test-utils';
import HojeRecepcao from '../HojeRecepcao.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
const dispatch = vi.fn();
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch }),
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    accountScopedRoute: (name, params) => ({ name, params }),
  }),
}));

const agora = new Date().toISOString();
const recepcao = (extra = {}) => ({
  papel: 'recepcao',
  data: '2026-10-03',
  sem_responsavel: [],
  atendimentos: [],
  caixa: { sem_responsavel: 0, controladoria: 0, com_advogadas: 0 },
  advbox_fora: false,
  ...extra,
});

const montar = dados =>
  mount(HojeRecepcao, {
    props: { dados },
    global: { stubs: { 'router-link': RouterLinkStub } },
  });

describe('HojeRecepcao', () => {
  beforeEach(() => vi.clearAllMocks());

  it('ADVBOX fora: avisa no bloco e mantém "Sem responsável"', () => {
    const w = montar(
      recepcao({
        atendimentos: null,
        advbox_fora: true,
        sem_responsavel: [
          {
            conversa_id: 4,
            nome: 'Maria',
            telefone: '+5547999990000',
            cliente: true,
            ultima_mensagem: 'tem data da perícia?',
            esperando_desde: agora,
          },
        ],
      })
    );
    expect(w.find('[data-testid="advbox-fora"]').exists()).toBe(true);
    expect(w.text()).toContain('Maria');
    expect(w.text()).toContain('RAMON.HOJE.ATRIBUIR');
  });

  it('número novo: telefone no lugar do nome e Encaminhar ao comercial', async () => {
    dispatch.mockResolvedValue({});
    const w = montar(
      recepcao({
        sem_responsavel: [
          {
            conversa_id: 8,
            nome: null,
            telefone: '+5547997110042',
            cliente: false,
            ultima_mensagem: 'vocês atendem aposentadoria?',
            esperando_desde: agora,
          },
        ],
      })
    );
    expect(w.text()).toContain('+5547997110042');
    expect(w.text()).toContain('RAMON.HOJE.NUMERO_NOVO');
    await w.find('[data-testid="encaminhar-comercial"]').trigger('click');
    await flushPromises();
    expect(dispatch).toHaveBeenCalledWith('leads/encaminharComercial', {
      conversationId: 8,
    });
    expect(w.emitted('recarregar')).toHaveLength(1);
  });

  it('atendimentos: hora, com quem e a situação', () => {
    const w = montar(
      recepcao({
        atendimentos: [
          {
            advbox_post_id: 1,
            hora: '14:00',
            cliente_nome: 'Neusa',
            responsavel_advbox: 'Dra. Tamires',
            situacao: 'aguardando',
          },
          {
            advbox_post_id: 2,
            hora: null,
            cliente_nome: 'Roberto',
            situacao: 'nao_chegou',
          },
        ],
        caixa: { sem_responsavel: 3, controladoria: 5, com_advogadas: 11 },
      })
    );
    expect(w.text()).toContain('14:00');
    expect(w.text()).toContain('RAMON.HOJE.COM');
    expect(w.text()).toContain('RAMON.HOJE.AGUARDANDO');
    expect(w.text()).toContain('RAMON.HOJE.NAO_CHEGOU');
    expect(w.text()).toContain('11');
  });
});
