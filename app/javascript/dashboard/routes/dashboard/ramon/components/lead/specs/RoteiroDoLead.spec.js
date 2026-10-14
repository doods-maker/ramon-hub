import { mount, flushPromises } from '@vue/test-utils';
import LeadsAPI from 'dashboard/api/leads';
import RoteiroDoLead from '../RoteiroDoLead.vue';

vi.mock('dashboard/api/leads', () => ({
  default: { reabrirRoteiro: vi.fn() },
}));
const alertSpy = vi.fn();
vi.mock('dashboard/composables', () => ({
  useAlert: (...a) => alertSpy(...a),
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));

const linha = (chave, situacao, extra = {}) => ({
  chave,
  titulo: chave.toUpperCase(),
  comum: false,
  situacao,
  valor: null,
  saida: null,
  calc: null,
  ...extra,
});
const EM_ANDAMENTO = {
  desfecho: null,
  motivo: null,
  decisivo: null,
  aguarda_equipe: false,
  so_comuns: false,
  passos: [
    linha('tem_advogado', 'respondido', { valor: 'nao' }),
    linha('recebeu', 'respondido', { valor: 'sim' }),
    linha('nascimento', 'fora'),
    linha('renda', 'atual'),
    linha('moradores', 'pendente'),
  ],
};
const ENCERRADO = {
  ...EM_ANDAMENTO,
  desfecho: 'desqualificado',
  motivo: 'fora do período de graça',
  decisivo: 'graca',
  aguarda_equipe: true,
  passos: [
    linha('tem_advogado', 'respondido', { valor: 'nao' }),
    linha('graca', 'respondido', {
      valor: '2022-01-01',
      calc: { resultado: 'fora', detalhe: 'mais de 36 meses' },
    }),
    linha('renda', 'fora'),
  ],
};

const montar = props =>
  mount(RoteiroDoLead, { props, global: { mocks: { $t: k => k } } });
const titulos = w =>
  w.findAll('[data-testid="roteiro-passo"]').map(l => l.text());

describe('RoteiroDoLead', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('à vista só o atual e os a perguntar; respondidos atrás do toggle', async () => {
    const wrapper = montar({ roteiro: EM_ANDAMENTO, leadId: 7 });
    expect(titulos(wrapper)).toEqual(['RENDA', 'MORADORES']);
    expect(wrapper.find('[data-testid="roteiro-reabrir"]').exists()).toBe(
      false
    );
    await wrapper.find('[data-testid="roteiro-respondidos"]').trigger('click');
    expect(titulos(wrapper)).toHaveLength(5);
    expect(titulos(wrapper)[1]).toContain('sim');
  });

  it('desfecho com motivo e conta; reabrir confirma e devolve o painel novo', async () => {
    LeadsAPI.reabrirRoteiro.mockResolvedValue({ data: EM_ANDAMENTO });
    const wrapper = montar({ roteiro: ENCERRADO, leadId: 7 });
    expect(wrapper.find('[data-testid="roteiro-desfecho"]').text()).toContain(
      'fora do período de graça'
    );
    await wrapper.find('[data-testid="roteiro-respondidos"]').trigger('click');
    expect(wrapper.find('[data-testid="roteiro-calc"]').text()).toBe('fora');
    await wrapper.find('[data-testid="roteiro-reabrir"]').trigger('click');
    await wrapper
      .find('[data-testid="confirm-modal-confirm"]')
      .trigger('click');
    await flushPromises();
    expect(LeadsAPI.reabrirRoteiro).toHaveBeenCalledWith(7);
    expect(wrapper.emitted('reaberto')[0]).toEqual([EM_ANDAMENTO]);
  });

  it('lead perdido mostra a dica no lugar do botão; no Testar (sem lead) não há reabrir', () => {
    const perdido = montar({
      roteiro: ENCERRADO,
      leadId: 7,
      bloqueio: 'perdido',
    });
    expect(perdido.find('[data-testid="roteiro-bloqueio"]').exists()).toBe(
      true
    );
    expect(perdido.find('[data-testid="roteiro-reabrir"]').exists()).toBe(
      false
    );
    const testar = montar({ roteiro: ENCERRADO });
    expect(testar.text()).not.toContain('RAMON.ROTEIRO_IA.AGUARDA_EQUIPE');
    expect(perdido.text()).toContain('RAMON.ROTEIRO_IA.AGUARDA_EQUIPE');
    expect(testar.find('[data-testid="roteiro-reabrir"]').exists()).toBe(false);
    expect(testar.find('[data-testid="roteiro-bloqueio"]').exists()).toBe(
      false
    );
  });
});
