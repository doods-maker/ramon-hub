import { mount, flushPromises } from '@vue/test-utils';
import RamonAgenteExecucoesAPI from 'dashboard/api/ramonAgenteExecucoes';
import ExecucoesAgente from '../ExecucoesAgente.vue';

const push = vi.fn();
const dispatch = vi.fn();
vi.mock('vue-router', () => ({
  useRouter: () => ({ push }),
  useRoute: () => ({ query: {} }),
}));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch }),
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    accountScopedRoute: (name, params) => ({ name, params }),
  }),
}));
vi.mock('dashboard/api/ramonAgenteExecucoes', () => ({
  default: { list: vi.fn() },
}));

const ITEM = {
  id: 5,
  pedido: 'resuma o caso da Maria',
  status: 'erro',
  resumo: 'Não achei o processo no AdvBox.',
  acoes: [{ tipo: 'drive', ref: 'https://drive.google.com/x' }],
  modelo: 'opus',
  esforco: 'low',
  duracao_ms: 4200,
  lead_id: 123,
  lead_nome: 'Maria Souza',
  conversa_display_id: 482,
  created_at: '2026-10-07T12:00:00Z',
};
const montar = async (items = [ITEM]) => {
  RamonAgenteExecucoesAPI.list.mockResolvedValue({
    data: { resumo: { hoje: 4, teto: 30, problemas_hoje: 1 }, items },
  });
  const wrapper = mount(ExecucoesAgente);
  await flushPromises();
  return wrapper;
};

describe('ExecucoesAgente.vue', () => {
  it('mostra o uso de hoje e cada pedido com status, duração e modelo', async () => {
    const wrapper = await montar();
    expect(wrapper.find('[data-testid="agente-hoje"]').text()).toBe(
      'Today: 4 of 30 requests'
    );
    const linha = wrapper.find('[data-testid="agente-linha"]');
    expect(linha.text()).toContain('resuma o caso da Maria');
    expect(linha.text()).toContain('Error');
    expect(linha.text()).toContain('4 s');
    expect(linha.text()).toContain('opus · low');
  });

  it('ver resultado mostra a resposta e as ações', async () => {
    const wrapper = await montar();
    await wrapper.find('[data-testid="agente-ver"]').trigger('click');
    const detalhe = wrapper.find('[data-testid="agente-detalhe"]');
    expect(detalhe.text()).toContain('Não achei o processo no AdvBox.');
    expect(detalhe.text()).toContain('drive → https://drive.google.com/x');
  });

  it('caso clicável abre o Funil', async () => {
    const wrapper = await montar();
    await wrapper.find('[data-testid="execucoes-caso"]').trigger('click');
    expect(dispatch).toHaveBeenCalledWith('leads/select', 123);
  });

  it('sem pedidos: aviso', async () => {
    const wrapper = await montar([]);
    expect(wrapper.find('[data-testid="agente-vazio"]').exists()).toBe(true);
  });
});
